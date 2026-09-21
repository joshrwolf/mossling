import Foundation
import Testing
@testable import MosslingCore

private final class MemoryRepository: DocumentRepository {
    var value: AppDocument?
    var shouldFail = false
    enum Failure: Error { case diskFull }
    func load() throws -> AppDocument? { value }
    func save(_ document: AppDocument) throws {
        if shouldFail { throw Failure.diskFull }
        value = document
    }
}

@Suite("Atomic document persistence")
struct PersistenceTests {
    @Test @MainActor func failedWriteDoesNotPublishMutation() throws {
        let repository = MemoryRepository()
        let controller = try DocumentController(repository: repository)
        let original = controller.document
        repository.shouldFail = true
        #expect(throws: MemoryRepository.Failure.self) {
            try controller.transact { $0.configuration.companionName = "Fern" }
        }
        #expect(controller.document == original)
        #expect(repository.value == original)
    }

    @Test @MainActor func invalidCandidateCannotReachDisk() throws {
        let repository = MemoryRepository()
        let controller = try DocumentController(repository: repository)
        let original = controller.document
        #expect(throws: (any Error).self) {
            try controller.transact { $0.pendingEventIDs = [UUID()] }
        }
        #expect(repository.value == original)
        #expect(controller.document == original)
    }

    @Test func unsupportedSchemaDoesNotOverwriteFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("forest.json")
        let future = Data("{\"schemaVersion\":999,\"unknownFutureField\":true}".utf8)
        try future.write(to: url)
        let repository = FileDocumentRepository(url: url)
        #expect(throws: DocumentError.unsupportedVersion(999)) { try repository.load() }
        #expect(try Data(contentsOf: url) == future)
    }

    @Test func malformedSaveIsNotReset() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("forest.json")
        let malformed = Data("not json".utf8)
        try malformed.write(to: url)
        #expect(throws: (any Error).self) { try FileDocumentRepository(url: url).load() }
        #expect(try Data(contentsOf: url) == malformed)
    }

    @Test func completeOutboxAndSessionRoundTrip() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9))!
        let opportunity = try #require(try ScheduleEngine(configuration: .standard).current(at: date, calendar: calendar))
        let activity = ActivityDefinition.starters[0]
        var session = SnackSession(opportunity: opportunity, activity: activity)
        session.resume(at: date)
        session.pause(at: date.addingTimeInterval(20))
        var document = AppDocument(session: session)
        let event = CompletionEvent(sessionID: session.id, opportunityID: opportunity.id, rewardKey: opportunity.rewardKey,
                                    scheduledAt: date, completedAt: date.addingTimeInterval(120),
                                    activity: activity, sourceDeviceID: document.deviceID)
        document.events = [event]
        document.pendingEventIDs = [event.eventID]
        let restored = try AppDocument.decode(document.encoded())
        #expect(restored == document)
        #expect(restored.session?.elapsed(at: date.addingTimeInterval(900)) == 20)
        #expect(restored.pendingEventIDs == [event.eventID])
    }

    @Test func atomicFileRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileDocumentRepository(url: folder.appendingPathComponent("forest.json"))
        #expect(try repository.load() == nil)
        let document = AppDocument()
        try repository.save(document)
        #expect(try repository.load() == document)
    }
}

@Suite("Save migrations")
struct MigrationTests {
    @Test func schemaOnePreservesStateWithoutInventingGraceOrOverrides() throws {
        let opportunity = sampleOpportunity(), event = sampleEvent(sampleOpportunity(hour: 10))
        let session = SnackSession(opportunity: opportunity, activity: opportunity.activity,
            accumulatedSeconds: 30, runningSince: opportunity.scheduledAt.addingTimeInterval(60))
        var original = AppDocument(events: [event], session: session, pendingEventIDs: [event.eventID], hasReceivedPhoneConfiguration: true)
        original.configurationAuthorityID = UUID()
        original.retiredConfigurationAuthorities = [UUID()]
        var legacy = try #require(try JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        legacy["schemaVersion"] = 1
        var configuration = try #require(legacy["configuration"] as? [String: Any])
        configuration.removeValue(forKey: "dailyOverride")
        legacy["configuration"] = configuration
        var legacySession = try #require(legacy["session"] as? [String: Any])
        legacySession.removeValue(forKey: "startedAt")
        legacy["session"] = legacySession
        let migrated = try AppDocument.decode(JSONSerialization.data(withJSONObject: legacy))
        original.hasReceivedPhoneConfiguration = false
        #expect(migrated == original)
        #expect(migrated.schemaVersion == AppDocument.currentSchemaVersion)
        #expect(migrated.session?.completionDeadline == opportunity.expiresAt)
        #expect(migrated.configuration.dailyOverride == nil)
        #expect(try AppDocument.decode(migrated.encoded()) == migrated)
    }

    @Test func schemaTwoPersistsOverridesAndExplicitStart() throws {
        let now = utcDate("2026-09-21T09:05:00Z")
        var document = AppDocument(session: try SnackSession.start(opportunity: sampleOpportunity(), activity: .starters[0], at: now))
        try document.configuration.skip(sampleOpportunity(), at: now, calendar: testCalendar())
        try document.configuration.pauseForToday(at: now, calendar: testCalendar())
        #expect(try AppDocument.decode(document.encoded()) == document)
        #expect(throws: DocumentError.unsupportedVersion(999)) {
            try AppDocument.decode(Data("{\"schemaVersion\":999}".utf8))
        }
    }
}
