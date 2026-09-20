import Foundation

public struct ConfigurationSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let configuration: AppConfiguration
    public let authorityID: UUID
    public init(configuration: AppConfiguration, authorityID: UUID) {
        version = 2; self.configuration = configuration; self.authorityID = authorityID
    }
    public func encoded() throws -> Data {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= SyncPacket.maximumEncodedBytes else { throw SyncProtocolError.payloadTooLarge(data.count) }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= SyncPacket.maximumEncodedBytes else { throw SyncProtocolError.payloadTooLarge(data.count) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 2 else { throw SyncProtocolError.unsupportedVersion(value.version) }
        try value.configuration.validate()
        return value
    }
}

public enum DocumentSync {
    public static func mergeBackup(_ backup: AppDocument, into document: inout AppDocument) throws {
        try backup.validate()
        let known = Set(document.events.map(\.eventID))
        var ledger = CompletionLedger(events: document.events)
        ledger.merge(backup.events)
        document.events = ledger.events
        let pending = Set(document.pendingEventIDs)
        document.pendingEventIDs += ledger.events.map(\.eventID).filter { !known.contains($0) && !pending.contains($0) }
        if let session = document.session, ledger.containsReward(key: session.opportunity.rewardKey) {
            document.session = nil
        }
    }

    /// Called inside DocumentController.transact. Caller ACKs only after transact returns.
    public static func receive(_ packet: SyncPacket, into document: inout AppDocument) throws {
        _ = try packet.encoded() // Validate locally-created packets too.
        switch packet.kind {
        case .events:
            var ledger = CompletionLedger(events: document.events)
            ledger.merge(packet.events)
            document.events = ledger.events
            if let session = document.session, ledger.containsReward(key: session.opportunity.rewardKey) {
                document.session = nil
            }
        case .acknowledgment:
            let acknowledged = Set(packet.acknowledgedIDs)
            document.pendingEventIDs.removeAll { acknowledged.contains($0) }
        case .historyRequest:
            break // Inventory is a request, not a durable mutation.
        }
    }

    /// The platform boundary ensures this is only called on the watch.
    public static func receive(_ snapshot: ConfigurationSnapshot, into document: inout AppDocument) throws {
        _ = try snapshot.encoded()
        guard !document.retiredConfigurationAuthorities.contains(snapshot.authorityID) else { return }
        if document.configurationAuthorityID == snapshot.authorityID && document.hasReceivedPhoneConfiguration {
            // The phone is the sole configuration writer and increments revision for
            // every content change, including content-changing migrations. Replaying
            // its equal-revision full snapshot repairs fields an older Watch decoder
            // discarded from its cache without accepting an older configuration.
            guard snapshot.configuration.revision >= document.configuration.revision else { return }
        } else if let previous = document.configurationAuthorityID, previous != snapshot.authorityID {
            document.retiredConfigurationAuthorities.append(previous)
        }
        document.configuration = snapshot.configuration
        document.configurationAuthorityID = snapshot.authorityID
        document.hasReceivedPhoneConfiguration = true
    }

    public static func complete(_ session: SnackSession, at date: Date, in document: inout AppDocument) throws {
        try CompletionValidator.validate(session: session, completedAt: date)
        var ledger = CompletionLedger(events: document.events)
        guard !ledger.containsReward(key: session.opportunity.rewardKey) else { throw CompletionError.alreadyCompleted }
        let event = CompletionEvent(sessionID: session.id, opportunityID: session.opportunity.id,
            rewardKey: session.opportunity.rewardKey, scheduledAt: session.opportunity.scheduledAt,
            completedAt: date, activity: session.activity, sourceDeviceID: document.deviceID)
        ledger.merge([event])
        guard ledger.events.contains(where: { $0.eventID == event.eventID }) else { throw DocumentError.invalidDocument }
        document.events = ledger.events
        document.pendingEventIDs.append(event.eventID)
        document.session = nil
    }
}
