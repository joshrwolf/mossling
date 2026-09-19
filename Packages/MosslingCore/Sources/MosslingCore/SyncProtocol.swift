import Foundation

public enum SyncProtocolError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidPacket
    case payloadTooLarge(Int)
    case singleEventTooLarge(UUID)
}

/// A diagnostic inventory, not a cryptographic integrity check or an acknowledgment.
public struct SyncInventory: Codable, Equatable, Sendable {
    public let eventCount: Int
    public let digest: String

    public init(events: [CompletionEvent]) throws {
        let records = try events.map { try SyncCodec.encoder().encode($0) }
            .sorted { $0.lexicographicallyPrecedes($1) }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for record in records {
            // Length-prefix each record so record boundaries are unambiguous.
            var length = UInt64(record.count).bigEndian
            withUnsafeBytes(of: &length) { bytes in
                for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
            }
            for byte in record { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        }
        eventCount = events.count
        digest = String(repeating: "0", count: 16 - String(hash, radix: 16).count)
            + String(hash, radix: 16)
    }

    fileprivate var isValid: Bool {
        eventCount >= 0 && digest.utf8.count == 16
            && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Versioned transport data only. Receiving this value does not commit or acknowledge it.
public struct SyncPacket: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case events, acknowledgment, historyRequest }
    public static let protocolVersion = 1
    public static let maximumEncodedBytes = 48 * 1_024
    public static let maximumEvents = 25

    public let version: Int
    public let kind: Kind
    public let events: [CompletionEvent]
    public let acknowledgedIDs: [UUID]
    public let inventory: SyncInventory?

    private init(kind: Kind, events: [CompletionEvent] = [], acknowledgedIDs: [UUID] = [],
                 inventory: SyncInventory? = nil) {
        version = Self.protocolVersion
        self.kind = kind
        self.events = events
        self.acknowledgedIDs = acknowledgedIDs
        self.inventory = inventory
    }

    public static func events(_ events: [CompletionEvent]) -> Self {
        Self(kind: .events, events: events)
    }

    /// Create only after every acknowledged event has been durably accepted.
    public static func acknowledgment(_ ids: [UUID]) -> Self {
        Self(kind: .acknowledgment,
             acknowledgedIDs: Array(Set(ids)).sorted { $0.uuidString < $1.uuidString })
    }

    public static func historyRequest(for events: [CompletionEvent]) throws -> Self {
        Self(kind: .historyRequest, inventory: try SyncInventory(events: events))
    }

    public func encoded() throws -> Data {
        try validate()
        let data = try SyncCodec.encoder().encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw SyncProtocolError.payloadTooLarge(data.count)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumEncodedBytes else {
            throw SyncProtocolError.payloadTooLarge(data.count)
        }
        return try SyncCodec.decoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case version, kind, events, acknowledgedIDs, inventory
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == Self.protocolVersion else {
            throw SyncProtocolError.unsupportedVersion(version)
        }
        kind = try values.decode(Kind.self, forKey: .kind)
        events = try values.decode([CompletionEvent].self, forKey: .events)
        acknowledgedIDs = try values.decode([UUID].self, forKey: .acknowledgedIDs)
        inventory = try values.decodeIfPresent(SyncInventory.self, forKey: .inventory)
        try validate()
    }

    private func validate() throws {
        guard version == Self.protocolVersion else {
            throw SyncProtocolError.unsupportedVersion(version)
        }
        switch kind {
        case .events:
            guard !events.isEmpty, events.count <= Self.maximumEvents,
                  acknowledgedIDs.isEmpty, inventory == nil,
                  CompletionLedger(events: events).events.count == events.count else {
                throw SyncProtocolError.invalidPacket
            }
        case .acknowledgment:
            guard events.isEmpty, !acknowledgedIDs.isEmpty,
                  acknowledgedIDs.count <= Self.maximumEvents,
                  Set(acknowledgedIDs).count == acknowledgedIDs.count,
                  inventory == nil else { throw SyncProtocolError.invalidPacket }
        case .historyRequest:
            guard events.isEmpty, acknowledgedIDs.isEmpty, inventory?.isValid == true else {
                throw SyncProtocolError.invalidPacket
            }
        }
    }
}

public enum SyncBatcher {
    /// Deterministic batches with both an event-count and actual encoded-byte bound.
    /// An oversized single event fails the entire operation; nothing is silently dropped.
    public static func batches(events: [CompletionEvent]) throws -> [SyncPacket] {
        let sorted = try events.map { ($0, try SyncCodec.encoder().encode($0)) }
            .sorted { $0.1.lexicographicallyPrecedes($1.1) }.map(\.0)
        var result: [SyncPacket] = []
        var current: [CompletionEvent] = []
        for event in sorted {
            let single = SyncPacket.events([event])
            do { _ = try single.encoded() }
            catch SyncProtocolError.payloadTooLarge {
                throw SyncProtocolError.singleEventTooLarge(event.eventID)
            }
            let candidate = current + [event]
            if candidate.count > SyncPacket.maximumEvents {
                result.append(.events(current))
                current = [event]
                continue
            }
            do {
                _ = try SyncPacket.events(candidate).encoded()
                current = candidate
            } catch SyncProtocolError.payloadTooLarge {
                result.append(.events(current))
                current = [event]
            }
        }
        if !current.isEmpty { result.append(.events(current)) }
        return result
    }
}

private enum SyncCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Explicit wire format, independent of app-document serialization.
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
