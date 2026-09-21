import Foundation
import Testing
@testable import MosslingCore

@Suite("Activity families and variations")
struct ActivityCatalogTests {
    @Test func completeCatalogHasStableDistinctVariationsAndEveryMovement() throws {
        #expect(ActivityFamily.allCases.count == 13)
        #expect(ActivityCatalog.variations.count == 33)
        #expect(Set(ActivityCatalog.variations.map(\.id)).count == 33)
        #expect(Set(ActivityCatalog.variations.map(\.movement)) == Set(ActivityMovement.allCases.filter { $0 != .custom }))
        for family in ActivityFamily.allCases {
            #expect(family.variations.count >= 2)
            #expect(Set(family.variations.map(\.label)).count == family.variations.count)
            for variation in family.variations {
                try variation.activity.validate()
                #expect(variation.activity.family == family)
                #expect(!variation.equipment.isEmpty)
            }
        }
        #expect(Set(ActivityCatalog.templates.map(\.id)).isSubset(of: Set(ActivityCatalog.variations.map(\.id))))
    }

    @Test func selectionKeepsRotationIdentityAndReplacesTheWholeMovementSnapshot() throws {
        var activity = ActivityFamily.pushUps.variations[0].activity
        activity.id = "my-stable-rotation-slot"
        activity.title = "My custom title"
        activity.targetValue = 14
        activity.isEnabled = false
        let floor = try #require(ActivityCatalog.variation(id: "floor-push"))
        let selected = activity.selecting(floor)
        #expect(selected.id == activity.id)
        #expect(!selected.isEnabled)
        #expect(selected.catalogVariationID == floor.id)
        #expect(selected.title == floor.title)
        #expect(selected.instructions == floor.instructions)
        #expect(selected.targetValue == floor.targetValue)
        #expect(selected.movement == .floorPush)
        #expect(selected.targetKind == floor.targetKind)
    }

    @Test func duplicateFamiliesAreRejectedButCustomArtDoesNotImplyMembership() throws {
        let wall = ActivityFamily.pushUps.variations[0].activity
        let floor = try #require(ActivityCatalog.variation(id: "floor-push")).activity
        #expect(throws: ConfigurationError.duplicateActivityFamilies) {
            try AppConfiguration(activities: [wall, floor]).validate()
        }
        var custom = floor
        custom.catalogVariationID = nil
        #expect(custom.family == nil)
        try AppConfiguration(activities: [wall, custom]).validate()
        var invalid = wall
        invalid.catalogVariationID = "not-a-variation"
        #expect(throws: ConfigurationError.invalidActivity(wall.id)) { try invalid.validate() }
        invalid.catalogVariationID = floor.id
        #expect(throws: ConfigurationError.invalidActivity(wall.id)) { try invalid.validate() }
        invalid = wall
        invalid.targetKind = .duration
        #expect(throws: ConfigurationError.invalidActivity(wall.id)) { try invalid.validate() }
    }

    @Test func schemaFiveFixtureConsolidatesOnlyRotationAndKeepsHistoricalBytes() throws {
        var activities = ActivityCatalog.templates
        let chair = try #require(activities.firstIndex { $0.movement == .chairStand })
        activities[chair].isEnabled = false
        let seatedMarch = try #require(activities.firstIndex { $0.movement == .seatedMarch })
        activities[seatedMarch].title = "Desk marching"
        activities[seatedMarch].targetValue = 90
        let custom = ActivityDefinition(id: "my-movement", title: "Desk press", instructions: "Use stable support.",
                                        targetKind: .repetitions, targetValue: 6, movement: .wallPush)
        activities.append(custom)
        let opportunity = sampleOpportunity()
        let eventActivity = try #require(activities.first { $0.movement == .stepJack })
        let event = CompletionEvent(sessionID: UUID(), opportunityID: opportunity.id,
            rewardKey: opportunity.rewardKey, scheduledAt: opportunity.scheduledAt,
            completedAt: opportunity.scheduledAt.addingTimeInterval(120), activity: eventActivity, sourceDeviceID: UUID())
        let sessionActivity = try #require(activities.first { $0.movement == .wallSlide })
        let session = try SnackSession.start(opportunity: opportunity, activity: sessionActivity, at: opportunity.scheduledAt)
        let fixture = AppDocument(configuration: AppConfiguration(activities: activities), events: [event],
                                  session: session, pendingEventIDs: [event.eventID])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(fixture)) as? [String: Any])
        json["schemaVersion"] = 5
        let inventory = try SyncInventory(events: [event])
        let restored = try AppDocument.decode(JSONSerialization.data(withJSONObject: json))
        #expect(restored.configuration.activities.count == 15)
        #expect(restored.configuration.activities.compactMap(\.family).count == 13)
        #expect(restored.configuration.activities.first { $0.family == .squats }?.movement == .miniSquat)
        #expect(restored.configuration.activities.first { $0.family == .marching }?.movement == .march)
        #expect(restored.configuration.activities.first { $0.id == "seated-march" }?.catalogVariationID == nil)
        #expect(restored.configuration.activities.first { $0.id == "seated-march" }?.targetValue == 90)
        #expect(restored.configuration.activities.first { $0.id == custom.id } == custom)
        #expect(restored.events == [event])
        #expect(restored.session == session)
        #expect(restored.pendingEventIDs == [event.eventID])
        #expect(try SyncInventory(events: restored.events) == inventory)
        #expect(try AppDocument.decode(restored.encoded()) == restored)
    }

    @Test func editedTargetKindSurvivesMigrationAndNewFamilyCannotOverwriteIt() throws {
        var timedWall = try #require(ActivityCatalog.templates.first { $0.id == "wall-push" })
        timedWall.targetKind = .duration
        timedWall.targetValue = 60
        let migrated = ActivityCatalog.migratedRotation([timedWall])
        #expect(migrated == [timedWall])
        var configuration = AppConfiguration(activities: migrated)
        try configuration.validate()
        let newFamily = configuration.activityDraft(for: .pushUps)
        #expect(newFamily.id != timedWall.id)
        #expect(newFamily.family == .pushUps)
        configuration.activities.append(newFamily)
        try configuration.validate()
        #expect(configuration.activities.first == timedWall)
        #expect(configuration.activityDraft(for: .pushUps) == newFamily)
    }

    @Test func allDisabledFamilyRetainsFirstChoice() throws {
        var choices = ActivityCatalog.templates.filter { [.chairStand, .miniSquat].contains($0.movement) }
        for i in choices.indices { choices[i].isEnabled = false }
        let migrated = ActivityCatalog.migratedRotation(choices)
        #expect(migrated.count == 1)
        #expect(migrated.first?.movement == .chairStand)
        #expect(migrated.first?.isEnabled == false)
    }
}
