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

let statePath = ".build-artifacts/UI-Simulator.json"
let derivedDataPath = ".build-artifacts/SimulatorDerivedData"
let resultPath = ".build-artifacts/UI-Tests.xcresult"
let screenshotsPath = ".build-artifacts/screenshots"

struct OwnedSimulator: Codable {
    let name: String
    let identifier: String

    func validate() throws {
        let prefix = "Mossling-UI-Tests-"
        guard UUID(uuidString: identifier) != nil, name.hasPrefix(prefix),
              let token = UUID(uuidString: String(name.dropFirst(prefix.count))),
              name == prefix + token.uuidString else {
            throw UITestError("Invalid owned simulator state; refusing to use or delete a device")
        }
    }

    func exists(in inventory: SimulatorInventory) throws -> Bool {
        try validate()
        guard let device = inventory.devices.values.flatMap({ $0 }).first(where: { $0.udid == identifier }) else {
            return false
        }
        guard device.name == name else {
            throw UITestError("Simulator identity no longer matches owned state; refusing to use or delete it")
        }
        return true
    }
}

enum UIPhase: String { case build, prepare, test, cleanup }

func commandPlan(_ arguments: [String]) throws -> [UIPhase] {
    if arguments.isEmpty || arguments == ["all"] { return [.build, .prepare, .test] }
    guard arguments.count == 1, let phase = UIPhase(rawValue: arguments[0]) else {
        throw UITestError("Usage: swift Tools/RunUITests.swift [all|build|prepare|test|cleanup]")
    }
    return [phase]
}

// A failed build never boots a simulator. A failed prepare/test still cleans up;
// cleanup diagnostics must not replace the original test or setup exit status.
func executePlan(_ plan: [UIPhase], execute: (UIPhase) throws -> Int32) throws -> Int32 {
    var needsCleanup = false
    var status: Int32 = 0
    var phaseError: (any Error)?
    do {
        for phase in plan {
            if plan.count > 1 && phase == .prepare { needsCleanup = true }
            status = try execute(phase)
            if status != 0 { break }
        }
    } catch { phaseError = error }
    if needsCleanup {
        do {
            let cleanupStatus = try execute(.cleanup)
            if status == 0 { status = cleanupStatus }
        } catch {
            diagnostic("Simulator cleanup failed: \(error)")
            if status == 0 { status = 1 }
        }
    }
    if let phaseError { throw phaseError }
    return status
}

func simulatorInventory() throws -> SimulatorInventory {
    let result = try run(["simctl", "list", "devices", "-j"], capture: true)
    guard result.status == 0 else { throw UITestError("simctl could not list devices") }
    return try JSONDecoder().decode(SimulatorInventory.self, from: result.output)
}

func loadOwnedSimulator() throws -> OwnedSimulator {
    let state = try JSONDecoder().decode(OwnedSimulator.self, from: Data(contentsOf: URL(fileURLWithPath: statePath)))
    try state.validate()
    return state
}

enum UITestPlan: String, CaseIterable { case all = "All", focused = "Focused", remainder = "Remainder" }

func selectedTestPlan(_ environment: [String: String]) throws -> UITestPlan {
    guard let plan = UITestPlan(rawValue: environment["MOSSLING_UI_TEST_PLAN"] ?? "All") else {
        throw UITestError("MOSSLING_UI_TEST_PLAN must be All, Focused or Remainder")
    }
    return plan
}

func buildArguments(plan: UITestPlan = .all) -> [String] {
    ["xcodebuild", "build-for-testing", "-project", "Mossling.xcodeproj", "-scheme", "Mossling",
     "-destination", "generic/platform=iOS Simulator", "-testPlan", plan.rawValue,
     "-derivedDataPath", derivedDataPath, "-showBuildTimingSummary", "CODE_SIGNING_ALLOWED=NO"]
}

func testArguments(for state: OwnedSimulator, diagnostics: Bool, plan: UITestPlan = .all) throws -> [String] {
    try state.validate()
    return ["xcodebuild", "test-without-building", "-project", "Mossling.xcodeproj", "-scheme", "Mossling",
            "-destination", "platform=iOS Simulator,id=\(state.identifier)",
            "-testPlan", plan.rawValue, "-parallel-testing-enabled", "NO",
            // Preserve XCTest attachments without the 600-second system diagnostic stall.
            "-collect-test-diagnostics", diagnostics ? "on-failure" : "never",
            "-resultBundlePath", resultPath, "-derivedDataPath", derivedDataPath,
            "-showBuildTimingSummary", "CODE_SIGNING_ALLOWED=NO"]
}

func runPhase(_ phase: UIPhase) throws -> Int32 {
    switch phase {
    case .build:
        guard FileManager.default.fileExists(atPath: "Mossling.xcodeproj/project.pbxproj") else {
            throw UITestError("Run from the repository root after generating Mossling.xcodeproj")
        }
        return try run(buildArguments(plan: selectedTestPlan(ProcessInfo.processInfo.environment))).status
    case .prepare:
        guard !FileManager.default.fileExists(atPath: statePath) else {
            throw UITestError("Owned simulator state already exists; run cleanup before preparing another device")
        }
        let template = try simulatorTemplate(from: simulatorInventory())
        let name = "Mossling-UI-Tests-\(UUID().uuidString)"
        let created = try run(["simctl", "create", name, template.type, template.runtime], capture: true)
        let identifier = String(decoding: created.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard created.status == 0, UUID(uuidString: identifier) != nil else {
            throw UITestError("simctl could not create a disposable test device")
        }
        let state = OwnedSimulator(name: name, identifier: identifier)
        do {
            // Persist before boot: a timed-out CI prepare step can still clean up.
            try FileManager.default.createDirectory(atPath: ".build-artifacts", withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: URL(fileURLWithPath: statePath), options: .atomic)
        } catch {
            // No state was saved; this invocation still knows the created UUID.
            _ = try? run(["simctl", "delete", identifier])
            throw error
        }
        let boot = try run(["simctl", "boot", identifier])
        guard boot.status == 0 else { return boot.status }
        return try run(["simctl", "bootstatus", identifier, "-b"]).status
    case .test:
        let state = try loadOwnedSimulator()
        guard try state.exists(in: simulatorInventory()) else { throw UITestError("Owned simulator no longer exists") }
        for path in [resultPath, screenshotsPath] where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        let result = try run(testArguments(for: state,
            diagnostics: ProcessInfo.processInfo.environment["MOSSLING_UI_DIAGNOSTICS"] == "1",
            plan: selectedTestPlan(ProcessInfo.processInfo.environment)))
        if FileManager.default.fileExists(atPath: resultPath) {
            do {
                let exported = try run(["xcresulttool", "export", "attachments", "--path", resultPath,
                                        "--output-path", screenshotsPath])
                if exported.status != 0 { diagnostic("Attachment export failed; xcresult remains available") }
            } catch { diagnostic("Attachment export failed: \(error)") }
        }
        return result.status
    case .cleanup:
        guard FileManager.default.fileExists(atPath: statePath) else { return 0 }
        let state = try loadOwnedSimulator()
        if try state.exists(in: simulatorInventory()) {
            diagnostic("Cleaning up owned simulator \(state.identifier)")
            _ = try? run(["simctl", "shutdown", state.identifier], capture: true)
            let deleted = try run(["simctl", "delete", state.identifier])
            guard deleted.status == 0 else { return deleted.status }
        }
        try FileManager.default.removeItem(atPath: statePath)
        return 0
    }
}

#if !UI_RUNNER_TESTS
let exitStatus: Int32
do {
    let plan = try commandPlan(Array(CommandLine.arguments.dropFirst()))
    // Do not let the default command clean up a previous invocation's device.
    if plan.count > 1 && FileManager.default.fileExists(atPath: statePath) {
        throw UITestError("Owned simulator state already exists; run cleanup before starting another suite")
    }
    exitStatus = try executePlan(plan, execute: runPhase)
} catch {
    diagnostic("UI test setup failed: \(error)")
    exitStatus = 1
}
exit(exitStatus)
#endif
