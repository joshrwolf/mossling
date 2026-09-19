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
        #expect(guardian.nextStageGrowth == nil)
        #expect(guardian.forestUnlocks == [.fern, .mushrooms, .pond])
        #expect(guardian.rewardRuleVersion == 1)
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
