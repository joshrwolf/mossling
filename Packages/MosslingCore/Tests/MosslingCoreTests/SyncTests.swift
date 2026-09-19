import Foundation
import Testing
@testable import MosslingCore

struct SyncTests {
    private func event(_ index: Int, instructions: String = "Move comfortably.") -> CompletionEvent {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
        let day = String(format: "%02d", index % 28 + 1)
        return CompletionEvent(
            eventID: id, sessionID: id, opportunityID: "2026-09-\(day)-m0540",
            rewardKey: "2026-09-\(day)-h09",
            scheduledAt: Date(timeIntervalSince1970: 1_789_000_000 + Double(index) * 3600),
            completedAt: Date(timeIntervalSince1970: 1_789_000_120 + Double(index) * 3600),
            activity: ActivityDefinition(id: "test", title: "Walk", instructions: instructions,
                                         targetKind: .duration, targetValue: 120),
            sourceDeviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    }

    @Test func packetsRoundTripAndBatchesAreBounded() throws {
        let events = (1...63).map { event($0) }
        let batches = try SyncBatcher.batches(events: events)
        #expect(batches.map(\.events.count) == [25, 25, 13])
        #expect(Set(batches.flatMap(\.events).map(\.eventID)) == Set(events.map(\.eventID)))
        for packet in batches {
            let data = try packet.encoded()
            #expect(data.count <= SyncPacket.maximumEncodedBytes)
            #expect(try SyncPacket.decode(data) == packet)
        }
        let ack = SyncPacket.acknowledgment([events[0].eventID, events[0].eventID])
        #expect(ack.acknowledgedIDs.count == 1)
        #expect(try SyncPacket.decode(ack.encoded()) == ack)
        let inventory = try SyncPacket.historyRequest(for: events)
        #expect(try SyncPacket.decode(inventory.encoded()) == inventory)
        #expect(try SyncBatcher.batches(events: []).isEmpty)
    }

    @Test func inventoryAndBatchesAreOrderIndependent() throws {
        let events = (1...35).map { event($0) }
        let reordered = Array(events.reversed())
        #expect(try SyncInventory(events: events) == SyncInventory(events: reordered))
        #expect(try SyncBatcher.batches(events: events).map { try $0.encoded() }
                == SyncBatcher.batches(events: reordered).map { try $0.encoded() })
        #expect(try SyncInventory(events: events) != SyncInventory(events: events + [event(99)]))
        #expect(try SyncInventory(events: [event(1)])
                != SyncInventory(events: [event(1, instructions: "Changed activity snapshot.")]))
    }

    @Test func duplicateDeliveryAndReorderedBatchesConverge() throws {
        let events = (1...60).map { event($0) }
        let batches = try SyncBatcher.batches(events: events)
        var receiver = CompletionLedger()
        for batch in batches.reversed() {
            let packet = try SyncPacket.decode(batch.encoded())
            receiver.merge(packet.events)
            receiver.merge(packet.events)
        }
        #expect(receiver == CompletionLedger(events: events))
        #expect(try SyncInventory(events: receiver.events) == SyncInventory(events: events))
    }

    @Test func corruptUnsupportedAndInvalidPacketsFailClosed() throws {
        let valid = try SyncPacket.events([event(1)]).encoded()
        let text = String(decoding: valid, as: UTF8.self)
        let future = Data(text.replacingOccurrences(of: "\"version\":1", with: "\"version\":99").utf8)
        #expect(throws: SyncProtocolError.unsupportedVersion(99)) { try SyncPacket.decode(future) }
        #expect(throws: (any Error).self) { try SyncPacket.decode(Data("not json".utf8)) }
        let invalidEvent = Data(text.replacingOccurrences(of: "2026-09-02-h09", with: "invalid-reward").utf8)
        #expect(throws: SyncProtocolError.invalidPacket) { try SyncPacket.decode(invalidEvent) }
        #expect(throws: SyncProtocolError.invalidPacket) {
            try SyncPacket.events([event(1), event(1)]).encoded()
        }
        #expect(throws: SyncProtocolError.invalidPacket) { try SyncPacket.events([]).encoded() }
        #expect(throws: SyncProtocolError.invalidPacket) {
            try SyncPacket.events((1...26).map { event($0) }).encoded()
        }
        #expect(throws: SyncProtocolError.invalidPacket) { try SyncPacket.acknowledgment([]).encoded() }
        #expect(throws: SyncProtocolError.payloadTooLarge(49_153)) {
            try SyncPacket.decode(Data(repeating: 32, count: 49_153))
        }
    }

    @Test func encodedBytesCanSplitBeforeEventCountLimit() throws {
        let events = (1...25).map { event($0, instructions: String(repeating: "🌿", count: 1000)) }
        let batches = try SyncBatcher.batches(events: events)
        #expect(batches.count > 1)
        #expect(batches.flatMap(\.events).count == events.count)
        for packet in batches { #expect(try packet.encoded().count <= SyncPacket.maximumEncodedBytes) }
    }

    @Test func oversizedSingleEventIsExplicitlyRejected() {
        // A combining sequence is one grapheme but many bytes: character validation
        // alone cannot establish a safe transport size.
        let oversized = event(1, instructions: "a" + String(repeating: "\u{301}", count: 25_000))
        #expect(throws: SyncProtocolError.singleEventTooLarge(oversized.eventID)) {
            try SyncBatcher.batches(events: [oversized])
        }
    }
}
