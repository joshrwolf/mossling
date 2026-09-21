import Foundation
import Testing
@testable import MosslingCore

@Suite("Activity illustration identity")
struct ActivityMovementTests {
    @Test func savedCopyDoesNotSelectTheNeutralPose() throws {
        for starter in ActivityDefinition.catalog {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(starter)) as? [String: Any])
            json.removeValue(forKey: "movement")
            json["title"] = "Earlier name"
            json["instructions"] = "Earlier coaching copy."
            let saved = try JSONDecoder().decode(ActivityDefinition.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(saved.movement == starter.movement)
            #expect(saved.movement != .custom)
        }
    }

    @Test func catalogHasDistinctValidatedMovementsAndSurvivesTransport() throws {
        let catalog = ActivityDefinition.catalog
        #expect(catalog.count >= ActivityDefinition.starters.count + 12)
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        #expect(Set(catalog.map(\.movement)) == Set(ActivityMovement.allCases.filter { $0 != .custom }))
        #expect(Set(catalog.compactMap(\.catalogVariationID)).count == catalog.count)
        for activity in catalog {
            let configuration = AppConfiguration(activities: [activity])
            try configuration.validate()
            let snapshot = ConfigurationSnapshot(configuration: configuration, authorityID: UUID())
            #expect(try ConfigurationSnapshot.decode(snapshot.encoded()) == snapshot)
            let document = AppDocument(configuration: configuration)
            #expect(try AppDocument.decode(document.encoded()) == document)
            let opportunity = sampleOpportunity()
            let event = CompletionEvent(sessionID: UUID(), opportunityID: opportunity.id,
                rewardKey: opportunity.rewardKey, scheduledAt: opportunity.scheduledAt,
                completedAt: opportunity.scheduledAt.addingTimeInterval(120), activity: activity, sourceDeviceID: UUID())
            let packet = SyncPacket.events([event])
            #expect(try SyncPacket.decode(packet.encoded()).events == [event])
        }
    }

    @Test func versionFourUpgradePreservesChosenRotationAndGeneratedTerrain() throws {
        var configuration = AppConfiguration(world: try .generated(seed: 123))
        configuration.activities[0].title = "My walking route"
        configuration.activities[1].isEnabled = false
        let document = AppDocument(configuration: configuration)
        var fields = try #require(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
        fields["schemaVersion"] = 4
        let restored = try AppDocument.decode(JSONSerialization.data(withJSONObject: fields))
        #expect(restored == document)
        #expect(restored.configuration.activities == configuration.activities)
    }

    @Test func customMovementChoiceRoundTripsAndUnknownValuesFail() throws {
        var activity = ActivityDefinition(id: "my-exercise", title: "Desk push-ups", instructions: "Use stable support.", targetKind: .repetitions, targetValue: 8)
        #expect(activity.movement == .custom)
        activity.movement = .wallPush
        #expect(try JSONDecoder().decode(ActivityDefinition.self, from: JSONEncoder().encode(activity)) == activity)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as? [String: Any])
        json["movement"] = "unknown"
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ActivityDefinition.self, from: JSONSerialization.data(withJSONObject: json)) }
    }

    @Test func eventTransportRejectsAnOlderInventoryFormatAndReplayStaysIdempotent() throws {
        let event = sampleEvent(sampleOpportunity())
        var json = try #require(JSONSerialization.jsonObject(with: SyncPacket.events([event]).encoded()) as? [String: Any])
        json["version"] = 2
        #expect(throws: SyncProtocolError.unsupportedVersion(2)) { try SyncPacket.decode(JSONSerialization.data(withJSONObject: json)) }
        var document = AppDocument()
        let packet = try SyncPacket.decode(SyncPacket.events([event]).encoded())
        try DocumentSync.receive(packet, into: &document)
        try DocumentSync.receive(packet, into: &document)
        #expect(document.events == [event])
        #expect(try SyncInventory(events: document.events) == SyncInventory(events: [event]))
    }
}
