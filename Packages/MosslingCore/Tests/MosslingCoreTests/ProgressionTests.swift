import Foundation
import Testing
@testable import MosslingCore

func sampleOpportunity(hour: Int = 9, day: Int = 21) -> Opportunity {
    let dayKey = String(format: "2026-09-%02d", day)
    let date = utcDate("\(dayKey)T\(String(format: "%02d", hour)):00:00Z")
    return Opportunity(id: "\(dayKey)-m\(String(format: "%04d", hour * 60))", rewardKey: "\(dayKey)-h\(String(format: "%02d", hour))", scheduledAt: date, expiresAt: date.addingTimeInterval(3600), activity: .starters[0], dayKey: dayKey, minuteOfDay: hour * 60)
}
func sampleEvent(_ opportunity: Opportunity = sampleOpportunity(), id: UUID = UUID(), completedAt: Date? = nil) -> CompletionEvent {
    CompletionEvent(eventID: id, sessionID: UUID(), opportunityID: opportunity.id, rewardKey: opportunity.rewardKey, scheduledAt: opportunity.scheduledAt, completedAt: completedAt ?? opportunity.scheduledAt.addingTimeInterval(120), activity: opportunity.activity, sourceDeviceID: UUID())
}

@Suite("Timer and completion invariants")
struct SessionTests {
    @Test func pauseResumeAndPersistence() throws {
        let opportunity = sampleOpportunity(), start = sampleOpportunity().scheduledAt
        var session = SnackSession(opportunity: opportunity, activity: opportunity.activity)
        session.resume(at: start)
        session.resume(at: start.addingTimeInterval(10))
        session.pause(at: start.addingTimeInterval(30))
        session.pause(at: start.addingTimeInterval(60))
        #expect(session.elapsed(at: start.addingTimeInterval(300)) == 30)
        session = try JSONDecoder().decode(SnackSession.self, from: JSONEncoder().encode(session))
        session.resume(at: start.addingTimeInterval(300))
        #expect(session.elapsed(at: start.addingTimeInterval(390)) == 120)
        #expect(session.completed == false)
        try CompletionValidator.validate(session: session, completedAt: start.addingTimeInterval(390))
        session.markCompleted(at: start.addingTimeInterval(390))
        session.resume(at: start.addingTimeInterval(400))
        #expect(session.runningSince == nil)
        #expect(session.elapsed(at: start.addingTimeInterval(600)) == 120)
        #expect(throws: CompletionError.alreadyCompleted) { try CompletionValidator.validate(session: session, completedAt: start.addingTimeInterval(600)) }
    }

    @Test func incompleteExpiredAndFutureCompletionsRejected() throws {
        let opportunity = sampleOpportunity(), start = sampleOpportunity().scheduledAt
        var session = SnackSession(opportunity: opportunity, activity: opportunity.activity)
        session.resume(at: start)
        #expect(throws: CompletionError.notStarted) { try CompletionValidator.validate(session: session, completedAt: start.addingTimeInterval(-1)) }
        #expect(throws: CompletionError.timerIncomplete) { try CompletionValidator.validate(session: session, completedAt: start.addingTimeInterval(119)) }
        #expect(throws: CompletionError.expired) { try CompletionValidator.validate(session: session, completedAt: opportunity.expiresAt) }
        #expect(session.elapsed(at: start.addingTimeInterval(-60)) == 0)
    }

    @Test func repetitionsAreManualAndTargetIsSnapshotted() throws {
        let opportunity = sampleOpportunity()
        var activity = ActivityDefinition.starters[1]
        let session = SnackSession(opportunity: opportunity, activity: activity)
        activity.targetValue = 100
        #expect(session.activity.targetValue == 8)
        try CompletionValidator.validate(session: session, completedAt: opportunity.scheduledAt.addingTimeInterval(5))
    }
}

@Suite("Mergeable completion ledger")
struct LedgerTests {
    @Test func repeatedDeliveryAndTwoDevicesRewardOnce() {
        let first = sampleEvent(), second = sampleEvent()
        var ledger = CompletionLedger(events: [first, first])
        ledger.merge([second, first, second])
        #expect(ledger.events.count == 2)
        #expect(ledger.progress.completedSnackCount == 1)
        #expect(ledger.progress.growth == 10)
        #expect(ledger.containsReward(key: first.rewardKey))
    }

    @Test func mergingIsCommutativeAndConflictResolutionDeterministic() throws {
        let id = UUID(), opportunity = sampleOpportunity()
        let a = sampleEvent(opportunity, id: id)
        let b = sampleEvent(opportunity, id: id, completedAt: opportunity.scheduledAt.addingTimeInterval(180))
        let c = sampleEvent(sampleOpportunity(hour: 10))
        var first = CompletionLedger(events: [a]); first.merge([b, c])
        var second = CompletionLedger(events: [c, b]); second.merge([a])
        #expect(first == second)
        #expect(first.events.count == 2)
        let restored = try JSONDecoder().decode(CompletionLedger.self, from: JSONEncoder().encode(first))
        #expect(restored == first)
    }

    @Test func futureRelativeToCompletionAndMalformedKeysRejected() {
        let opportunity = sampleOpportunity()
        let future = sampleEvent(opportunity, completedAt: opportunity.scheduledAt.addingTimeInterval(-1))
        let malformed = CompletionEvent(sessionID: UUID(), opportunityID: opportunity.id, rewardKey: "fake", scheduledAt: opportunity.scheduledAt, completedAt: opportunity.scheduledAt, activity: opportunity.activity, sourceDeviceID: UUID())
        #expect(CompletionLedger(events: [future, malformed]).progress.growth == 0)
    }

    @Test func progressionUsesUniqueRewardKeysAndFixedThresholds() {
        let events = (0..<15).map { sampleEvent(sampleOpportunity(hour: 9 + ($0 % 8), day: 21 + ($0 / 8))) }
        #expect(CompletionLedger().progress.stage == .seedling)
        #expect(CompletionLedger(events: Array(events.prefix(2))).progress.stage == .seedling)
        let sprout = CompletionLedger(events: Array(events.prefix(3))).progress
        #expect(sprout.stage == .sprout)
        #expect(sprout.stageProgress == 0)
        #expect(sprout.nextStageGrowth == 150)
        #expect(CompletionLedger(events: Array(events.prefix(5))).progress.forestUnlocks == [.fern, .mushrooms])
        let guardian = CompletionLedger(events: events + events).progress
        #expect(guardian.growth == 150)
        #expect(guardian.completedSnackCount == 15)
        #expect(guardian.stage == .guardian)
        #expect(guardian.nextStageGrowth == 1_200)
        #expect(guardian.forestUnlocks == [.fern, .mushrooms, .pond])
        #expect(guardian.rewardRuleVersion == 1)
    }
}

@Suite("Permanent companion progression")
struct CompanionProgressionTests {
    private func history(_ count: Int) -> [CompletionEvent] {
        (0..<count).map { sampleEvent(sampleOpportunity(hour: 9 + ($0 % 8), day: 1 + ($0 / 8))) }
    }

    @Test(arguments: [1, 3, 5, 10, 15, 30, 60, 90, 120])
    func milestonesUnlockExactlyAtTheirThreshold(_ count: Int) throws {
        let expectedIDs = [1: "forest.fern", 3: "stage.sprout", 5: "forest.mushrooms",
            10: "forest.pond", 15: "stage.guardian", 30: "forest.wildflowers",
            60: "forest.steppingStones", 90: "forest.lanterns", 120: "stage.groveKeeper"]
        let events = history(count + 1)
        let before = CompletionLedger(events: Array(events.prefix(count - 1))).progress
        let at = CompletionLedger(events: Array(events.prefix(count))).progress
        let after = CompletionLedger(events: events).progress
        let id = try #require(expectedIDs[count])
        #expect(!before.unlockedMilestones.contains { $0.id == id })
        #expect(at.unlockedMilestones.contains { $0.id == id })
        #expect(after.unlockedMilestones.contains { $0.id == id })
        #expect(at.milestones(since: before).map(\.id) == [id])
        #expect(after.milestones(since: at).isEmpty)
        #expect(at.growth == count * 10)
        #expect(at.rewardRuleVersion == 1)
        #expect(at.catalogVersion == 2)
    }

    @Test func laterGrowthExtendsTheStoryWithoutTakingAwayLegacyStagesOrDecorations() {
        let events = history(121)
        let seedling = CompletionLedger().progress
        #expect(seedling.stage == .seedling)
        #expect(seedling.stageProgress == 0)
        #expect(seedling.nextMilestone?.id == "forest.fern")
        let guardian = CompletionLedger(events: Array(events.prefix(15))).progress
        #expect(guardian.stage == .guardian)
        #expect(guardian.forestUnlocks == [.fern, .mushrooms, .pond])
        #expect(guardian.stageProgress == 0)
        #expect(guardian.nextMilestone?.requiredSnackCount == 30)
        let almostKeeper = CompletionLedger(events: Array(events.prefix(119))).progress
        #expect(almostKeeper.stage == .guardian)
        #expect(almostKeeper.stageProgress > 0.99)
        #expect(almostKeeper.nextStageGrowth == 1_200)
        let keeper = CompletionLedger(events: Array(events.prefix(120))).progress
        #expect(keeper.stage == .groveKeeper)
        #expect(keeper.forestUnlocks == [.fern, .mushrooms, .pond, .wildflowers, .steppingStones, .lanterns])
        #expect(keeper.stageProgress == 1)
        #expect(keeper.nextStageGrowth == nil)
        #expect(keeper.nextMilestone == nil)
        #expect(CompletionLedger(events: events).progress.growth == 1_210)
        #expect(Set(ProgressionCatalog.milestones.map(\.id)).count == ProgressionCatalog.milestones.count)
    }

    @Test func offlineDuplicateRewardsAndMergeOrderNeverChangeMilestones() throws {
        let phoneEvents = history(120)
        let watchEvents = history(120) // Distinct event IDs for the same scheduled rewards.
        var phone = CompletionLedger(events: Array(phoneEvents.prefix(70)))
        phone.merge(watchEvents.reversed())
        phone.merge(phoneEvents)
        var watch = CompletionLedger(events: watchEvents)
        watch.merge(phoneEvents.reversed())
        watch.merge(watchEvents)
        #expect(phone == watch)
        #expect(phone.events.count == 240)
        #expect(phone.progress.completedSnackCount == 120)
        #expect(phone.progress.growth == 1_200)
        #expect(phone.progress.stage == .groveKeeper)
        let restored = try JSONDecoder().decode(CompletionLedger.self, from: JSONEncoder().encode(phone))
        #expect(restored.progress == phone.progress)
        #expect(restored.progress.milestones(since: phone.progress).isEmpty)
    }

    @Test func oldSavesKeepTheirProgressAndDefaultToNoAffinity() throws {
        let original = AppDocument(events: history(15))
        var json = try #require(JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        var configuration = try #require(json["configuration"] as? [String: Any])
        configuration.removeValue(forKey: "companionAffinity")
        configuration.removeValue(forKey: "dailyOverride")
        json["configuration"] = configuration
        json["schemaVersion"] = 1
        let restored = try AppDocument.decode(JSONSerialization.data(withJSONObject: json))
        #expect(restored.configuration.companionAffinity == nil)
        #expect(restored.events == original.events)
        #expect(CompletionLedger(events: restored.events).progress.stage == .guardian)
        #expect(CompletionLedger(events: restored.events).progress.forestUnlocks == [.fern, .mushrooms, .pond])
        #expect(CompletionLedger(events: restored.events).progress.canChooseAffinity)
        #expect(!CompletionLedger(events: history(2)).progress.canChooseAffinity)
        #expect(CompletionLedger(events: history(3)).progress.canChooseAffinity)
    }

    @Test func affinityIsReversiblePersistentAndPhoneAuthoritative() throws {
        var phone = AppConfiguration(companionAffinity: .sunlit)
        let authorityID = UUID()
        var watch = AppDocument()
        let firstSnapshot = ConfigurationSnapshot(configuration: phone, authorityID: authorityID)
        try DocumentSync.receive(ConfigurationSnapshot.decode(firstSnapshot.encoded()), into: &watch)
        #expect(watch.configuration.companionAffinity == .sunlit)
        phone.revision += 1
        phone.companionAffinity = .moonlit
        try DocumentSync.receive(ConfigurationSnapshot(configuration: phone, authorityID: authorityID), into: &watch)
        try DocumentSync.receive(firstSnapshot, into: &watch)
        #expect(watch.configuration.companionAffinity == .moonlit)
        #expect(try AppDocument.decode(watch.encoded()).configuration.companionAffinity == .moonlit)
        let backup = AppDocument(configuration: AppConfiguration(companionAffinity: .sunlit), events: history(3))
        try DocumentSync.mergeBackup(backup, into: &watch)
        #expect(watch.configuration.companionAffinity == .moonlit)
        #expect(CompletionLedger(events: watch.events).progress.growth == 30)
    }
}

@Suite("Started-session grace")
struct SessionGraceTests {
    @Test func lateStartHasPersistedFiveMinuteGraceAndExclusiveDeadline() throws {
        let opportunity = sampleOpportunity()
        let start = opportunity.expiresAt.addingTimeInterval(-30)
        let session = try SnackSession.start(opportunity: opportunity, activity: opportunity.activity, at: start)
        let restored = try AppDocument.decode(AppDocument(session: session).encoded()).session!
        #expect(restored.startedAt == start)
        #expect(restored.completionDeadline == opportunity.expiresAt.addingTimeInterval(300))
        try CompletionValidator.validate(session: restored, completedAt: start.addingTimeInterval(120))
        #expect(throws: CompletionError.expired) {
            try CompletionValidator.validate(session: restored, completedAt: restored.completionDeadline)
        }
    }

    @Test func futureExpiredAndImpossibleStartsAreRejected() throws {
        let opportunity = sampleOpportunity()
        #expect(throws: CompletionError.notStarted) {
            try SnackSession.start(opportunity: opportunity, activity: opportunity.activity, at: opportunity.scheduledAt.addingTimeInterval(-1))
        }
        #expect(throws: CompletionError.expired) {
            try SnackSession.start(opportunity: opportunity, activity: opportunity.activity, at: opportunity.expiresAt)
        }
        var longActivity = opportunity.activity
        longActivity.targetValue = 600
        #expect(throws: CompletionError.insufficientTime) {
            try SnackSession.start(opportunity: opportunity, activity: longActivity, at: opportunity.expiresAt.addingTimeInterval(-60))
        }
    }

    @Test func legacyAndInvalidStartsNeverReceiveGrace() throws {
        let opportunity = sampleOpportunity()
        var legacy = SnackSession(opportunity: opportunity, activity: opportunity.activity, accumulatedSeconds: 120)
        legacy.resume(at: opportunity.expiresAt.addingTimeInterval(-10))
        #expect(legacy.startedAt == nil)
        #expect(legacy.completionDeadline == opportunity.expiresAt)
        #expect(throws: CompletionError.expired) {
            try CompletionValidator.validate(session: legacy, completedAt: opportunity.expiresAt)
        }
        let invalid = SnackSession(opportunity: opportunity, activity: opportunity.activity,
            accumulatedSeconds: 120, startedAt: opportunity.expiresAt)
        #expect(invalid.completionDeadline == opportunity.expiresAt)
        #expect(throws: DocumentError.invalidDocument) { try AppDocument(session: invalid).validate() }
    }

    @Test func pausingAndReopeningCannotExtendGraceOrRewardTwice() throws {
        let opportunity = sampleOpportunity(), start = opportunity.expiresAt.addingTimeInterval(-60)
        var session = try SnackSession.start(opportunity: opportunity, activity: opportunity.activity, at: start)
        session.pause(at: opportunity.expiresAt.addingTimeInterval(60))
        let deadline = session.completionDeadline
        session.resume(at: opportunity.expiresAt.addingTimeInterval(120))
        #expect(session.completionDeadline == deadline)
        var document = AppDocument(session: session)
        try document.configuration.pauseForToday(at: start, calendar: testCalendar())
        try document.configuration.skip(opportunity, at: start, calendar: testCalendar())
        try DocumentSync.complete(session, at: opportunity.expiresAt.addingTimeInterval(121), in: &document)
        #expect(CompletionLedger(events: document.events).progress.growth == 10)
        #expect(throws: CompletionError.alreadyCompleted) {
            try DocumentSync.complete(session, at: opportunity.expiresAt.addingTimeInterval(122), in: &document)
        }
    }
}
