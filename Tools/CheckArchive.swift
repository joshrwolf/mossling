import Foundation

// Validate the products we intend to distribute without requiring signing credentials.
struct ArchiveError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ArchiveError(message) }
}

func readPlist(_ url: URL) throws -> [String: Any] {
    guard let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: url), format: nil
    ) as? [String: Any] else {
        throw ArchiveError("Expected a property-list dictionary at \(url.path)")
    }
    return plist
}

func concreteString(_ key: String, in plist: [String: Any], bundle: String) throws -> String {
    guard let value = plist[key] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !value.contains("$("), !value.contains("${") else {
        throw ArchiveError("\(bundle): \(key) must contain a resolved, nonempty value")
    }
    return value
}

func requireFile(_ url: URL) throws {
    var isDirectory: ObjCBool = false
    try require(
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue,
        "Missing required file: \(url.path)"
    )
}

func checkBundle(_ bundle: URL, platform: String) throws -> [String: Any] {
    let info = try readPlist(bundle.appendingPathComponent("Info.plist"))
    let identifier = try concreteString("CFBundleIdentifier", in: info, bundle: bundle.lastPathComponent)
    try require(
        identifier.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil,
        "\(bundle.lastPathComponent): invalid bundle identifier \(identifier)"
    )
    try require(info["CFBundlePackageType"] as? String == "APPL", "\(identifier): expected an application bundle")
    try require(
        (info["CFBundleSupportedPlatforms"] as? [String]) == [platform],
        "\(identifier): expected device platform \(platform), not a simulator product"
    )
    let executable = try concreteString("CFBundleExecutable", in: info, bundle: identifier)
    try require(
        executable != "." && executable != ".." && !executable.contains("/"),
        "\(identifier): executable must be a filename inside its bundle"
    )
    let executableURL = bundle.appendingPathComponent(executable)
    try requireFile(executableURL)
    try require(FileManager.default.isExecutableFile(atPath: executableURL.path), "\(identifier): executable is not executable")
    try requireFile(bundle.appendingPathComponent("Assets.car"))
    _ = try readPlist(bundle.appendingPathComponent("PrivacyInfo.xcprivacy"))
    _ = try concreteString("CFBundleShortVersionString", in: info, bundle: identifier)
    _ = try concreteString("CFBundleVersion", in: info, bundle: identifier)
    return info
}

func checkArchive(_ archive: URL) throws {
    let archiveInfo = try readPlist(archive.appendingPathComponent("Info.plist"))
    let properties = archiveInfo["ApplicationProperties"] as? [String: Any]
    try require(
        properties?["ApplicationPath"] as? String == "Applications/Mossling.app",
        "Archive must declare Applications/Mossling.app as its application product"
    )
    let applications = archive.appendingPathComponent("Products/Applications")
    let products = try FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "app" }
    try require(products.map(\.lastPathComponent) == ["Mossling.app"], "Archive must contain exactly one top-level application: Mossling.app")
    let phoneURL = applications.appendingPathComponent("Mossling.app")
    let watchDirectory = phoneURL.appendingPathComponent("Watch")
    let watchProducts = try FileManager.default.contentsOfDirectory(at: watchDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "app" }
    try require(watchProducts.map(\.lastPathComponent) == ["MosslingWatch.app"], "iPhone application must embed exactly one Watch application: MosslingWatch.app")
    let phone = try checkBundle(phoneURL, platform: "iPhoneOS")
    let watch = try checkBundle(watchDirectory.appendingPathComponent("MosslingWatch.app"), platform: "WatchOS")
    try require(
        watch["WKCompanionAppBundleIdentifier"] as? String == phone["CFBundleIdentifier"] as? String,
        "Watch companion identifier does not match the iPhone bundle identifier"
    )
    try require(
        watch["CFBundleIdentifier"] as? String != phone["CFBundleIdentifier"] as? String,
        "Phone and Watch must have distinct bundle identifiers"
    )
    let phoneIdentifier = try concreteString("CFBundleIdentifier", in: phone, bundle: "iPhone")
    let watchIdentifier = try concreteString("CFBundleIdentifier", in: watch, bundle: "Watch")
    try require(watchIdentifier.hasPrefix(phoneIdentifier + "."), "Watch bundle identifier must extend the iPhone identifier")
    for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
        try require(phone[key] as? String == watch[key] as? String, "Phone and Watch \(key) values differ")
    }
    print("Archive verified: iPhone and embedded Watch device apps, matching versions, assets and privacy manifests.")
}

do {
    try require(CommandLine.arguments.count == 2, "Usage: swift Tools/CheckArchive.swift <path.xcarchive>")
    try checkArchive(URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("Archive validation failed: \(error)\n".utf8))
    exit(1)
}
