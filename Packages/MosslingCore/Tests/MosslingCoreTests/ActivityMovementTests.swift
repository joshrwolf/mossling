import Foundation
import Testing
@testable import MosslingCore

@Suite("Activity illustration identity")
struct ActivityMovementTests {
    @Test func savedCopyDoesNotSelectTheNeutralPose() throws {
        for starter in ActivityDefinition.starters {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(starter)) as? [String: Any])
            json.removeValue(forKey: "movement")
            json["title"] = "Earlier name"
            json["instructions"] = "Earlier coaching copy."
            let saved = try JSONDecoder().decode(ActivityDefinition.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(saved.movement == starter.movement)
            #expect(saved.movement != .custom)
        }
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
        json["version"] = 1
        #expect(throws: SyncProtocolError.unsupportedVersion(1)) { try SyncPacket.decode(JSONSerialization.data(withJSONObject: json)) }
        var document = AppDocument()
        let packet = try SyncPacket.decode(SyncPacket.events([event]).encoded())
        try DocumentSync.receive(packet, into: &document)
        try DocumentSync.receive(packet, into: &document)
        #expect(document.events == [event])
        #expect(try SyncInventory(events: document.events) == SyncInventory(events: [event]))
    }
}
