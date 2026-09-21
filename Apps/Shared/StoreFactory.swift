import Foundation
import MosslingCore
import MosslingApplication

@MainActor
extension MosslingStore {
    static func live(role: DeviceRole) -> MosslingStore {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            var documentURL = folder.appendingPathComponent("Mossling/forest-v1.json")
            #if DEBUG && targetEnvironment(simulator)
            // UI automation exercises real disk persistence in a separate namespace.
            // The reset flag can never remove a person's normal forest.
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                documentURL = folder.appendingPathComponent("MosslingUITests/forest-v1.json")
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset"),
                   FileManager.default.fileExists(atPath: documentURL.path) {
                    try FileManager.default.removeItem(at: documentURL)
                }
            }
            #endif
            let repository = FileDocumentRepository(url: documentURL)
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--ui-testing-reset"),
               let fixture = ProcessInfo.processInfo.environment["MOSSLING_UI_TEST_DOCUMENT"] {
                guard let data = Data(base64Encoded: fixture) else { throw DocumentError.invalidDocument }
                try repository.save(AppDocument.decode(data))
            }
            #endif
            let controller = try DocumentController(repository: repository, initial: try freshDocument())
            var clock: () -> Date = Date.init
            #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing"),
               let index = arguments.firstIndex(of: "--ui-testing-now"), index + 1 < arguments.count,
               let seconds = Double(arguments[index + 1]), seconds.isFinite {
                let fixed = Date(timeIntervalSince1970: seconds)
                NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
                clock = { fixed }
            }
            #endif
            return MosslingStore(role: role, controller: controller, connection: WatchConnectivityService(),
                                 notifications: reminders(for: role), clock: clock)
        } catch {
            return MosslingStore(role: role, controller: nil,
                failure: "Your forest could not be opened. Existing data has been preserved. \(error.localizedDescription)")
        }
    }

    static func preview() -> MosslingStore {
        MosslingStore(role: .phone, controller: try? DocumentController(repository: PreviewRepository()))
    }

    private static func freshDocument() throws -> AppDocument {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return AppDocument() }
        #endif
        return AppDocument(configuration: AppConfiguration(world: try .generated(seed: UInt64.random(in: 0...UInt64.max))))
    }

    private static func reminders(for role: DeviceRole) -> (any ReminderService)? {
        #if os(iOS)
        role == .phone ? NotificationService() : nil
        #else
        nil
        #endif
    }
}

private final class PreviewRepository: DocumentRepository {
    var document: AppDocument?
    func load() throws -> AppDocument? { document }
    func save(_ document: AppDocument) throws { self.document = document }
}
