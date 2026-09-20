import Foundation

func runCloudHookTests() throws {
        let product = Product(bundleIdentifier: "com.joshrwolf.mossling", marketingVersion: "0.1.0")
        let valid = ["CI": "TRUE", "CI_BUNDLE_ID": product.bundleIdentifier,
            "CI_TEAM_ID": "ABCDE12345", "CI_BUILD_NUMBER": "42"]
        var checked = 0
        func expectFailure(_ name: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { checked += 1; return }
            throw CloudError("Expected rejection: \(name)")
        }
        // Diagnostics identify the failing phase/tool without disclosing argv or environment.
        var messages: [String] = []
        do {
            try run("/bin/sh", ["-c", "exit 23", "argument-secret"],
                environment: ["TEST_SECRET": "environment-secret"], phase: "fixture subprocess",
                log: { messages.append($0) })
            throw CloudError("Failing subprocess incorrectly succeeded")
        } catch let failure as CommandFailure {
            try requireCloud(failure.status == 23, "Subprocess exit status was changed")
            try requireCloud(failure.description.contains("fixture subprocess") && failure.description.contains("sh"),
                "Subprocess failure lost its actionable context")
            checked += 1
        }
        let diagnostic = messages.joined(separator: "\n")
        try requireCloud(diagnostic.contains("status 23") && diagnostic.contains("Elapsed:"), "Missing failure timing/status")
        try requireCloud(!diagnostic.contains("argument-secret") && !diagnostic.contains("environment-secret"),
            "Diagnostics exposed command arguments or environment")
        messages.removeAll()
        let captured = try run("/bin/sh", ["-c", "printf fixture-output"], capture: true,
            phase: "fixture captured output", log: { messages.append($0) })
        try requireCloud(captured == "fixture-output", "Diagnostics corrupted captured subprocess output")
        try requireCloud(messages.last?.contains("Finished fixture captured output in") == true,
            "Successful subprocess omitted its duration")
        do {
            try run("/nonexistent/mossling-tool", [], phase: "fixture missing tool", log: { messages.append($0) })
            throw CloudError("Missing subprocess incorrectly succeeded")
        } catch let failure as CloudError {
            try requireCloud(failure.description == "fixture missing tool: could not launch mossling-tool.",
                "Launch failure lost its phase/tool context")
            checked += 1
        }
        do {
            try run("/bin/sh", ["-c", "kill -TERM $$"], phase: "fixture terminated tool", log: { messages.append($0) })
            throw CloudError("Terminated subprocess incorrectly succeeded")
        } catch let failure as CommandFailure {
            try requireCloud(failure.status == 143, "Terminated process did not preserve signal status")
            checked += 1
        }
        let config = try identity(valid, product: product).configuration
        try requireCloud(config.contains("CURRENT_PROJECT_VERSION = 42\n"), "Valid build must reach configuration")
        for key in valid.keys {
            var env = valid; env.removeValue(forKey: key)
            try expectFailure("missing \(key)") { _ = try identity(env, product: product) }
        }
        for (key, values) in [
            "CI_TEAM_ID": ["XXXXXXXXXX", "YOURTEAMID", "abcde12345", "ABCDE12345\nCODE_SIGNING_ALLOWED = NO", "$(TEAM)", "ABCDE12345\n"],
            "CI_BUILD_NUMBER": ["0", "-1", "1.2", "42\n#include \"evil\"", "$(BUILD)", "42\n"],
            "CI_BUNDLE_ID": ["com.example.mossling", "com.joshrwolf.other", "com.joshrwolf.mossling\n"],
        ] {
            for value in values {
                var env = valid; env[key] = value
                try expectFailure("invalid \(key)") { _ = try identity(env, product: product) }
            }
        }
        let scripts = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scripts) }
        try Data(#"{"bundleIdentifier":"com.joshrwolf.mossling","marketingVersion":"0.1.0"}"#.utf8)
            .write(to: scripts.appendingPathComponent("Product.json"))
        for action in ["analyze", "build", "build-for-testing", "test-without-building"] {
            try cloudMain(["test", "post-xcodebuild", scripts.path], environment: [
                "CI_XCODEBUILD_ACTION": action, "CI_XCODEBUILD_EXIT_CODE": "0"])
        }
        // Native failure must survive absent product metadata, archive, and signing identity.
        do {
            try cloudMain(["test", "post-xcodebuild", "/missing"], environment: [
                "CI_XCODEBUILD_ACTION": "archive", "CI_XCODEBUILD_EXIT_CODE": "65"])
            throw CloudError("Failed native action incorrectly succeeded")
        } catch let failure as CommandFailure {
            try requireCloud(failure.status == 65, "Original xcodebuild exit status was masked")
            checked += 1
        }
        var archiveEnv = valid
        archiveEnv["CI_XCODEBUILD_ACTION"] = "archive"
        archiveEnv["CI_XCODEBUILD_EXIT_CODE"] = "0"
        try expectFailure("successful archive without artifact") {
            try cloudMain(["test", "post-xcodebuild", scripts.path], environment: archiveEnv)
        }
        archiveEnv["CI_ARCHIVE_PATH"] = "/nonexistent/Mossling.xcarchive"
        try expectFailure("missing archive path") {
            try cloudMain(["test", "post-xcodebuild", scripts.path], environment: archiveEnv)
        }
        // Simulate Apple's copied ci_scripts phase with no source checkout available.
        let helpers = scripts.appendingPathComponent("helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let archive = scripts.appendingPathComponent("Mossling.xcarchive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        archiveEnv["CI_ARCHIVE_PATH"] = archive.path
        let validator = helpers.appendingPathComponent("CheckArchive.swift")
        try "import Foundation\nexit(23)\n".write(to: validator, atomically: true, encoding: .utf8)
        do {
            try cloudMain(["test", "post-xcodebuild", scripts.path], environment: archiveEnv)
            throw CloudError("Archive validator failure incorrectly succeeded")
        } catch let failure as CommandFailure {
            try requireCloud(failure.status == 23, "Archive validator failure was masked")
            checked += 1
        }
        try #"""
        import Foundation
        let expected = ["--expect-bundle-id", "com.joshrwolf.mossling", "--expect-build-number", "42", "--expect-version", "0.1.0"]
        guard Array(CommandLine.arguments.dropFirst(2)) == expected else { exit(24) }
        """#.write(to: validator, atomically: true, encoding: .utf8)
        try cloudMain(["test", "post-xcodebuild", scripts.path], environment: archiveEnv)
        for status in ["", "garbage", "-1", "256"] {
            try expectFailure("malformed exit status") {
                _ = try nativeAction(["CI_XCODEBUILD_ACTION": "archive", "CI_XCODEBUILD_EXIT_CODE": status])
            }
        }
        print("Cloud hooks: valid configuration, successful non-archive phases, and \(checked) failure cases passed.")
    }

try runCloudHookTests()
