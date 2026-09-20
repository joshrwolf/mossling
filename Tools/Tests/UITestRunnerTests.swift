import Foundation

func testUITestRunner() throws {
    var assertions = 0
    func check(_ value: Bool, _ message: String) throws {
        guard value else { throw UITestError(message) }
        assertions += 1
    }
    func rejects(_ message: String, _ action: () throws -> Void) throws {
        do { try action() } catch { assertions += 1; return }
        throw UITestError(message)
    }
    let plan = try commandPlan([])
    try check(plan == [.build, .prepare, .test], "Compile must finish before simulator preparation")
    try check(try commandPlan(["all"]) == plan, "Explicit all must match default")
    try check(try commandPlan(["cleanup"]) == [.cleanup], "Cleanup must run independently")
    try rejects("Unknown command accepted") { _ = try commandPlan(["erase"]) }
    try rejects("Extra command accepted") { _ = try commandPlan(["test", "cleanup"]) }
    var phases: [UIPhase] = []
    let success = try executePlan(plan) { phases.append($0); return 0 }
    try check(success == 0 && phases == [.build, .prepare, .test, .cleanup], "Default ordering or cleanup changed")
    phases = []
    let failedBuild = try executePlan(plan) { phases.append($0); return 65 }
    try check(failedBuild == 65 && phases == [.build], "A failed build must not boot a device")
    phases = []
    let failedTest = try executePlan(plan) { phase in
        phases.append(phase)
        return phase == .test ? 65 : (phase == .cleanup ? 99 : 0)
    }
    try check(failedTest == 65 && phases.last == .cleanup, "Cleanup must preserve test failure")
    let failedCleanup = try executePlan(plan) { $0 == .cleanup ? 99 : 0 }
    try check(failedCleanup == 99, "Successful tests must not hide a cleanup failure")
    phases = []
    try rejects("Prepare exception lost") {
        _ = try executePlan(plan) { phase in
            phases.append(phase)
            if phase == .prepare { throw UITestError("boot failed") }
            return 0
        }
    }
    try check(phases == [.build, .prepare, .cleanup], "Failed preparation must still clean up")

    let state = OwnedSimulator(name: "Mossling-UI-Tests-11111111-1111-1111-1111-111111111111",
                               identifier: "22222222-2222-2222-2222-222222222222")
    let device = SimulatorInventory.Device(name: state.name, udid: state.identifier,
                                          isAvailable: true, deviceTypeIdentifier: nil)
    try state.validate()
    try check(try state.exists(in: .init(devices: ["runtime": [device]])), "Valid owned device rejected")
    try check(try !state.exists(in: .init(devices: [:])), "Absent device should allow stale state cleanup")
    let renamed = SimulatorInventory.Device(name: "My personal iPhone", udid: state.identifier,
                                           isAvailable: true, deviceTypeIdentifier: nil)
    try rejects("Renamed external device accepted") { _ = try state.exists(in: .init(devices: ["runtime": [renamed]])) }
    for name in ["iPhone 17", "Mossling-UI-Tests-", "Mossling-UI-Tests-invalid", state.name + "-other"] {
        try rejects("Malformed ownership name accepted") { try OwnedSimulator(name: name, identifier: state.identifier).validate() }
    }
    try rejects("Invalid identifier accepted") { try OwnedSimulator(name: state.name, identifier: "all").validate() }
    let roundTrip = try JSONDecoder().decode(OwnedSimulator.self, from: JSONEncoder().encode(state))
    try check(roundTrip.name == state.name && roundTrip.identifier == state.identifier, "Persisted ownership changed")
    try check(try selectedTestPlan([:]) == .all, "Local testing must include the full plan")
    try rejects("Unknown test plan accepted") { _ = try selectedTestPlan(["MOSSLING_UI_TEST_PLAN": "missing"]) }
    for plan in UITestPlan.allCases {
        try check(try selectedTestPlan(["MOSSLING_UI_TEST_PLAN": plan.rawValue]) == plan, "Valid plan rejected")
        let build = buildArguments(plan: plan)
        let test = try testArguments(for: state, diagnostics: false, plan: plan)
        try check(build.contains(plan.rawValue) && test.contains(plan.rawValue), "Build and execution plans must match")
    }
    let build = buildArguments()
    let test = try testArguments(for: state, diagnostics: false)
    try check(build[1] == "build-for-testing" && test[1] == "test-without-building", "Test phase must never recompile")
    try check(build.contains(derivedDataPath) && test.contains(derivedDataPath), "Build and test products diverged")
    try check(test.contains("NO") && test.contains("never"), "Serial baseline or diagnostic policy changed")
    try check(try testArguments(for: state, diagnostics: true).contains("on-failure"), "Diagnostic opt-in lost")
    try rejects("Invalid identifier reached xcodebuild") {
        _ = try testArguments(for: .init(name: state.name, identifier: "all"), diagnostics: false)
    }
    print("UI runner: \(assertions) ordering, ownership and argument checks passed")
}

try testUITestRunner()
