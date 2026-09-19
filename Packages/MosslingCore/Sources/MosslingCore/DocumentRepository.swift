import Foundation

public protocol DocumentRepository {
    func load() throws -> AppDocument?
    func save(_ document: AppDocument) throws
}

/// File I/O is intentionally small and synchronous: the main-actor controller
/// serializes writes, without an await at which another mutation can interleave.
public struct FileDocumentRepository: DocumentRepository {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> AppDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try AppDocument.decode(Data(contentsOf: url))
    }

    public func save(_ document: AppDocument) throws {
        let data = try document.encoded()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Atomic replacement preserves the previous valid file on a failed write.
        #if os(iOS) || os(watchOS)
        // Permit background watch synchronization after the first device unlock.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

/// Persist first, then publish. A failing writer leaves the UI's state unchanged.
@MainActor
public final class DocumentController {
    public private(set) var document: AppDocument
    private let repository: any DocumentRepository

    public init(repository: any DocumentRepository, initial: AppDocument = AppDocument()) throws {
        self.repository = repository
        if let existing = try repository.load() {
            try existing.validate()
            document = existing
        } else {
            try repository.save(initial)
            document = initial
        }
    }

    public func transact(_ mutation: (inout AppDocument) throws -> Void) throws {
        var candidate = document
        try mutation(&candidate)
        try candidate.validate()
        try repository.save(candidate)
        document = candidate
    }
}
