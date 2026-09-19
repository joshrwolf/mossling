import Foundation

/// A single atomic unit: an earned event and its delivery obligation cannot diverge.
public struct AppDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var deviceID: UUID
    public var configuration: AppConfiguration
    public var events: [CompletionEvent]
    public var session: SnackSession?
    public var pendingEventIDs: [UUID]
    public var hasReceivedPhoneConfiguration: Bool
    public var configurationAuthorityID: UUID?
    public var retiredConfigurationAuthorities: [UUID]

    public init(
        deviceID: UUID = UUID(), configuration: AppConfiguration = .standard,
        events: [CompletionEvent] = [], session: SnackSession? = nil,
        pendingEventIDs: [UUID] = [], hasReceivedPhoneConfiguration: Bool = false
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.deviceID = deviceID
        self.configuration = configuration
        self.events = events
        self.session = session
        self.pendingEventIDs = pendingEventIDs
        self.hasReceivedPhoneConfiguration = hasReceivedPhoneConfiguration
        configurationAuthorityID = nil
        retiredConfigurationAuthorities = []
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DocumentError.unsupportedVersion(schemaVersion)
        }
        try configuration.validate()
        let eventIDs = Set(events.map(\.eventID))
        guard eventIDs.count == events.count,
              Set(pendingEventIDs).isSubset(of: eventIDs),
              Set(pendingEventIDs).count == pendingEventIDs.count,
              CompletionLedger(events: events).events.count == events.count else {
            throw DocumentError.invalidDocument
        }
        if let session {
            try session.activity.validate()
            guard session.accumulatedSeconds.isFinite, session.accumulatedSeconds >= 0,
                  session.opportunity.scheduledAt < session.opportunity.expiresAt,
                  session.runningSince.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
                  session.startedAt.map({ session.opportunity.isActive(at: $0) }) ?? true,
                  !session.completed else { throw DocumentError.invalidDocument }
        }
    }

    /// Codable dates use milliseconds since 1970 consistently on both devices.
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> AppDocument {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let header = try decoder.decode(Header.self, from: data)
        guard (1...currentSchemaVersion).contains(header.schemaVersion) else {
            throw DocumentError.unsupportedVersion(header.schemaVersion)
        }
        var document = try decoder.decode(AppDocument.self, from: data)
        // Schema 1 did not record explicit session starts or temporary routine changes.
        // Optional fields decode absent; never infer a start from a timer's resume date.
        if document.schemaVersion == 1 {
            document.schemaVersion = 2
            // A watch upgraded from v1 must accept an equal-revision v2 snapshot:
            // its old decoder could have discarded unknown temporary routine fields.
            document.hasReceivedPhoneConfiguration = false
        }
        try document.validate()
        return document
    }
}

public enum DocumentError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidDocument

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This forest uses save version \(version). Update the app before opening it. Your save has been preserved."
        case .invalidDocument:
            return "The saved forest could not be validated. Your file has been preserved; it has not been reset."
        }
    }
}
