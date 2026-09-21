import Foundation
import Dispatch
import Testing
import MosslingCore
@testable import MosslingApplication

@Suite("Application workflows", .timeLimit(.minutes(1)))
@MainActor
struct StoreTests {
    @Test func habitatEditsPersistAndStaleSettingsCannotReplaceThem() async throws {
        let h = try Harness(), store = try h.open()
        let draft = store.configuration
        #expect(!store.placeHabitat(.fern, at: ForestCell(4, 3)))
        #expect(!store.expandForest(.grove))
        #expect(store.placeHabitat(.stump, at: ForestCell(4, 3)))
        let world = store.configuration.world
        #expect(await store.saveConfig(draft))
        #expect(store.configuration.world == world)
        #expect(try h.open().configuration.world == world)
        #expect(store.progress.growth == 0)
        h.repository.failWrites = true
        h.connection.snapshots.removeAll()
        let before = store.configuration
        #expect(!store.placeHabitat(.stump, at: ForestCell(4, 4)))
        #expect(store.configuration == before)
        #expect(h.connection.snapshots.isEmpty)
        #expect(try h.saved().configuration == before)
    }

    @Test func habitatRestoreIsExplicitAtomicAndEntitlementChecked() async throws {
        let source = try Harness(), producer = try source.open()
        #expect(producer.placeHabitat(.stump, at: ForestCell(4, 4)))
        let data = try producer.exportData()
        let destination = try Harness(), receiver = try destination.open()
        #expect(await receiver.importData(data))
        #expect(receiver.configuration.world == ForestWorld())
        #expect(await receiver.importData(data, restoreHabitat: true))
        #expect(try destination.open().configuration.world == producer.configuration.world)
        var invalid = try AppDocument.decode(data)
        try invalid.configuration.world.expand(.grove, growth: 30)
        let before = try destination.saved()
        #expect(!(await receiver.importData(try invalid.encoded(), restoreHabitat: true)))
        #expect(try destination.saved() == before)
        destination.repository.failWrites = true
        #expect(!(await receiver.importData(try AppDocument().encoded(), restoreHabitat: true)))
        #expect(receiver.configuration == before.configuration)
    }

    @Test func watchCannotEditHabitat() throws {
        let h = try Harness(), watch = try h.open(role: .watch)
        #expect(!watch.placeHabitat(.stump, at: ForestCell(4, 3)))
        #expect(!watch.removeHabitat(.stump))
        #expect(!watch.expandForest(.grove))
        #expect(try h.saved().configuration.world == ForestWorld())
    }

    @Test func createdAndEditedActivityReopensWithoutDuplication() async throws {
        let h = try Harness()
        let store = try h.open()
        var config = store.configuration
        let activity = ActivityDefinition(id: "custom", title: "Kitchen wiggle",
            instructions: "Move gently to a favorite song.", targetKind: .duration, targetValue: 120)
        config.activities.append(activity)
        #expect(await store.saveConfig(config))
        let reopened = try h.open()
        #expect(reopened.configuration.activities.last == activity)
        #expect(reopened.configuration.revision == config.revision + 1)
        var edit = reopened.configuration
        edit.activities[edit.activities.count - 1].targetValue = 30
        #expect(await reopened.saveConfig(edit))
        let saved = try h.open().configuration
        #expect(saved.activities.filter { $0.id == activity.id }.count == 1)
        #expect(saved.activities.last?.targetValue == 30)
        #expect(saved.activities.last?.instructions == activity.instructions)
        #expect(saved.revision == config.revision + 2)
    }

    @Test func scheduleChangesReopenWithSelectedDaysAndInterval() async throws {
        let h = try Harness(), store = try h.open()
        var config = store.configuration
        config.schedule.weekdays.remove(2)
        config.schedule.intervalMinutes = 90
        #expect(await store.saveConfig(config))
        let saved = try h.open().configuration
        #expect(saved.schedule.weekdays == [3, 4, 5, 6])
        #expect(saved.schedule.intervalMinutes == 90)
        #expect(saved.revision == 1)
        #expect(try h.open().currentOpportunity == nil)
    }

    @Test func completionReopensWithOneRewardAndDurableOutbox() async throws {
        let h = try Harness(), store = try h.open()
        let activity = try #require(store.configuration.activities.first { $0.id == "wall-push" })
        #expect(store.start(activity: activity))
        let sessionID = try #require(store.session?.id)
        #expect(await store.complete())
        #expect(store.celebrationID == 1)
        #expect(store.session == nil)
        #expect(store.progress.growth == 10)
        let reopened = try h.open()
        #expect(reopened.session == nil)
        #expect(reopened.isCurrentCompleted)
        #expect(reopened.currentOpportunity == nil)
        #expect(reopened.events.count == 1)
        #expect(reopened.events.first?.sessionID == sessionID)
        #expect(reopened.progress.growth == 10)
        #expect(try h.saved().pendingEventIDs == reopened.events.map(\.eventID))
        #expect(!(await reopened.complete()))
        #expect(!reopened.start(activity: activity))
        #expect(reopened.celebrationID == 0)
        #expect(try h.saved().events.count == 1)
    }

    @Test func failedWritesDoNotPublishCelebrateOrSend() async throws {
        let h = try Harness(), store = try h.open()
        await store.bootstrap()
        let activity = try #require(store.configuration.activities.first { $0.targetKind == .repetitions })
        #expect(store.start(activity: activity))
        let before = try h.saved()
        h.connection.sent.removeAll()
        h.connection.snapshots.removeAll()
        h.repository.failWrites = true
        #expect(!(await store.complete()))
        #expect(store.session == before.session)
        #expect(store.events.isEmpty)
        #expect(store.progress.growth == 0)
        #expect(store.celebrationID == 0)
        #expect(store.celebrationMilestones.isEmpty)
        var config = store.configuration
        config.companionName = "Unsaved"
        #expect(!(await store.saveConfig(config)))
        #expect(store.configuration == before.configuration)
        #expect(store.error != nil)
        #expect(h.connection.sent.isEmpty)
        #expect(h.connection.snapshots.isEmpty)
        #expect(try h.saved() == before)
    }

    @Test func skipReopensButDoesNotSuppressNextOpportunity() async throws {
        let h = try Harness(), store = try h.open()
        await store.skipCurrentSnack()
        let reopened = try h.open()
        #expect(reopened.isCurrentSkipped)
        #expect(reopened.currentOpportunity == nil)
        h.now.addTimeInterval(3600)
        let next = try h.open()
        #expect(!next.isCurrentSkipped)
        #expect(next.currentOpportunity != nil)
        #expect(next.progress.growth == 0)
        #expect(next.events.isEmpty)
    }

    @Test func pauseAndResumePersistWithoutRewardingMovement() async throws {
        let h = try Harness(), store = try h.open()
        await store.pauseToday()
        let paused = try h.open()
        #expect(paused.isPausedToday)
        #expect(paused.currentOpportunity == nil)
        await paused.resumeToday()
        let resumed = try h.open()
        #expect(!resumed.isPausedToday)
        #expect(resumed.currentOpportunity != nil)
        #expect(resumed.events.isEmpty)
        #expect(resumed.progress.growth == 0)
    }

    @Test func affinityRequiresThreeCompletionsAndBothChoicesPersist() async throws {
        let h = try Harness()
        for index in 0..<3 {
            let store = try h.open()
            #expect(!store.progress.canChooseAffinity)
            await store.saveAffinity(.moonlit)
            #expect(store.configuration.companionAffinity == nil)
            let activity = try #require(store.configuration.activities.first { $0.targetKind == .repetitions })
            #expect(store.start(activity: activity))
            #expect(await store.complete())
            #expect(store.progress.growth == (index + 1) * 10)
            if index < 2 { h.now.addTimeInterval(3600) }
        }
        let earned = try h.open()
        #expect(earned.progress.canChooseAffinity)
        let events = earned.events
        await earned.saveAffinity(.moonlit)
        let moonlit = try h.open()
        #expect(moonlit.configuration.companionAffinity == .moonlit)
        await moonlit.saveAffinity(.sunlit)
        let sunlit = try h.open()
        #expect(sunlit.configuration.companionAffinity == .sunlit)
        #expect(sunlit.events == events)
        #expect(sunlit.progress.growth == 30)
    }

    @Test func saveAndCompletionReturnWhileRemindersAreSuspended() async throws {
        let h = try Harness(), store = try h.open()
        h.notifications.authorization = .authorized
        h.notifications.suspendReplacement = true
        // A regression that awaits delivery must fail, not strand a continuation
        // forever. This independent watchdog also releases failed-test teardown.
        let watchdog = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            Issue.record("Durable operations waited for suspended reminder delivery")
            h.notifications.release()
        }
        defer { watchdog.cancel(); h.notifications.release() }
        var config = store.configuration
        config.companionName = "Fern"
        #expect(await store.saveConfig(config))
        try await eventually { h.notifications.blocked != nil }
        let activity = try #require(store.configuration.activities.first { $0.targetKind == .repetitions })
        #expect(store.start(activity: activity))
        #expect(await store.complete())
        #expect(try h.saved().configuration.companionName == "Fern")
        #expect(try h.saved().events.count == 1)
        #expect(store.celebrationID == 1)
        #expect(h.notifications.operations == ["replace"])
        h.notifications.release()
        await store.bootstrap() // Waits behind the queued cleanup and reconciliation.
        #expect(Array(h.notifications.operations.prefix(3)) == ["replace", "complete", "replace"])
        #expect(h.notifications.plans.last?.opportunities.contains {
            $0.rewardKey == store.events.first?.rewardKey
        } == false)
    }

    @Test(arguments: ReminderAuthorization.allCases)
    func bootstrapNeverAsksPermissionAndMapsRealStatus(_ status: ReminderAuthorization) async throws {
        let h = try Harness(), store = try h.open()
        h.notifications.authorization = status
        await store.bootstrap()
        #expect(h.notifications.permissionRequests == 0)
        let labels: [ReminderAuthorization: String] = [
            .notDetermined: "Not requested", .denied: "Disabled in Settings", .authorized: "Enabled",
            .provisional: "Quiet delivery", .ephemeral: "Temporary permission", .unknown: "Unknown",
        ]
        #expect(store.notificationStatus == labels[status])
        #expect((store.notificationCoverageEnd != nil) == status.canSchedule)
        #expect(h.notifications.plans.isEmpty == !status.canSchedule)
    }

    @Test func blockingNotificationRemovalLeavesMainActorResponsiveAndPreservesOrdering() async throws {
        let h = try Harness(), store = try h.open()
        h.notifications.authorization = .authorized
        let mutations = NotificationMutationQueue()
        let release = DispatchSemaphore(value: 0)
        let (entered, continuation) = AsyncStream<Void>.makeStream()
        defer { release.signal(); continuation.finish(); h.notifications.onRemoval = nil }
        h.notifications.onRemoval = {
            await mutations.perform {
                #expect(!Thread.isMainThread, "Synchronous system IPC must not run on the UI thread")
                continuation.yield(())
                // This timeout runs on the worker itself: it still terminates a
                // regression that blocks MainActor and its own test watchdog.
                #expect(release.wait(timeout: .now() + 2) == .success,
                        "MainActor must remain able to release blocked notification IPC")
            }
        }
        let activity = try #require(store.configuration.activities.first { $0.targetKind == .repetitions })
        #expect(store.start(activity: activity))
        #expect(await store.complete())
        var iterator = entered.makeAsyncIterator()
        _ = await iterator.next()
        #expect(store.progress.growth == 10)
        #expect(try h.saved().events.count == 1)
        #expect(h.notifications.operations == ["complete"], "Replacement must wait for removal")
        release.signal() // Executed on MainActor while the worker is blocked.
        await store.bootstrap()
        #expect(Array(h.notifications.operations.prefix(3)) == ["complete", "removed", "replace"])
    }

    @Test func permissionIsRequestedOnlyByExplicitAction() async throws {
        let h = try Harness(), store = try h.open()
        await store.bootstrap()
        #expect(h.notifications.permissionRequests == 0)
        await store.requestNotificationPermission()
        #expect(h.notifications.permissionRequests == 1)
        #expect(store.notificationStatus == "Enabled")
        #expect(store.notificationCoverageEnd != nil)
    }

    @Test func reminderFailureInvalidatesCoverageWithoutUndoingDurableConfig() async throws {
        let h = try Harness(), store = try h.open()
        h.notifications.authorization = .authorized
        await store.bootstrap()
        #expect(store.notificationCoverageEnd != nil)
        h.notifications.failReplacement = true
        var config = store.configuration
        config.schedule.intervalMinutes = 90
        #expect(await store.saveConfig(config))
        #expect(store.notificationCoverageEnd == nil)
        await store.bootstrap()
        #expect(store.error?.contains("Reminder update failed") == true)
        #expect(store.notificationCoverageEnd == nil)
        #expect(try h.open().configuration.schedule.intervalMinutes == 90)
        h.notifications.failReplacement = false
        store.clearError()
        await store.bootstrap()
        #expect(store.error == nil)
        #expect(store.notificationCoverageEnd != nil)
    }

    @Test func receivedEventsAreSavedBeforeAcknowledgmentAndDuplicatesAreHarmless() async throws {
        let source = try Harness(), producer = try source.open()
        let activity = try #require(producer.configuration.activities.first { $0.targetKind == .repetitions })
        #expect(producer.start(activity: activity))
        #expect(await producer.complete())
        let event = try #require(producer.events.first)
        let packet = try SyncPacket.events([event]).encoded()
        let h = try Harness(), receiver = try h.open()
        await receiver.bootstrap()
        h.connection.sent.removeAll()
        h.repository.failWrites = true
        h.connection.onReceive?(packet, .events)
        #expect(receiver.events.isEmpty)
        #expect(h.connection.sent.isEmpty)
        h.repository.failWrites = false
        defer { h.connection.beforeSend = nil }
        h.connection.beforeSend = { data in
            let packet = try SyncPacket.decode(data)
            if packet.kind == .acknowledgment {
                #expect(try h.saved().events == [event])
            }
        }
        h.connection.onReceive?(packet, .events)
        h.connection.onReceive?(packet, .events)
        #expect(receiver.events == [event])
        #expect(receiver.progress.growth == 10)
        #expect(receiver.celebrationID == 0)
        #expect(h.connection.sent.count == 2)
        #expect(try SyncPacket.decode(h.connection.sent[0]).acknowledgedIDs == [event.eventID])
        #expect(try h.saved().pendingEventIDs.isEmpty)
        #expect(try h.open().events == [event])
    }

    @Test func watchCannotChangePhoneConfigurationOrRequestNotifications() async throws {
        let h = try Harness(), watch = try h.open(role: .watch)
        await watch.bootstrap()
        #expect(watch.currentOpportunity == nil)
        #expect(watch.notificationStatus == "Reminders follow your iPhone")
        #expect(!(await watch.saveConfig(.standard)))
        await watch.requestNotificationPermission()
        #expect(h.notifications.permissionRequests == 0)
        let config = AppConfiguration(revision: 3, companionName: "Fern")
        let snapshot = try ConfigurationSnapshot(configuration: config, authorityID: UUID()).encoded()
        h.connection.onReceive?(snapshot, .snapshot)
        #expect(watch.configuration == config)
        #expect(watch.currentOpportunity != nil)
        #expect(try h.open(role: .watch).configuration == config)
    }

    @Test func offlineWatchCompletionSurvivesUntilDurablePeerAcknowledgment() async throws {
        let h = try Harness(), watch = try h.open(role: .watch)
        await watch.bootstrap()
        let snapshot = try ConfigurationSnapshot(configuration: .standard, authorityID: UUID()).encoded()
        h.connection.onReceive?(snapshot, .snapshot)
        h.connection.state = .waitingForCompanion
        let activity = try #require(watch.configuration.activities.first { $0.targetKind == .repetitions })
        #expect(watch.start(activity: activity))
        #expect(await watch.complete())
        let event = try #require(watch.events.first)
        let reopened = try h.open(role: .watch)
        #expect(reopened.progress.growth == 10)
        #expect(reopened.session == nil)
        #expect(try h.saved().pendingEventIDs == [event.eventID])
        await reopened.bootstrap()
        h.connection.state = .ready
        h.connection.onResync?()
        #expect(try h.connection.sent.map(SyncPacket.decode).contains { $0.events == [event] })
        #expect(h.connection.snapshots.isEmpty, "Watch must never publish configuration")
        let acknowledgment = try SyncPacket.acknowledgment([event.eventID]).encoded()
        h.repository.failWrites = true
        h.connection.onReceive?(acknowledgment, .events)
        #expect(try h.saved().pendingEventIDs == [event.eventID])
        h.repository.failWrites = false
        h.connection.onReceive?(acknowledgment, .events)
        #expect(try h.saved().pendingEventIDs.isEmpty)
        #expect(try h.open(role: .watch).events == [event])
        #expect(h.notifications.operations.isEmpty)
    }

    @Test func liveCalendarProviderIsReevaluatedAfterTimezoneChange() throws {
        let h = try Harness(), store = try h.open()
        #expect(store.currentOpportunity != nil)
        h.calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!
        store.refresh()
        #expect(store.currentOpportunity == nil)
    }
}

@MainActor
private final class Harness {
    let folder: URL
    let repository: FallibleFileRepository
    let notifications = FakeReminders()
    let connection = FakeConnection()
    let time = TestTime()
    var now: Date { get { time.now } set { time.now = newValue } }
    var calendar: Calendar { get { time.calendar } set { time.calendar = newValue } }

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = FallibleFileRepository(url: folder.appendingPathComponent("forest.json"))
    }
    deinit { try? FileManager.default.removeItem(at: folder) }
    func open(role: DeviceRole = .phone) throws -> MosslingStore {
        MosslingStore(role: role, controller: try DocumentController(repository: repository),
            connection: connection, notifications: notifications, clock: { [time] in time.now },
            calendar: { [time] in time.calendar })
    }
    func saved() throws -> AppDocument { try #require(try repository.load()) }
}

@MainActor
private final class TestTime {
    var now = Date(timeIntervalSince1970: 1_789_985_100)
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

}

private final class FallibleFileRepository: DocumentRepository {
    enum Failure: Error { case diskFull }
    let file: FileDocumentRepository
    var failWrites = false
    init(url: URL) { file = FileDocumentRepository(url: url) }
    func load() throws -> AppDocument? { try file.load() }
    func save(_ document: AppDocument) throws {
        if failWrites { throw Failure.diskFull }
        try file.save(document)
    }
}

@MainActor
private final class FakeReminders: ReminderService {
    enum Failure: Error { case unavailable }
    var onAction: ((ReminderAction) -> Void)?
    var authorization: ReminderAuthorization = .notDetermined
    var permissionRequests = 0
    var plans: [ReminderPlan] = []
    var operations: [String] = []
    var suspendReplacement = false
    var failReplacement = false
    var blocked: CheckedContinuation<Void, Never>?
    var onRemoval: (() async -> Void)?
    func authorizationStatus() async -> ReminderAuthorization { authorization }
    func requestAuthorization() async throws -> ReminderAuthorization {
        permissionRequests += 1
        authorization = .authorized
        return authorization
    }
    func replaceSchedule(_ plan: ReminderPlan) async throws {
        operations.append("replace")
        if suspendReplacement { await withCheckedContinuation { blocked = $0 } }
        if failReplacement { throw Failure.unavailable }
        plans.append(plan)
    }
    func release() {
        suspendReplacement = false
        let continuation = blocked
        blocked = nil
        continuation?.resume()
    }
    func snooze(opportunity: Opportunity, until: Date) async throws { operations.append("snooze") }
    func markCompleted(opportunityID: String) async {
        operations.append("complete")
        if let onRemoval {
            await onRemoval()
            operations.append("removed")
        }
    }
}

@MainActor
private final class FakeConnection: CompanionConnection {
    var state: CompanionConnectionState = .ready
    var onReceive: ((Data, CompanionChannel) -> Void)?
    var onResync: (() -> Void)?
    var onError: ((String) -> Void)?
    var onStateChange: (() -> Void)?
    var sent: [Data] = []
    var snapshots: [Data] = []
    var beforeSend: ((Data) throws -> Void)?
    func activate() {}
    func sendSnapshot(_ data: Data) throws { snapshots.append(data) }
    func sendEvents(_ data: Data) throws {
        try beforeSend?(data)
        sent.append(data)
    }
}

@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition(), ContinuousClock.now < deadline { await Task.yield() }
    try #require(condition(), "The injected service must reach its suspension point")
}
