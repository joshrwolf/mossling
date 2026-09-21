import Foundation
import Testing
@testable import MosslingCore

@Suite("Buildable habitat")
struct ForestWorldTests {
    @Test func placingMovingAndRemovingPreservesInventoryAndConnectivity() throws {
        var world = ForestWorld()
        try world.place(.fern, at: ForestCell(4, 3), growth: 10)
        try world.place(.fern, at: ForestCell(4, 4), growth: 10)
        #expect(world.placements.filter { $0.kind == .fern }.count == 1)
        let fern = try #require(world.placements.first { $0.kind == .fern })
        let destination = try #require(world.interactionCell(for: fern, from: ForestWorld.home))
        let route = try #require(world.path(from: ForestWorld.home, to: destination))
        #expect(!route.contains(fern.cell))
        #expect(zip(route, route.dropFirst()).allSatisfy { world.canStep(from: $0.0, to: $0.1) })
        world.remove(.fern)
        #expect(!world.placements.contains { $0.kind == .fern })
        try world.validate()
    }
    @Test func invalidEditsAreAtomic() throws {
        var world = ForestWorld()
        let before = world
        #expect(throws: ForestWorldError.locked) { try world.place(.fern, at: ForestCell(4, 3), growth: 0) }
        #expect(throws: ForestWorldError.occupied) { try world.place(.fern, at: ForestCell(1, 1), growth: 10) }
        #expect(throws: ForestWorldError.occupied) { try world.place(.fern, at: ForestWorld.home, growth: 10) }
        #expect(throws: ForestWorldError.outsideHabitat) { try world.place(.fern, at: ForestCell(Int.max, 0), growth: 10) }
        #expect(throws: ForestWorldError.outsideHabitat) { try world.place(.pond, at: ForestCell(5, 4), growth: 100) }
        #expect(world == before)
        try world.place(.stump, at: ForestCell(3, 0), growth: 0)
        let moved = world
        #expect(throws: ForestWorldError.blockedPath) { try world.place(.fern, at: ForestCell(4, 1), growth: 10) }
        #expect(world == moved)
    }
    @Test func expansionRequiresGrowthAndRoutesThroughStairs() throws {
        var world = ForestWorld()
        #expect(throws: ForestWorldError.locked) { try world.expand(.grove, growth: 20) }
        #expect(!world.regions.contains(.grove))
        try world.expand(.grove, growth: 30)
        let route = try #require(world.path(from: ForestWorld.home, to: ForestCell(8, 4)))
        #expect(route.contains(ForestCell(6, 2)))
        #expect(zip(route, route.dropFirst()).allSatisfy { world.canStep(from: $0.0, to: $0.1) })
        try world.place(.pond, at: ForestCell(7, 3), growth: 100)
        try world.validate()
    }
    @Test func currentDocumentsRequireWorldAndMigrationPreservesDurableState() throws {
        let event = sampleEvent(sampleOpportunity())
        let original = AppDocument(events: [event], pendingEventIDs: [event.eventID])
        var json = try #require(try JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        var config = try #require(json["configuration"] as? [String: Any])
        config.removeValue(forKey: "world"); json["configuration"] = config
        #expect(throws: (any Error).self) { try AppDocument.decode(JSONSerialization.data(withJSONObject: json)) }
        json["schemaVersion"] = 2
        let migrated = try AppDocument.decode(JSONSerialization.data(withJSONObject: json))
        #expect(migrated == original)
        #expect(migrated.configuration.world == ForestWorld())
        #expect(try AppDocument.decode(migrated.encoded()) == migrated)
    }
    @Test func watchAcceptsLayoutBeforeHistoryAndRejectsStaleLayout() throws {
        let authority = UUID()
        var phone = AppConfiguration(revision: 2)
        try phone.world.expand(.grove, growth: 30)
        try phone.world.place(.fern, at: ForestCell(7, 3), growth: 30)
        var watch = AppDocument()
        try DocumentSync.receive(ConfigurationSnapshot.decode(ConfigurationSnapshot(configuration: phone, authorityID: authority).encoded()), into: &watch)
        #expect(watch.events.isEmpty)
        #expect(watch.configuration.world == phone.world)
        try DocumentSync.receive(ConfigurationSnapshot(configuration: AppConfiguration(revision: 1), authorityID: authority), into: &watch)
        #expect(watch.configuration.world == phone.world)
        try watch.validate()
    }
}
