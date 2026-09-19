import Foundation

// UI tests exercise real local adapters, so always give them a disposable device.
struct SimulatorInventory: Decodable {
    struct Device: Decodable {
        let name: String
        let udid: String
        let isAvailable: Bool
        let deviceTypeIdentifier: String?
    }
    let devices: [String: [Device]]
}

struct UITestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func simulatorTemplate(from inventory: SimulatorInventory) throws -> (runtime: String, type: String) {
    let prefix = "com.apple.CoreSimulator.SimRuntime.iOS-"
    let candidates = inventory.devices.flatMap { runtime, devices -> [(version: [Int], runtime: String, type: String)] in
        guard runtime.hasPrefix(prefix) else { return [] }
        let components = runtime.dropFirst(prefix.count).split(separator: "-")
        let version = components.compactMap { Int($0) }
        guard !version.isEmpty, version.count == components.count, version[0] >= 18 else { return [] }
        return devices.compactMap { device in
            guard device.isAvailable, device.name.hasPrefix("iPhone"),
                  let type = device.deviceTypeIdentifier else { return nil }
            return (version, runtime, type)
        }
    }.sorted { lhs, rhs in
        // Numeric comparison prevents iOS 9 sorting above iOS 26.
        for index in 0..<max(lhs.version.count, rhs.version.count) {
            let left = index < lhs.version.count ? lhs.version[index] : 0
            let right = index < rhs.version.count ? rhs.version[index] : 0
            if left != right { return left > right }
        }
        return lhs.type < rhs.type
    }
    guard let template = candidates.first else {
        throw UITestError("No available iPhone simulator for iOS 18 or newer. Install an iOS runtime and an iPhone simulator in Xcode.")
    }
    return (template.runtime, template.type)
}

func run(_ arguments: [String], capture: Bool = false) throws -> (status: Int32, output: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    process.standardError = FileHandle.standardError
    let pipe = capture ? Pipe() : nil
    process.standardOutput = pipe ?? FileHandle.standardOutput
    try process.run()
    let output = pipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    process.waitUntilExit()
    return (process.terminationStatus, output)
}

func diagnostic(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

func runUITests() throws -> Int32 {
    guard FileManager.default.fileExists(atPath: "Mossling.xcodeproj/project.pbxproj") else {
        throw UITestError("Run from the repository root after generating Mossling.xcodeproj.")
    }
    let inventory = try run(["simctl", "list", "devices", "available", "-j"], capture: true)
    guard inventory.status == 0 else { throw UITestError("simctl could not list available devices") }
    let template = try simulatorTemplate(from: JSONDecoder().decode(SimulatorInventory.self, from: inventory.output))
    let created = try run(["simctl", "create", "Mossling-UI-Tests-\(UUID().uuidString)", template.type, template.runtime], capture: true)
    let identifier = String(decoding: created.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard created.status == 0, UUID(uuidString: identifier) != nil else {
        throw UITestError("simctl could not create a disposable test device")
    }
    defer {
        // Shutdown can fail if Xcode never booted the device; deletion still runs.
        _ = try? run(["simctl", "shutdown", identifier], capture: true)
        do {
            let deletion = try run(["simctl", "delete", identifier], capture: true)
            if deletion.status != 0 { diagnostic("Could not delete temporary simulator \(identifier)") }
        } catch { diagnostic("Could not delete temporary simulator \(identifier): \(error)") }
    }

    let resultPath = ".build-artifacts/UI-Tests.xcresult"
    let screenshotsPath = ".build-artifacts/screenshots"
    try FileManager.default.createDirectory(atPath: ".build-artifacts", withIntermediateDirectories: true)
    // These two paths contain only outputs from this helper; discard stale results.
    for path in [resultPath, screenshotsPath] where FileManager.default.fileExists(atPath: path) {
        try FileManager.default.removeItem(atPath: path)
    }
    let test = try run([
        "xcodebuild", "test", "-project", "Mossling.xcodeproj", "-scheme", "Mossling",
        "-destination", "platform=iOS Simulator,id=\(identifier)",
        "-only-testing:MosslingUITests", "-parallel-testing-enabled", "NO",
        "-resultBundlePath", resultPath, "-derivedDataPath", ".build-artifacts/UITestsDerivedData",
        "CODE_SIGNING_ALLOWED=NO"
    ])
    if FileManager.default.fileExists(atPath: resultPath) {
        do {
            let export = try run([
                "xcresulttool", "export", "attachments", "--path", resultPath,
                "--output-path", screenshotsPath
            ])
            if export.status != 0 { diagnostic("Attachment export failed; the original xcresult bundle remains available.") }
        } catch { diagnostic("Attachment export failed: \(error)") }
    }
    return test.status
}

let exitStatus: Int32
do {
    exitStatus = try runUITests()
} catch {
    diagnostic("UI test setup failed: \(error)")
    exitStatus = 1
}
exit(exitStatus)
