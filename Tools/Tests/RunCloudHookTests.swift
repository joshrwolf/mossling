import Foundation

// Compile the production adapter with its CLI entry point disabled, then test its actual functions.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mossling-cloud-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let binary = directory.appendingPathComponent("tests")
let source = directory.appendingPathComponent("main.swift")
let production = try String(contentsOf: root.appendingPathComponent("Tools/XcodeCloud.swift"), encoding: .utf8)
let tests = try String(contentsOf: root.appendingPathComponent("Tools/Tests/CloudHookTests.swift"), encoding: .utf8)
try (production + "\n" + tests).write(to: source, atomically: true, encoding: .utf8)
func execute(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 { exit(process.terminationStatus) }
}
try execute(["swiftc", "-swift-version", "6", "-warnings-as-errors", "-D", "CLOUD_HOOK_TESTS",
    source.path, "-o", binary.path])
try execute([binary.path])
