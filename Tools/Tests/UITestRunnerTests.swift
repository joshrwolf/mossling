import Foundation

func testSimulatorOwnership() throws {
    let parentName = "Mossling-UI-Tests-11111111-1111-1111-1111-111111111111"
    let parentID = "22222222-2222-2222-2222-222222222222"
    let cloneID = "33333333-3333-3333-3333-333333333333"
    let otherID = "44444444-4444-4444-4444-444444444444"
    func device(_ name: String, _ id: String, available: Bool = true) -> SimulatorInventory.Device {
        .init(name: name, udid: id, isAvailable: available, deviceTypeIdentifier: nil)
    }
    func check(_ devices: [SimulatorInventory.Device], expected: [String], _ reason: String) throws {
        let inventory = SimulatorInventory(devices: ["runtime": devices])
        guard ownedSimulatorIDs(in: inventory, parentName: parentName, parentID: parentID) == expected else {
            throw UITestError("Simulator cleanup ownership failed: \(reason)")
        }
    }
    try check([], expected: [parentID], "parent survives inventory failure or absence")
    try check([device(parentName, parentID), device("Clone 1 of \(parentName)", cloneID)],
              expected: [cloneID, parentID], "own worker before parent")
    try check([device("Clone 2 of \(parentName)", cloneID, available: false)],
              expected: [cloneID, parentID], "unavailable owned worker still cleaned")
    try check([device("Clone 1 of \(parentName)", cloneID), device("Clone 2 of \(parentName)", cloneID)],
              expected: [cloneID, parentID], "duplicate inventory IDs cleaned once")
    for name in [
        "iPhone 17", parentName, "Clone 1 of another-run", "Clone 1 of \(parentName)-other",
        "Prefix Clone 1 of \(parentName)", "Clone 1 of prefix-\(parentName)",
        "Clone 0 of \(parentName)", "Clone -1 of \(parentName)", "Clone x of \(parentName)",
        "Clone  of \(parentName)", "Clone 1 extra of \(parentName)", "Clone ١ of \(parentName)",
        "Clone 999999999999999999999999999999 of \(parentName)",
    ] {
        try check([device(name, otherID)], expected: [parentID], "must retain unrelated or malformed name: \(name)")
    }
    try check([device("Clone 1 of \(parentName)", "not-a-device-id")], expected: [parentID],
              "invalid clone UUID rejected")
    print("Simulator cleanup ownership: 18 cases passed")
}

try testSimulatorOwnership()
