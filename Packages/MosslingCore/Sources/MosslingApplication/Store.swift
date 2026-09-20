import Foundation
import Observation
import MosslingCore

/// Phone config is authoritative; both devices own a durable completion ledger.
public enum DeviceRole { case phone, watch }

@MainActor @Observable
public final class MosslingStore {
    private var document: AppDocument
    public private(set) var now = Date()
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    public var currentDate: Date { clock() }
    public private(set) var notificationCoverageEnd: Date?
    public private(set) var isReady: Bool
    public private(set) var status: String?
    public var error: String?
    public private(set) var notificationStatus = "Checking…"
    public private(set) var celebrationID = 0
    public private(set) var celebrationMilestones: [ProgressionMilestone] = []
    public private(set) var navigationRequest = 0
    public let role: DeviceRole
    @ObservationIgnored private var controller: DocumentController?
    @ObservationIgnored private let connection: (any CompanionConnection)?
    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored private let notifications: (any ReminderService)?
    @ObservationIgnored private var notificationTask: Task<Bool, Never>?

    public var configuration: AppConfiguration { document.configuration }
    public var events: [CompletionEvent] { document.events }
    public var session: SnackSession? { document.session }
    public var progress: CompanionProgress { CompletionLedger(events: events).progress }
    public var currentOpportunity: Opportunity? {
        guard isReady, role == .phone || document.hasReceivedPhoneConfiguration,
              let opportunity = try? ScheduleEngine(configuration: configuration).current(at: now, calendar: calendar()),
              !CompletionLedger(events: events).containsReward(key: opportunity.rewardKey) else { return nil }
        return opportunity
    }
    public var nextOpportunity: Opportunity? {
        guard isReady, role == .phone || document.hasReceivedPhoneConfiguration else { return nil }
        return try? ScheduleEngine(configuration: configuration).next(after: now, calendar: calendar())
    }

    public init(role: DeviceRole, controller: DocumentController?,
                connection: (any CompanionConnection)? = nil, notifications: (any ReminderService)? = nil,
                failure: String? = nil, clock: @escaping () -> Date = Date.init,
                calendar: @escaping () -> Calendar = { .current }) {
        self.clock = clock
        self.calendar = calendar
        self.connection = connection
        self.notifications = role == .phone ? notifications : nil
        self.now = clock()
        self.role = role
        self.controller = controller
        document = controller?.document ?? AppDocument()
        isReady = controller != nil
        error = failure
        if role == .watch { notificationStatus = "Reminders follow your iPhone" }
    }

    public func bootstrap() async {
        let interval = AppDiagnostics.begin("bootstrap")
        defer { AppDiagnostics.end(interval) }
        guard isReady else { return }
        refresh()
        if !bootstrapped {
            bootstrapped = true
            connection?.onReceive = { [weak self] data, channel in self?.receive(data, channel: channel) }
            connection?.onResync = { [weak self] in self?.synchronize(includeInventory: true) }
            connection?.onStateChange = { [weak self] in self?.updateSyncStatus() }
            connection?.onError = { [weak self] message in self?.status = message }
            notifications?.onAction = { [weak self] action in
                Task { @MainActor in await self?.handleNotification(action) }
            }
        }
        connection?.activate()
        await updateNotificationStatus()
        _ = await reconcileNotifications()
    }

    public func refresh() { now = clock() }
    public func clearError() { error = nil }

    @discardableResult
    private func commit(_ mutation: (inout AppDocument) throws -> Void) -> Bool {
        let interval = AppDiagnostics.begin("documentCommit")
        defer { AppDiagnostics.end(interval) }
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
    public func saveConfig(_ proposed: AppConfiguration) async -> Bool {
        guard role == .phone else { error = "Change activities and reminders on your iPhone."; return false }
        var next = proposed
        next.revision = configuration.revision + 1
        do { _ = try ConfigurationSnapshot(configuration: next, authorityID: document.deviceID).encoded() }
        catch { self.error = error.localizedDescription; return false }
        guard commit({ $0.configuration = next }) else { return false }
        synchronize(includeInventory: false)
        // The durable save is complete. A slow system notification service must not
        // hold the editor open; scheduling errors remain visible and retry on reopen.
        _ = enqueueNotificationReconciliation()
        return true
    }

    @discardableResult
    public func start(activity: ActivityDefinition) -> Bool {
        refresh()
        guard session == nil else { error = "Finish or close your current snack first."; return false }
        guard let opportunity = currentOpportunity else { error = "No snack is available right now."; return false }
        guard configuration.activities.contains(where: { $0 == activity && $0.isEnabled }) else {
            error = "Choose an enabled activity from your library."; return false
        }
        let date = now
        do {
            let session = try SnackSession.start(opportunity: opportunity, activity: activity, at: date)
            return commit { $0.session = session }
        } catch { self.error = error.localizedDescription; return false }
    }

    public var isPausedToday: Bool { configuration.isPaused(at: now) }
    public var currentScheduledOpportunity: Opportunity? {
        guard isReady, role == .phone || document.hasReceivedPhoneConfiguration else { return nil }
        return try? ScheduleEngine(configuration: configuration).opportunities(on: now, calendar: calendar())
            .first { $0.isActive(at: now) }
    }
    public var isCurrentSkipped: Bool {
        guard let opportunity = currentScheduledOpportunity else { return false }
        return configuration.isSkipped(opportunity, at: now)
    }
    public var isCurrentCompleted: Bool {
        guard let opportunity = currentScheduledOpportunity else { return false }
        return CompletionLedger(events: events).containsReward(key: opportunity.rewardKey)
    }

    public func skipCurrentSnack() async {
        refresh()
        guard role == .phone, session == nil, let opportunity = currentOpportunity else { return }
        var next = configuration
        do { try next.skip(opportunity, at: now, calendar: calendar()) }
        catch { self.error = error.localizedDescription; return }
        _ = await saveConfig(next)
    }

    public func pauseToday() async {
        refresh()
        guard role == .phone else { return }
        var next = configuration
        do { try next.pauseForToday(at: now, calendar: calendar()) }
        catch { self.error = error.localizedDescription; return }
        _ = await saveConfig(next)
    }

    public func resumeToday() async {
        refresh()
        guard role == .phone else { return }
        var next = configuration
        next.resumeToday(at: now)
        _ = await saveConfig(next)
    }

    public func saveAffinity(_ affinity: CompanionAffinity) async {
        guard role == .phone, progress.canChooseAffinity else { return }
        var next = configuration
        next.companionAffinity = affinity
        _ = await saveConfig(next)
    }

    public func pause() { let date = clock(); _ = commit { $0.session?.pause(at: date) } }
    public func resume() { let date = clock(); _ = commit { $0.session?.resume(at: date) } }
    public func cancelSession() { _ = commit { $0.session = nil } }

    @discardableResult
    public func complete() async -> Bool {
        let interval = AppDiagnostics.begin("completion")
        defer { AppDiagnostics.end(interval) }
        guard let session else { return false }
        let date = clock()
        let alreadyUnlocked = Set(progress.unlockedMilestones.map(\.id))
        guard commit({ try DocumentSync.complete(session, at: date, in: &$0) }) else { return false }
        celebrationMilestones = progress.unlockedMilestones.filter { !alreadyUnlocked.contains($0.id) }
        celebrationID += 1
        synchronize(includeInventory: false)
        if let notifications {
            _ = enqueueNotificationOperation {
                await notifications.markCompleted(opportunityID: session.opportunity.id)
            }
        }
        _ = enqueueNotificationReconciliation()
        return true
    }

    public func snooze() async {
        refresh()
        guard let opportunity = currentOpportunity else { error = "This snack is no longer available to snooze."; return }
        guard let notifications else {
            error = "Snooze this reminder on your iPhone. Your watch can start and finish snacks."
            return
        }
        _ = await notificationOperation { [weak self, notifications] in
            guard let self, self.currentOpportunity?.id == opportunity.id else { return }
            let until = self.clock().addingTimeInterval(600)
            try await notifications.snooze(opportunity: opportunity, until: until)
            self.status = "Reminder snoozed for 10 minutes."
        }
    }

    public func requestNotificationPermission() async {
        guard let notifications else { return }
        _ = await notificationOperation { [notifications] in _ = try await notifications.requestAuthorization() }
        await updateNotificationStatus()
        _ = await reconcileNotifications()
    }

    public func exportData() throws -> Data {
        guard isReady else { throw DocumentError.invalidDocument }
        return try document.encoded()
    }

    /// Recovery is a merge, never a replacement of this installation's identity/settings.
    @discardableResult
    public func importData(_ data: Data) async -> Bool {
        guard role == .phone else { return false }
        do {
            guard data.count <= 20 * 1_024 * 1_024 else {
                error = "This backup is too large to open. Choose a Mossling JSON backup under 20 MB."
                return false
            }
            let backup = try AppDocument.decode(data)
            guard commit({ try DocumentSync.mergeBackup(backup, into: &$0) }) else { return false }
            synchronize(includeInventory: true)
            _ = enqueueNotificationReconciliation()
            status = "Backup merged. Your current schedule and activities are unchanged."
            return true
        } catch { self.error = "The backup could not be opened. Your current forest is unchanged. \(error.localizedDescription)"; return false }
    }

    // MARK: Durable, bounded synchronization
    private func synchronize(includeInventory: Bool) {
        let interval = AppDiagnostics.begin("synchronize")
        defer { AppDiagnostics.end(interval) }
        guard isReady, let connection, connection.state == .ready else { updateSyncStatus(); return }
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

    private func receive(_ data: Data, channel: CompanionChannel) {
        guard isReady, let connection else { return }
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
                    let receivedEvents = packet.events
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        _ = await self.notificationOperation { [notifications = self.notifications] in
                            for event in receivedEvents {
                                await notifications?.markCompleted(opportunityID: event.opportunityID)
                            }
                        }
                        _ = await self.reconcileNotifications()
                    }
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
        guard let connection else { return }
        switch connection.state {
        case .ready:
            status = document.pendingEventIDs.isEmpty ? nil : "Saved here · waiting to sync \(document.pendingEventIDs.count) \(document.pendingEventIDs.count == 1 ? "snack" : "snacks")"
        case .waitingForCompanion:
            status = role == .phone ? nil : "Open the iPhone app to sync. Your progress is saved here."
        case .failed(let message): status = "Sync unavailable: \(message)"
        case .unsupported, .inactive, .activating:
            if !document.pendingEventIDs.isEmpty { status = "Saved here · sync pending" }
        }
    }

    private func notificationOperation(_ operation: @escaping @MainActor () async throws -> Void) async -> Bool {
        await enqueueNotificationOperation(operation).value
    }

    // Enqueue synchronously so post-commit work retains ordering without delaying
    // durable success. The store retains the tail; each task retains its predecessor.
    private func enqueueNotificationOperation(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Bool, Never> {
        let previous = notificationTask
        let queued = AppDiagnostics.begin("notificationQueueWait")
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            AppDiagnostics.end(queued)
            let interval = AppDiagnostics.begin("notificationOperation")
            defer { AppDiagnostics.end(interval) }
            do { try await operation(); return true }
            catch { self?.error = "Reminder update failed. Reopen the app to retry. \(error.localizedDescription)"; return false }
        }
        notificationTask = task
        return task
    }

    private func reconcileNotifications() async -> Bool {
        await enqueueNotificationReconciliation().value
    }

    private func enqueueNotificationReconciliation() -> Task<Bool, Never> {
        // Existing coverage describes the old configuration until this job succeeds.
        notificationCoverageEnd = nil
        return enqueueNotificationOperation { [weak self, notifications] in
            guard let self, let notifications else { return }
            // Permission is opt-in. Passive reconciliation must not interrupt onboarding.
            self.notificationCoverageEnd = nil
            if self.configuration.schedule.enabled,
               !(await notifications.authorizationStatus()).canSchedule { return }
            let plan = try ReminderPlan(configuration: self.configuration, at: self.clock(), calendar: self.calendar(),
                                        completedRewardKeys: Set(self.events.map(\.rewardKey)))
            try await notifications.replaceSchedule(plan)
            if self.configuration.schedule.enabled { self.notificationCoverageEnd = plan.coverageEnd }
        }
    }

    private func updateNotificationStatus() async {
        guard let notifications else { return }
        let interval = AppDiagnostics.begin("notificationStatusRefresh")
        defer { AppDiagnostics.end(interval) }
        switch await notifications.authorizationStatus() {
        case .notDetermined: notificationStatus = "Not requested"
        case .denied: notificationStatus = "Disabled in Settings"
        case .authorized: notificationStatus = "Enabled"
        case .provisional: notificationStatus = "Quiet delivery"
        case .ephemeral: notificationStatus = "Temporary permission"
        case .unknown: notificationStatus = "Unknown"
        }
        AppDiagnostics.event("notificationStatusPublished")
    }

    private func handleNotification(_ action: ReminderAction) async {
        refresh()
        guard let opportunityID = action.opportunityID,
              let candidate = currentOpportunity, candidate.id == opportunityID,
              action.scheduledAt == candidate.scheduledAt else { return }
        navigationRequest += 1
        if action.kind == .snooze { await snooze() }
        // Home consumes this intent; notification actions never mark a snack complete.
    }
}
