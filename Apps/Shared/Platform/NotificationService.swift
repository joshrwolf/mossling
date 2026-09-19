#if os(iOS)
import Foundation
import MosslingCore
@preconcurrency import UserNotifications

/// Owns phone reminders only. Apple Watch notification mirroring remains a system preference.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum Authorization: String, Sendable {
        case notDetermined, denied, authorized, provisional, ephemeral, unknown

        var canSchedule: Bool {
            self == .authorized || self == .provisional || self == .ephemeral
        }
    }

    struct Action: Sendable {
        enum Kind: Sendable { case open, snooze }
        let kind: Kind
        let requestIdentifier: String
        let deliveredAt: Date
        let opportunityID: String?
    }

    enum ServiceError: LocalizedError {
        case invalidSchedule, permissionRequired, expiredSnooze, snoozeCapacity

        var errorDescription: String? {
            switch self {
            case .invalidSchedule:
                "Reminders need unique weekday/time slots and at most 56 reminders per week."
            case .permissionRequired:
                "Allow notifications in Settings to receive movement reminders."
            case .expiredSnooze:
                "This snack cannot be snoozed beyond its next reminder or quiet hours."
            case .snoozeCapacity:
                "Too many snoozes are pending. Open the app to refresh your reminders."
            }
        }
    }

    var onAction: ((Action) -> Void)? {
        didSet {
            guard let onAction else { return }
            let actions = bufferedActions
            bufferedActions.removeAll()
            actions.forEach(onAction)
        }
    }

    private let center: UNUserNotificationCenter
    private var bufferedActions: [Action] = []
    private static let recurringPrefix = "mossling.reminder."
    private static let snoozePrefix = "mossling.snooze."
    private nonisolated static let category = "MOSSLING_SNACK"
    private nonisolated static let openAction = "MOSSLING_OPEN"
    private nonisolated static let snoozeAction = "MOSSLING_SNOOZE"
    private nonisolated static let opportunityKey = "mosslingOpportunityID"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    UNNotificationAction(identifier: Self.openAction, title: "Start snack", options: .foreground),
                    UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze", options: .foreground)
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    func authorizationStatus() async -> Authorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    func requestAuthorization() async throws -> Authorization {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    static func reminderIdentifier(for slot: RecurringSlot) -> String {
        recurringPrefix + slot.id
    }

    /// The store serializes reconciliation calls. UNUserNotificationCenter has no transaction API:
    /// an add failure may leave a partial schedule and must be shown and retried by the store.
    func replaceSchedule(_ slots: [RecurringSlot]) async throws {
        guard slots.count <= 56,
              Set(slots.map(\.id)).count == slots.count,
              slots.allSatisfy({ (1...7).contains($0.weekday) && (0..<1440).contains($0.minuteOfDay) }) else {
            throw ServiceError.invalidSchedule
        }
        if !slots.isEmpty {
            guard await authorizationStatus().canSchedule else { throw ServiceError.permissionRequired }
        }

        let desiredIDs = Set(slots.map(Self.reminderIdentifier))
        let previous = await center.pendingNotificationRequests()
        let previousRecurringIDs = Set(previous.filter {
            $0.identifier.hasPrefix(Self.recurringPrefix)
        }.map(\.identifier))
        let scheduleChanged = previousRecurringIDs != desiredIDs || slots.isEmpty
        let obsolete = previous.compactMap { request -> String? in
            if scheduleChanged, request.identifier.hasPrefix(Self.snoozePrefix) { return request.identifier }
            if request.identifier.hasPrefix(Self.recurringPrefix), !desiredIDs.contains(request.identifier) {
                return request.identifier
            }
            return nil
        }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        if scheduleChanged { center.removeDeliveredNotifications(withIdentifiers: obsolete) }

        for slot in slots {
            var components = DateComponents()
            // No fixed date/zone: reminder follows the phone's local calendar clock.
            components.weekday = slot.weekday
            components.hour = slot.minuteOfDay / 60
            components.minute = slot.minuteOfDay % 60
            components.second = 0
            let content = makeContent()
            let request = UNNotificationRequest(
                identifier: Self.reminderIdentifier(for: slot),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try await center.add(request)
        }
    }

    func snooze(opportunityID: String, until: Date, expiresAt: Date) async throws {
        guard !opportunityID.isEmpty, until > Date(), until < expiresAt else {
            throw ServiceError.expiredSnooze
        }
        guard await authorizationStatus().canSchedule else { throw ServiceError.permissionRequired }
        let identifier = Self.snoozePrefix + opportunityID
        let requests = await center.pendingNotificationRequests()
        let otherSnoozes = requests.filter {
            $0.identifier.hasPrefix(Self.snoozePrefix) && $0.identifier != identifier
        }
        guard otherSnoozes.count < 8 else { throw ServiceError.snoozeCapacity }
        let delay = until.timeIntervalSinceNow
        // Recheck after the authorization/pending-request suspension points.
        guard delay > 0, Date() < expiresAt else { throw ServiceError.expiredSnooze }
        let content = makeContent()
        content.userInfo = [Self.opportunityKey: opportunityID]
        try await center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        ))
    }

    func markCompleted(opportunityID: String, deliveredReminderID: String?) {
        let snoozeID = Self.snoozePrefix + opportunityID
        center.removePendingNotificationRequests(withIdentifiers: [snoozeID])
        var deliveredIDs = [snoozeID]
        if let deliveredReminderID { deliveredIDs.append(deliveredReminderID) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    private func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "A little movement, a little growth"
        content.body = "Your woodland friend is ready for a movement snack."
        content.categoryIdentifier = Self.category
        content.threadIdentifier = "mossling.snacks"
        content.sound = .default
        return content
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let kind: Action.Kind
        switch response.actionIdentifier {
        case Self.snoozeAction: kind = .snooze
        case Self.openAction, UNNotificationDefaultActionIdentifier: kind = .open
        default: return
        }
        // Extract Sendable values on the delegate's executor; never move an SDK response
        // object across actors or assert unchecked Sendable conformance.
        let action = Action(
            kind: kind,
            requestIdentifier: response.notification.request.identifier,
            deliveredAt: response.notification.date,
            opportunityID: response.notification.request.content.userInfo[Self.opportunityKey] as? String
        )
        await deliver(action)
    }

    private func deliver(_ action: Action) {
        if let onAction { onAction(action) }
        else { bufferedActions.append(action) }
    }
}
#endif
