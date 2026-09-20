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
        let scheduledAt: Date?
    }

    enum ServiceError: LocalizedError {
        case invalidSchedule, permissionRequired, expiredSnooze, snoozeCapacity

        var errorDescription: String? {
            switch self {
            case .invalidSchedule:
                "Reminders need unique snack windows and at most 56 scheduled reminders."
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
    private static let legacyRecurringPrefix = "mossling.reminder."
    private static let datedPrefix = "mossling.dated."
    private static let snoozePrefix = "mossling.snooze."
    private nonisolated static let category = "MOSSLING_SNACK"
    private nonisolated static let openAction = "MOSSLING_OPEN"
    private nonisolated static let snoozeAction = "MOSSLING_SNOOZE"
    private nonisolated static let opportunityKey = "mosslingOpportunityID"
    private nonisolated static let scheduledKey = "mosslingScheduledAt"
    private nonisolated static let expiryKey = "mosslingExpiresAt"

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

    static func reminderIdentifier(for opportunityID: String) -> String {
        datedPrefix + opportunityID
    }

    /// Dated requests make skip/pause effective while the app is closed. The caller must expose
    /// the finite coverage and refresh on foreground; no background execution is assumed.
    /// The store serializes calls. An add failure leaves visible, retryable partial coverage.
    func replaceSchedule(_ plan: ReminderPlan) async throws {
        let opportunities = plan.opportunities
        guard opportunities.count <= 56,
              Set(opportunities.map(\.id)).count == opportunities.count,
              opportunities.allSatisfy({
                  !$0.id.isEmpty && $0.scheduledAt.timeIntervalSinceReferenceDate.isFinite
                      && $0.expiresAt.timeIntervalSinceReferenceDate.isFinite
                      && $0.scheduledAt < $0.expiresAt
              }) else { throw ServiceError.invalidSchedule }

        let desiredIDs = Set(opportunities.map { Self.reminderIdentifier(for: $0.id) })
        let previous = await center.pendingNotificationRequests()
        let observedAt = Date()
        let obsolete = previous.compactMap { request -> String? in
            if request.identifier.hasPrefix(Self.legacyRecurringPrefix) { return request.identifier }
            if request.identifier.hasPrefix(Self.datedPrefix), !desiredIDs.contains(request.identifier) {
                return request.identifier
            }
            if request.identifier.hasPrefix(Self.snoozePrefix) {
                // A routine horizon top-up must not cancel a legitimate current snooze.
                guard let current = plan.currentOpportunity,
                      request.identifier == Self.snoozePrefix + current.id,
                      let scheduled = request.content.userInfo[Self.scheduledKey] as? Double,
                      scheduled == current.scheduledAt.timeIntervalSince1970,
                      let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
                      let fireDate = trigger.nextTriggerDate(),
                      fireDate > observedAt, fireDate < current.expiresAt else { return request.identifier }
            }
            return nil
        }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)

        // Remove stale deliveries too, including old repeating notifications after migration.
        let deliveries = await center.deliveredNotifications()
        let activeID = plan.currentOpportunity?.id
        let staleDelivered = deliveries.compactMap { notification -> String? in
            let request = notification.request
            if request.identifier.hasPrefix(Self.legacyRecurringPrefix) { return request.identifier }
            guard request.identifier.hasPrefix(Self.datedPrefix) || request.identifier.hasPrefix(Self.snoozePrefix) else { return nil }
            guard let activeID,
                  request.content.userInfo[Self.opportunityKey] as? String == activeID,
                  let scheduled = request.content.userInfo[Self.scheduledKey] as? Double,
                  scheduled == plan.currentOpportunity?.scheduledAt.timeIntervalSince1970 else { return request.identifier }
            return nil
        }
        center.removeDeliveredNotifications(withIdentifiers: staleDelivered)

        if !opportunities.isEmpty {
            guard await authorizationStatus().canSchedule else { throw ServiceError.permissionRequired }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for opportunity in opportunities {
            // A reconciliation that crosses a boundary must not enqueue an overdue alert.
            guard opportunity.scheduledAt > Date() else { continue }
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: opportunity.scheduledAt)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            try await center.add(UNNotificationRequest(
                identifier: Self.reminderIdentifier(for: opportunity.id),
                content: makeContent(for: opportunity),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }
    }

    func snooze(opportunity: Opportunity, until: Date) async throws {
        guard !opportunity.id.isEmpty, until > Date(), until < opportunity.expiresAt else {
            throw ServiceError.expiredSnooze
        }
        guard await authorizationStatus().canSchedule else { throw ServiceError.permissionRequired }
        let identifier = Self.snoozePrefix + opportunity.id
        let requests = await center.pendingNotificationRequests()
        let otherSnoozes = requests.filter {
            $0.identifier.hasPrefix(Self.snoozePrefix) && $0.identifier != identifier
        }
        guard otherSnoozes.count < 8 else { throw ServiceError.snoozeCapacity }
        let delay = until.timeIntervalSinceNow
        guard delay > 0, Date() < opportunity.expiresAt else { throw ServiceError.expiredSnooze }
        try await center.add(UNNotificationRequest(
            identifier: identifier,
            content: makeContent(for: opportunity),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        ))
    }

    func markCompleted(opportunityID: String) {
        let identifiers = [Self.snoozePrefix + opportunityID, Self.reminderIdentifier(for: opportunityID)]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func makeContent(for opportunity: Opportunity) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "A little movement, a little growth"
        content.body = "Your woodland friend is ready for a movement snack."
        content.categoryIdentifier = Self.category
        content.threadIdentifier = "mossling.snacks"
        content.sound = .default
        content.userInfo = [
            Self.opportunityKey: opportunity.id,
            Self.scheduledKey: opportunity.scheduledAt.timeIntervalSince1970,
            Self.expiryKey: opportunity.expiresAt.timeIntervalSince1970
        ]
        return content
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let expires = notification.request.content.userInfo[Self.expiryKey] as? Double,
           Date().timeIntervalSince1970 >= expires { return [] }
        return [.banner, .sound]
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
        let scheduledTimestamp = response.notification.request.content.userInfo[Self.scheduledKey] as? Double
        let action = Action(
            kind: kind,
            requestIdentifier: response.notification.request.identifier,
            deliveredAt: response.notification.date,
            opportunityID: response.notification.request.content.userInfo[Self.opportunityKey] as? String,
            scheduledAt: scheduledTimestamp.map(Date.init(timeIntervalSince1970:))
        )
        await deliver(action)
    }

    private func deliver(_ action: Action) {
        if let onAction { onAction(action) }
        else { bufferedActions.append(action) }
    }
}
#endif
