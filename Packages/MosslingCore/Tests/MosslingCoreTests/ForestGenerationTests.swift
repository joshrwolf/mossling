import Foundation
import Testing
@testable import MosslingCore

@Suite("Generated woodland")
struct ForestGenerationTests {
    @Test func seededLayoutsStayConnectedAndLeaveBuildingSpace() throws {
        var layouts = Set<String>()
        for seed in Array(UInt64(0)..<128) + [UInt64.max] {
            var world = try ForestWorld.generated(seed: seed)
            #expect(world == (try ForestWorld.generated(seed: seed)))
            try world.validate()
            let starter = try #require(world.placements.first)
            #expect(world.interactionCell(for: starter, from: ForestWorld.home) != nil)
            // A guaranteed 2x2 grass patch is usable even before expansion.
            try world.place(.pond, at: ForestCell(3, 0), growth: 100)
            try world.expand(.grove, growth: 100)
            try world.validate()
            #expect(world.path(from: ForestWorld.home, to: ForestCell(8, 4))?.contains(ForestLandscape.stairs) == true)
            layouts.insert(world.landscape.trees.map(\.id).sorted().joined() + world.landscape.water.map(\.id).sorted().joined() + starter.cell.id)
            let document = AppDocument(configuration: AppConfiguration(world: world))
            #expect(try AppDocument.decode(document.encoded()) == document)
            let snapshot = ConfigurationSnapshot(configuration: document.configuration, authorityID: document.deviceID)
            #expect(try ConfigurationSnapshot.decode(snapshot.encoded()) == snapshot)
        }
        #expect(layouts.count >= 20)
    }

    @Test func schemaThreeMigrationPreservesPlacedHabitatAndDeliveryState() throws {
        let opportunity = sampleOpportunity(), event = sampleEvent(opportunity)
        var original = AppDocument(events: [event], session: SnackSession(opportunity: opportunity, activity: opportunity.activity),
                                   pendingEventIDs: [event.eventID], hasReceivedPhoneConfiguration: true)
        original.configurationAuthorityID = UUID()
        original.retiredConfigurationAuthorities = [UUID()]
        try original.configuration.world.expand(.grove, growth: 30)
        try original.configuration.world.place(.stump, at: ForestCell(4, 3), growth: 0)
        var json = try #require(JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        json["schemaVersion"] = 3
        var config = try #require(json["configuration"] as? [String: Any])
        var world = try #require(config["world"] as? [String: Any])
        world.removeValue(forKey: "landscape")
        config["world"] = world
        json["configuration"] = config
        func withoutMovement(_ value: Any) -> Any {
            if let object = value as? [String: Any] {
                return object.filter { $0.key != "movement" }.mapValues(withoutMovement)
            }
            if let array = value as? [Any] { return array.map(withoutMovement) }
            return value
        }
        let migrated = try AppDocument.decode(JSONSerialization.data(withJSONObject: withoutMovement(json)))
        #expect(migrated == original)
        #expect(try SyncInventory(events: migrated.events) == SyncInventory(events: original.events))
    }

    @Test func malformedTerrainCannotEnterADocument() throws {
        let document = AppDocument()
        var json = try #require(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
        var config = try #require(json["configuration"] as? [String: Any])
        var world = try #require(config["world"] as? [String: Any])
        var landscape = try #require(world["landscape"] as? [String: Any])
        landscape["water"] = [["x": 2, "y": 2]]
        world["landscape"] = landscape; config["world"] = world; json["configuration"] = config
        #expect(throws: (any Error).self) { try AppDocument.decode(JSONSerialization.data(withJSONObject: json)) }
        landscape["water"] = [["x": 1, "y": 4], ["x": 1, "y": 4]]
        world["landscape"] = landscape; config["world"] = world; json["configuration"] = config
        #expect(throws: (any Error).self) { try AppDocument.decode(JSONSerialization.data(withJSONObject: json)) }
    }
}
