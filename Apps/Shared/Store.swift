import Foundation
import Observation
import MosslingCore

/// Phone config is authoritative; both devices own a durable completion ledger.
enum DeviceRole { case phone, watch }

@MainActor @Observable
final class MosslingStore {
    private var document: AppDocument
    private(set) var now = Date()
    @ObservationIgnored private let clock: () -> Date
    var currentDate: Date { clock() }
    private(set) var notificationCoverageEnd: Date?
    private(set) var isReady: Bool
    private(set) var status: String?
    var error: String?
    private(set) var notificationStatus = "Checking…"
    private(set) var celebrationID = 0
    private(set) var navigationRequest = 0
    let role: DeviceRole
    @ObservationIgnored private var controller: DocumentController?
    @ObservationIgnored private let connection = WatchConnectivityService()
    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored private var isPreview = false
    #if os(iOS)
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private var notificationTask: Task<Bool, Never>?
    #endif

    var configuration: AppConfiguration { document.configuration }
    var events: [CompletionEvent] { document.events }
    var session: SnackSession? { document.session }
    var progress: CompanionProgress { CompletionLedger(events: events).progress }
    var currentOpportunity: Opportunity? {
        guard isReady, role == .phone || document.hasReceivedPhoneConfiguration,
              let opportunity = try? ScheduleEngine(configuration: configuration).current(at: now, calendar: .current),
              !CompletionLedger(events: events).containsReward(key: opportunity.rewardKey) else { return nil }
        return opportunity
    }
    var nextOpportunity: Opportunity? {
        guard isReady, role == .phone || document.hasReceivedPhoneConfiguration else { return nil }
        return try? ScheduleEngine(configuration: configuration).next(after: now, calendar: .current)
    }

    private init(role: DeviceRole, controller: DocumentController?, failure: String? = nil, clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        self.now = clock()
        self.role = role
        self.controller = controller
        document = controller?.document ?? AppDocument()
        isReady = controller != nil
        error = failure
        if role == .watch { notificationStatus = "Reminders follow your iPhone" }
    }

    static func live(role: DeviceRole) -> MosslingStore {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            var documentURL = folder.appendingPathComponent("Mossling/forest-v1.json")
            #if DEBUG && targetEnvironment(simulator)
            // UI automation exercises real disk persistence in a separate namespace.
            // The reset flag can never remove a person's normal forest.
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                documentURL = folder.appendingPathComponent("MosslingUITests/forest-v1.json")
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset"),
                   FileManager.default.fileExists(atPath: documentURL.path) {
                    try FileManager.default.removeItem(at: documentURL)
                }
            }
            #endif
            let repository = FileDocumentRepository(url: documentURL)
            let controller = try DocumentController(repository: repository)
            var clock: () -> Date = Date.init
            #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing"),
               let index = arguments.firstIndex(of: "--ui-testing-now"), index + 1 < arguments.count,
               let seconds = Double(arguments[index + 1]), seconds.isFinite {
                let fixed = Date(timeIntervalSince1970: seconds)
                NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
                clock = { fixed }
            }
            #endif
            return MosslingStore(role: role, controller: controller, clock: clock)
        } catch {
            return MosslingStore(role: role, controller: nil,
                failure: "Your forest could not be opened. Existing data has been preserved. \(error.localizedDescription)")
        }
    }

    static func preview() -> MosslingStore {
        let store = MosslingStore(role: .phone, controller: try? DocumentController(repository: PreviewRepository()))
        store.isPreview = true
        return store
    }

    func bootstrap() async {
        guard isReady, !isPreview else { return }
        refresh()
        if !bootstrapped {
            bootstrapped = true
            connection.onReceive = { [weak self] data, channel in self?.receive(data, channel: channel) }
            connection.onResync = { [weak self] in self?.synchronize(includeInventory: true) }
            connection.onStateChange = { [weak self] in self?.updateSyncStatus() }
            connection.onError = { [weak self] message in self?.status = message }
            #if os(iOS)
            notifications.onAction = { [weak self] action in
                Task { @MainActor in await self?.handleNotification(action) }
            }
            #endif
        }
        connection.activate()
        #if os(iOS)
        await updateNotificationStatus()
        _ = await reconcileNotifications()
        #endif
    }

    func refresh() { now = clock() }
    func clearError() { error = nil }

    @discardableResult
    private func commit(_ mutation: (inout AppDocument) throws -> Void) -> Bool {
        guard let controller else { error = "Your forest is unavailable. Reopen the app after resolving the save error."; return false }
        do {
            try controller.transact(mutation)
            document = controller.document
            refresh()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveConfig(_ proposed: AppConfiguration) async -> Bool {
        guard role == .phone else { error = "Change activities and reminders on your iPhone."; return false }
        var next = proposed
        next.revision = configuration.revision + 1
        do { _ = try ConfigurationSnapshot(configuration: next, authorityID: document.deviceID).encoded() }
        catch { self.error = error.localizedDescription; return false }
        guard commit({ $0.configuration = next }) else { return false }
        synchronize(includeInventory: false)
        #if os(iOS)
        // Saving settings succeeds independently; a scheduling failure stays visible with retry on reopen.
        _ = await reconcileNotifications()
        #endif
        return true
    }

    @discardableResult
    func start(activity: ActivityDefinition) -> Bool {
        refresh()
        guard session == nil else { error = "Finish or close your current snack first."; return false }
        guard let opportunity = currentOpportunity else { error = "There is no open snack right now. The next one is a fresh start."; return false }
        guard configuration.activities.contains(where: { $0 == activity && $0.isEnabled }) else {
            error = "Choose an enabled activity from your library."; return false
        }
        let date = now
        do {
            let session = try SnackSession.start(opportunity: opportunity, activity: activity, at: date)
            return commit { $0.session = session }
        } catch { self.error = error.localizedDescription; return false }
    }

    var isPausedToday: Bool { configuration.isPaused(at: now) }
    var currentScheduledOpportunity: Opportunity? {
        guard isReady, role == .phone || document.hasReceivedPhoneConfiguration else { return nil }
        return try? ScheduleEngine(configuration: configuration).opportunities(on: now, calendar: .current)
            .first { $0.isActive(at: now) }
    }
    var isCurrentSkipped: Bool {
        guard let opportunity = currentScheduledOpportunity else { return false }
        return configuration.isSkipped(opportunity, at: now)
    }
    var isCurrentCompleted: Bool {
        guard let opportunity = currentScheduledOpportunity else { return false }
        return CompletionLedger(events: events).containsReward(key: opportunity.rewardKey)
    }

    func skipCurrentSnack() async {
        refresh()
        guard role == .phone, session == nil, let opportunity = currentOpportunity else { return }
        var next = configuration
        do { try next.skip(opportunity, at: now, calendar: .current) }
        catch { self.error = error.localizedDescription; return }
        _ = await saveConfig(next)
    }

    func pauseToday() async {
        refresh()
        guard role == .phone else { return }
        var next = configuration
        do { try next.pauseForToday(at: now, calendar: .current) }
        catch { self.error = error.localizedDescription; return }
        _ = await saveConfig(next)
    }

    func resumeToday() async {
        refresh()
        guard role == .phone else { return }
        var next = configuration
        next.resumeToday(at: now)
        _ = await saveConfig(next)
    }

    func pause() { let date = clock(); _ = commit { $0.session?.pause(at: date) } }
    func resume() { let date = clock(); _ = commit { $0.session?.resume(at: date) } }
    func cancelSession() { _ = commit { $0.session = nil } }

    @discardableResult
    func complete() async -> Bool {
        guard let session else { return false }
        let date = clock()
        guard commit({ try DocumentSync.complete(session, at: date, in: &$0) }) else { return false }
        celebrationID += 1
        synchronize(includeInventory: false)
        #if os(iOS)
        _ = await notificationOperation { [notifications] in
            notifications.markCompleted(opportunityID: session.opportunity.id)
        }
        _ = await reconcileNotifications()
        #endif
        return true
    }

    func snooze() async {
        refresh()
        guard let opportunity = currentOpportunity else { error = "This snack is no longer available to snooze."; return }
        #if os(iOS)
        _ = await notificationOperation { [weak self, notifications] in
            guard let self, self.currentOpportunity?.id == opportunity.id else { return }
            let until = self.clock().addingTimeInterval(600)
            try await notifications.snooze(opportunity: opportunity, until: until)
            self.status = "A gentle reminder in 10 minutes."
        }
        #else
        error = "Snooze this reminder on your iPhone. Your watch can start and finish snacks."
        #endif
    }

    func requestNotificationPermission() async {
        #if os(iOS)
        _ = await notificationOperation { [notifications] in _ = try await notifications.requestAuthorization() }
        await updateNotificationStatus()
        _ = await reconcileNotifications()
        #endif
    }

    func exportData() throws -> Data {
        guard isReady else { throw DocumentError.invalidDocument }
        return try document.encoded()
    }

    /// Recovery is a merge, never a replacement of this installation's identity/settings.
    @discardableResult
    func importData(_ data: Data) async -> Bool {
        guard role == .phone else { return false }
        do {
            guard data.count <= 20 * 1_024 * 1_024 else {
                error = "This backup is too large to open. Choose a Mossling JSON backup under 20 MB."
                return false
            }
            let backup = try AppDocument.decode(data)
            guard commit({ try DocumentSync.mergeBackup(backup, into: &$0) }) else { return false }
            synchronize(includeInventory: true)
            #if os(iOS)
            _ = await reconcileNotifications()
            #endif
            status = "Backup merged. Your current schedule and activities are unchanged."
            return true
        } catch { self.error = "The backup could not be opened. Your current forest is unchanged. \(error.localizedDescription)"; return false }
    }

    // MARK: Durable, bounded synchronization
    private func synchronize(includeInventory: Bool) {
        guard isReady, connection.state == .ready else { updateSyncStatus(); return }
        do {
            if role == .phone { try connection.sendSnapshot(ConfigurationSnapshot(configuration: configuration, authorityID: document.deviceID).encoded()) }
            let pending = Set(document.pendingEventIDs)
            for batch in try SyncBatcher.batches(events: events.filter { pending.contains($0.eventID) }) {
                try connection.sendEvents(batch.encoded())
            }
            if includeInventory { try connection.sendEvents(SyncPacket.historyRequest(for: events).encoded()) }
            updateSyncStatus()
        } catch { status = "Saved on this device. Sync will retry: \(error.localizedDescription)" }
    }

    private func receive(_ data: Data, channel: WatchConnectivityService.Channel) {
        guard isReady else { return }
        do {
            switch channel {
            case .snapshot:
                guard role == .watch else { return }
                let snapshot = try ConfigurationSnapshot.decode(data)
                guard commit({ try DocumentSync.receive(snapshot, into: &$0) }) else { return }
            case .events:
                let packet = try SyncPacket.decode(data)
                if packet.kind == .historyRequest {
                    if packet.inventory != (try SyncInventory(events: events)) {
                        for batch in try SyncBatcher.batches(events: events) { try connection.sendEvents(batch.encoded()) }
                    }
                    if role == .phone { try connection.sendSnapshot(ConfigurationSnapshot(configuration: configuration, authorityID: document.deviceID).encoded()) }
                    return
                }
                guard commit({ try DocumentSync.receive(packet, into: &$0) }) else { return }
                if packet.kind == .events {
                    // Only a successful atomic commit permits an application acknowledgment.
                    try connection.sendEvents(SyncPacket.acknowledgment(packet.events.map(\.eventID)).encoded())
                    #if os(iOS)
                    let receivedEvents = packet.events
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        _ = await self.notificationOperation { [notifications = self.notifications] in
                            for event in receivedEvents {
                                notifications.markCompleted(opportunityID: event.opportunityID)
                            }
                        }
                        _ = await self.reconcileNotifications()
                    }
                    #endif
                }
            }
            updateSyncStatus()
        } catch { self.error = "Sync was interrupted. Saved progress is retained and can be synchronized again. \(error.localizedDescription)" }
    }

    private func updateSyncStatus() {
        if role == .watch && !document.hasReceivedPhoneConfiguration {
            status = "Open Mossling on your iPhone to bring your forest over."
            return
        }
        switch connection.state {
        case .ready:
            status = document.pendingEventIDs.isEmpty ? nil : "Saved here · waiting to sync \(document.pendingEventIDs.count) snack(s)"
        case .waitingForCompanion:
            status = role == .phone ? nil : "Open the iPhone app to sync. Your progress is saved here."
        case .failed(let message): status = "Sync unavailable: \(message)"
        case .unsupported, .inactive, .activating:
            if !document.pendingEventIDs.isEmpty { status = "Saved here · sync pending" }
        }
    }

    #if os(iOS)
    private func notificationOperation(_ operation: @escaping @MainActor () async throws -> Void) async -> Bool {
        let previous = notificationTask
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            do { try await operation(); return true }
            catch { self?.error = "Reminder update failed. Reopen the app to retry. \(error.localizedDescription)"; return false }
        }
        notificationTask = task
        return await task.value
    }

    private func reconcileNotifications() async -> Bool {
        await notificationOperation { [weak self, notifications] in
            guard let self else { return }
            // Permission is opt-in. Passive reconciliation must not interrupt onboarding.
            self.notificationCoverageEnd = nil
            if self.configuration.schedule.enabled,
               !(await notifications.authorizationStatus()).canSchedule { return }
            let plan = try ReminderPlan(configuration: self.configuration, at: self.clock(), calendar: .current,
                                        completedRewardKeys: Set(self.events.map(\.rewardKey)))
            try await notifications.replaceSchedule(plan)
            if self.configuration.schedule.enabled { self.notificationCoverageEnd = plan.coverageEnd }
        }
    }

    private func updateNotificationStatus() async {
        switch await notifications.authorizationStatus() {
        case .notDetermined: notificationStatus = "Not requested"
        case .denied: notificationStatus = "Disabled in Settings"
        case .authorized: notificationStatus = "Enabled"
        case .provisional: notificationStatus = "Quiet delivery"
        case .ephemeral: notificationStatus = "Temporary permission"
        case .unknown: notificationStatus = "Unknown"
        }
    }

    private func handleNotification(_ action: NotificationService.Action) async {
        refresh()
        guard let opportunityID = action.opportunityID,
              let candidate = currentOpportunity, candidate.id == opportunityID,
              action.scheduledAt == candidate.scheduledAt else { return }
        navigationRequest += 1
        if action.kind == .snooze { await snooze() }
        // Home consumes this intent; notification actions never mark a snack complete.
    }
    #endif
}

private final class PreviewRepository: DocumentRepository {
    var document: AppDocument?
    func load() throws -> AppDocument? { document }
    func save(_ document: AppDocument) throws { self.document = document }
}
