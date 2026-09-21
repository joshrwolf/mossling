import Foundation
import Testing
@testable import MosslingCore

private final class TransactionRepository: DocumentRepository {
    var saved: AppDocument?
    var failWrites = false
    var successfulWrites: [AppDocument] = []
    enum Failure: Error { case diskFull }
    func load() throws -> AppDocument? { saved }
    func save(_ document: AppDocument) throws {
        if failWrites { throw Failure.diskFull }
        saved = document
        successfulWrites.append(document)
    }
}

private func readySession() -> SnackSession {
    let opportunity = sampleOpportunity()
    return SnackSession(opportunity: opportunity, activity: opportunity.activity,
                        accumulatedSeconds: Double(opportunity.activity.targetValue))
}

@Suite("Durable sync transactions")
struct DocumentSyncTests {
    @Test @MainActor func completionCommitsRewardOutboxAndSessionTogether() throws {
        let repository = TransactionRepository()
        let session = readySession()
        let controller = try DocumentController(repository: repository, initial: AppDocument(session: session))
        try controller.transact {
            try DocumentSync.complete(session, at: session.opportunity.scheduledAt.addingTimeInterval(120), in: &$0)
        }
        let event = try #require(controller.document.events.first)
        #expect(event.sessionID == session.id)
        #expect(controller.document.pendingEventIDs == [event.eventID])
        #expect(controller.document.session == nil)
        #expect(repository.saved == controller.document)
        #expect(repository.successfulWrites.count == 2)
        #expect(repository.successfulWrites.last?.events == [event])
        #expect(repository.successfulWrites.last?.pendingEventIDs == [event.eventID])
        #expect(repository.successfulWrites.last?.session == nil)
    }

    @Test @MainActor func failedCompletionPreservesSessionAndLeavesNoRewardOrOutbox() throws {
        let repository = TransactionRepository(), session = readySession()
        let controller = try DocumentController(repository: repository, initial: AppDocument(session: session))
        let original = controller.document
        repository.failWrites = true
        #expect(throws: TransactionRepository.Failure.self) {
            try controller.transact {
                try DocumentSync.complete(session, at: session.opportunity.scheduledAt.addingTimeInterval(120), in: &$0)
            }
        }
        #expect(controller.document == original)
        #expect(repository.saved == original)
        #expect(controller.document.events.isEmpty)
        #expect(controller.document.pendingEventIDs.isEmpty)
        #expect(controller.document.session == session)
    }

    @Test @MainActor func acknowledgmentCanBeIssuedOnlyAfterDurableReceive() throws {
        let repository = TransactionRepository()
        let controller = try DocumentController(repository: repository)
        let event = sampleEvent(), packet = SyncPacket.events([sampleEvent()])
        // Mirrors the platform adapter's actual ordering: transact, then enqueue ACK.
        func receiveAndAcknowledge(_ packet: SyncPacket) throws -> SyncPacket {
            try controller.transact { try DocumentSync.receive(packet, into: &$0) }
            return .acknowledgment(packet.events.map(\.eventID))
        }
        repository.failWrites = true
        var acknowledgment: SyncPacket?
        #expect(throws: TransactionRepository.Failure.self) { acknowledgment = try receiveAndAcknowledge(packet) }
        #expect(acknowledgment == nil)
        #expect(controller.document.events.isEmpty)
        #expect(repository.saved?.events.isEmpty == true)
        repository.failWrites = false
        acknowledgment = try receiveAndAcknowledge(.events([event]))
        #expect(acknowledgment?.acknowledgedIDs == [event.eventID])
        #expect(repository.saved?.events == [event])
        #expect(controller.document.pendingEventIDs.isEmpty)
    }

    @Test @MainActor func acknowledgmentRemovesOnlyPendingObligation() throws {
        let repository = TransactionRepository()
        let first = sampleEvent(), second = sampleEvent(sampleOpportunity(hour: 10))
        let initial = AppDocument(events: [first, second], pendingEventIDs: [first.eventID, second.eventID])
        let controller = try DocumentController(repository: repository, initial: initial)
        try controller.transact { try DocumentSync.receive(.acknowledgment([first.eventID, UUID()]), into: &$0) }
        #expect(controller.document.pendingEventIDs == [second.eventID])
        #expect(Set(controller.document.events.map(\.eventID)) == [first.eventID, second.eventID])
        #expect(CompletionLedger(events: controller.document.events).progress.growth == 20)
        // A repeated ACK is harmless and never deletes history.
        try controller.transact { try DocumentSync.receive(.acknowledgment([first.eventID]), into: &$0) }
        #expect(controller.document.pendingEventIDs == [second.eventID])
        #expect(controller.document.events.count == 2)
    }

    @Test @MainActor func failedAcknowledgmentWriteRetainsOutbox() throws {
        let repository = TransactionRepository(), event = sampleEvent()
        let initial = AppDocument(events: [event], pendingEventIDs: [event.eventID])
        let controller = try DocumentController(repository: repository, initial: initial)
        repository.failWrites = true
        #expect(throws: TransactionRepository.Failure.self) {
            try controller.transact { try DocumentSync.receive(.acknowledgment([event.eventID]), into: &$0) }
        }
        #expect(controller.document == initial)
        #expect(repository.saved == initial)
    }

    @Test @MainActor func initialRevisionZeroPhoneConfigurationAcceptedButStaleUpdatesIgnored() throws {
        let repository = TransactionRepository()
        let controller = try DocumentController(repository: repository)
        let authorityID = UUID()
        var phone = AppConfiguration.standard
        phone.companionName = "Fern"
        try controller.transact { try DocumentSync.receive(ConfigurationSnapshot(configuration: phone, authorityID: authorityID), into: &$0) }
        #expect(controller.document.configuration.companionName == "Fern")
        #expect(controller.document.hasReceivedPhoneConfiguration)
        phone.revision = 2; phone.companionName = "Clover"
        try controller.transact { try DocumentSync.receive(ConfigurationSnapshot(configuration: phone, authorityID: authorityID), into: &$0) }
        phone.revision = 1; phone.companionName = "Outdated"
        try controller.transact { try DocumentSync.receive(ConfigurationSnapshot(configuration: phone, authorityID: authorityID), into: &$0) }
        #expect(controller.document.configuration.revision == 2)
        #expect(controller.document.configuration.companionName == "Clover")
        // Equal revision is a replay of the authoritative content: the phone must
        // increment revision before changing its name or any other setting.
        phone.revision = 2; phone.companionName = "Clover"
        let beforeReplay = controller.document
        try controller.transact { try DocumentSync.receive(ConfigurationSnapshot(configuration: phone, authorityID: authorityID), into: &$0) }
        #expect(controller.document == beforeReplay)
    }

    @Test @MainActor func equalRevisionRefreshRepairsFieldsDiscardedByOlderWatchDecoder() throws {
        let repository = TransactionRepository(), authorityID = UUID()
        let phone = AppConfiguration(revision: 12, companionName: "Clover", companionAffinity: .moonlit)
        let event = sampleEvent()
        var savedWatch = AppDocument(configuration: phone, events: [event],
            pendingEventIDs: [event.eventID], hasReceivedPhoneConfiguration: true)
        savedWatch.configurationAuthorityID = authorityID
        // An older Watch understood the same wire/save versions but dropped the
        // then-unknown optional affinity field when persisting its own cache.
        var cachedJSON = try #require(try JSONSerialization.jsonObject(with: savedWatch.encoded()) as? [String: Any])
        var cachedConfiguration = try #require(cachedJSON["configuration"] as? [String: Any])
        cachedConfiguration.removeValue(forKey: "companionAffinity")
        cachedJSON["configuration"] = cachedConfiguration
        repository.saved = try AppDocument.decode(JSONSerialization.data(withJSONObject: cachedJSON))
        let controller = try DocumentController(repository: repository)
        #expect(controller.document.configuration.companionAffinity == nil)
        let snapshot = try ConfigurationSnapshot.decode(ConfigurationSnapshot(configuration: phone, authorityID: authorityID).encoded())
        try controller.transact { try DocumentSync.receive(snapshot, into: &$0) }
        #expect(controller.document == savedWatch)
        #expect(repository.saved == savedWatch)
        try controller.transact { try DocumentSync.receive(snapshot, into: &$0) }
        #expect(controller.document == savedWatch)
        var olderPhone = phone
        olderPhone.revision -= 1
        olderPhone.companionAffinity = nil
        try controller.transact {
            try DocumentSync.receive(ConfigurationSnapshot(configuration: olderPhone, authorityID: authorityID), into: &$0)
        }
        #expect(controller.document == savedWatch)
        let relaunched = try DocumentController(repository: repository)
        #expect(relaunched.document == savedWatch)
    }

    @Test @MainActor func phoneReinstallAcceptsNewAuthorityAndRejectsDelayedRetiredAuthority() throws {
        let repository = TransactionRepository()
        let controller = try DocumentController(repository: repository)
        let originalAuthority = UUID(), replacementAuthority = UUID()
        var oldPhone = AppConfiguration(revision: 42, companionName: "Old phone")
        try controller.transact {
            try DocumentSync.receive(ConfigurationSnapshot(configuration: oldPhone, authorityID: originalAuthority), into: &$0)
        }
        let replacement = AppConfiguration(revision: 0, companionName: "New phone")
        try controller.transact {
            try DocumentSync.receive(ConfigurationSnapshot(configuration: replacement, authorityID: replacementAuthority), into: &$0)
        }
        #expect(controller.document.configuration == replacement)
        #expect(controller.document.configurationAuthorityID == replacementAuthority)
        #expect(controller.document.retiredConfigurationAuthorities == [originalAuthority])
        // Queued old-device traffic must not revive an authority, even with a larger revision.
        oldPhone.revision = 100
        try controller.transact {
            try DocumentSync.receive(ConfigurationSnapshot(configuration: oldPhone, authorityID: originalAuthority), into: &$0)
        }
        #expect(controller.document.configuration == replacement)
        #expect(controller.document.configurationAuthorityID == replacementAuthority)
        #expect(controller.document.retiredConfigurationAuthorities == [originalAuthority])
        let restored = try DocumentController(repository: repository)
        #expect(restored.document.configurationAuthorityID == replacementAuthority)
        #expect(restored.document.retiredConfigurationAuthorities == [originalAuthority])
        try restored.transact {
            try DocumentSync.receive(ConfigurationSnapshot(configuration: oldPhone, authorityID: originalAuthority), into: &$0)
        }
        #expect(restored.document.configuration == replacement)
    }

    @Test @MainActor func peerCompletionClearsMatchingSessionWithoutCreatingOutbox() throws {
        let repository = TransactionRepository(), session = readySession()
        let event = sampleEvent(session.opportunity)
        let controller = try DocumentController(repository: repository, initial: AppDocument(session: session))
        try controller.transact { try DocumentSync.receive(.events([event]), into: &$0) }
        #expect(controller.document.session == nil)
        #expect(controller.document.events == [event])
        #expect(controller.document.pendingEventIDs.isEmpty)
        #expect(repository.saved?.session == nil)
        try controller.transact { try DocumentSync.receive(.events([event]), into: &$0) }
        #expect(controller.document.events == [event])
        #expect(CompletionLedger(events: controller.document.events).progress.growth == 10)
    }

    @Test @MainActor func unrelatedPeerCompletionPreservesActiveSession() throws {
        let repository = TransactionRepository(), session = readySession()
        let controller = try DocumentController(repository: repository, initial: AppDocument(session: session))
        try controller.transact { try DocumentSync.receive(.events([sampleEvent(sampleOpportunity(hour: 10))]), into: &$0) }
        #expect(controller.document.session == session)
    }

    @Test @MainActor func diskRestartRetainsPendingEventsUntilPersistedAcknowledgment() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileDocumentRepository(url: folder.appendingPathComponent("forest.json"))
        let session = readySession()
        let first = try DocumentController(repository: repository, initial: AppDocument(session: session))
        try first.transact {
            try DocumentSync.complete(session, at: session.opportunity.scheduledAt.addingTimeInterval(120), in: &$0)
        }
        let eventID = try #require(first.document.events.first?.eventID)
        let restarted = try DocumentController(repository: repository)
        #expect(restarted.document.pendingEventIDs == [eventID])
        #expect(restarted.document.session == nil)
        #expect(restarted.document.events == first.document.events)
        try restarted.transact { try DocumentSync.receive(.acknowledgment([eventID]), into: &$0) }
        let afterAcknowledgment = try DocumentController(repository: repository)
        #expect(afterAcknowledgment.document.pendingEventIDs.isEmpty)
        #expect(afterAcknowledgment.document.events.map(\.eventID) == [eventID])
        #expect(CompletionLedger(events: afterAcknowledgment.document.events).progress.growth == 10)
    }
}

@Suite("Phone-owned daily routine sync")
struct DailyRoutineSyncTests {
    @Test func upgradedWatchAcceptsEqualRevisionV2AndRejectsOldOrFutureWireVersions() throws {
        let authority = UUID(), now = utcDate("2026-09-21T09:05:00Z")
        var oldWatch = AppDocument(configuration: AppConfiguration(revision: 10), hasReceivedPhoneConfiguration: true)
        oldWatch.configurationAuthorityID = authority
        var oldJSON = try #require(try JSONSerialization.jsonObject(with: oldWatch.encoded()) as? [String: Any])
        oldJSON["schemaVersion"] = 1
        var watch = try AppDocument.decode(JSONSerialization.data(withJSONObject: oldJSON))
        var phone = AppConfiguration(revision: 10)
        try phone.pauseForToday(at: now, calendar: testCalendar())
        let snapshot = ConfigurationSnapshot(configuration: phone, authorityID: authority)
        try DocumentSync.receive(snapshot, into: &watch)
        #expect(watch.configuration.isPaused(at: now))
        #expect(watch.hasReceivedPhoneConfiguration)
        #expect(watch.retiredConfigurationAuthorities.isEmpty)
        phone.revision += 1
        phone.resumeToday(at: now)
        try DocumentSync.receive(ConfigurationSnapshot(configuration: phone, authorityID: authority), into: &watch)
        #expect(!watch.configuration.isPaused(at: now))
        #expect(watch.configuration.revision == 11)
        var wire = try #require(try JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        for version in [1, 2, 999] {
            wire["version"] = version
            let data = try JSONSerialization.data(withJSONObject: wire)
            #expect(throws: SyncProtocolError.unsupportedVersion(version)) { try ConfigurationSnapshot.decode(data) }
        }
    }

    @Test func overridesRoundTripAndStaleSnapshotCannotUndoPause() throws {
        let authority = UUID(), now = utcDate("2026-09-21T09:05:00Z")
        var phone = AppConfiguration.standard
        let initial = ConfigurationSnapshot(configuration: phone, authorityID: authority)
        let session = try SnackSession.start(opportunity: sampleOpportunity(), activity: .starters[0], at: now)
        var watch = AppDocument(session: session)
        try DocumentSync.receive(initial, into: &watch)
        try phone.skip(sampleOpportunity(), at: now, calendar: testCalendar())
        try phone.pauseForToday(at: now, calendar: testCalendar())
        phone.revision += 1
        let updated = try ConfigurationSnapshot.decode(ConfigurationSnapshot(configuration: phone, authorityID: authority).encoded())
        try DocumentSync.receive(updated, into: &watch)
        try DocumentSync.receive(initial, into: &watch)
        #expect(watch.configuration == phone)
        #expect(watch.configuration.isPaused(at: now))
        #expect(watch.configuration.isSkipped(sampleOpportunity(), at: now))
        #expect(watch.session == session)
        #expect(!watch.configuration.isPaused(at: utcDate("2026-09-22T00:00:00Z")))
        phone.resumeToday(at: now)
        phone.revision += 1
        try DocumentSync.receive(ConfigurationSnapshot(configuration: phone, authorityID: authority), into: &watch)
        #expect(!watch.configuration.isPaused(at: now))
        #expect(watch.configuration.isSkipped(sampleOpportunity(), at: now))
    }
}
