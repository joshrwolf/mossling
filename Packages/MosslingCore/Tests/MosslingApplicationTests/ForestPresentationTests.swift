import Foundation
import Testing
import MosslingCore
@testable import MosslingApplication

@Suite("Forest presentation")
struct ForestPresentationTests {
    private func snapshot(_ snacks: Int, affinity: CompanionAffinity? = nil) throws -> ForestSnapshot {
        var document = AppDocument()
        let activity = document.configuration.activities[1]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_789_981_200)
        for index in 0..<snacks {
            let date = start.addingTimeInterval(Double(index) * 3_600)
            let opportunity = try #require(try ScheduleEngine(configuration: document.configuration).current(at: date, calendar: calendar))
            let session = try SnackSession.start(opportunity: opportunity, activity: activity, at: date)
            document.session = session
            try DocumentSync.complete(session, at: date, in: &document)
        }
        return ForestSnapshot(progress: CompletionLedger(events: document.events).progress, affinity: affinity)
    }

    @Test func projectionRoundTripsEveryCellIncludingRaisedTerrain() {
        let cells = ForestRegion.allCases.flatMap(\.cells)
        for cell in cells {
            #expect(ForestProjection.cell(at: ForestProjection.point(for: cell), among: cells) == cell)
        }
        #expect(ForestProjection.cell(at: .init(x: 10000, y: 10000), among: cells) == nil)
    }

    @Test func openingAnEarnedForestDoesNotReplayRewards() throws {
        var playback = ForestPlayback()
        let state = try snapshot(3)
        let change = playback.receive(state, active: true, reduceMotion: false)
        #expect(change.to.stage == .sprout)
        #expect(change.moment == .none)
        #expect(change.discoveries.isEmpty)
    }

    @Test func fernSnackAndEvolutionHaveDistinctMoments() throws {
        var playback = ForestPlayback()
        _ = playback.receive(try snapshot(0), active: true, reduceMotion: false)
        let fern = playback.receive(try snapshot(1), active: true, reduceMotion: false)
        #expect(fern.moment == .discovery)
        #expect(fern.discoveries == [.fern])
        #expect(playback.receive(try snapshot(2), active: true, reduceMotion: false).moment == .snack)
        let evolution = playback.receive(try snapshot(3), active: true, reduceMotion: false)
        #expect(evolution.moment == .evolution)
        #expect(evolution.from?.stage == .seedling)
        #expect(evolution.to.stage == .sprout)
        #expect(playback.receive(try snapshot(3), active: true, reduceMotion: false).moment == .none)
    }

    @Test func completionBehindSessionSheetPlaysOnReturn() throws {
        var playback = ForestPlayback()
        _ = playback.receive(try snapshot(2), active: true, reduceMotion: false)
        #expect(playback.receive(try snapshot(3), active: false, reduceMotion: false).moment == .none)
        #expect(playback.receive(try snapshot(3), active: true, reduceMotion: false).moment == .evolution)
        _ = playback.receive(try snapshot(3), active: false, reduceMotion: false)
        #expect(playback.receive(try snapshot(3), active: true, reduceMotion: false).moment == .none)
    }

    @Test func reducedMotionAndAffinityChangesNeverReplayEvolution() throws {
        var playback = ForestPlayback()
        _ = playback.receive(try snapshot(0), active: true, reduceMotion: false)
        #expect(playback.receive(try snapshot(3), active: true, reduceMotion: true).moment == .none)
        #expect(playback.receive(try snapshot(3, affinity: .moonlit), active: true, reduceMotion: false).moment == .none)
        #expect(playback.receive(try snapshot(3), active: true, reduceMotion: false).moment == .none)
    }

    @Test func batchedProgressUsesOneEvolutionWithAllDiscoveries() throws {
        var playback = ForestPlayback()
        _ = playback.receive(try snapshot(0), active: true, reduceMotion: false)
        let change = playback.receive(try snapshot(5), active: true, reduceMotion: false)
        #expect(change.moment == .evolution)
        #expect(change.discoveries == [.fern, .mushrooms])
        #expect(change.to.growth == 50)
    }
}
