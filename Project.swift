import Foundation
import ProjectDescription

// The manifest is the source of truth. Generated files are tracked only because
// Xcode Cloud requires a continuously present project; CI rejects generation drift.
struct ProductConfiguration: Decodable {
    let bundleIdentifier: String
    let marketingVersion: String
}
let productConfiguration = try JSONDecoder().decode(
    ProductConfiguration.self,
    from: Data(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Config/Product.json"))
)
let phoneBundleID = productConfiguration.bundleIdentifier
let project = Project(
    name: "Mossling",
    options: .options(
        automaticSchemesOptions: .disabled,
        developmentRegion: "en",
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [.package(path: "Packages/MosslingCore")],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "MARKETING_VERSION": .string(productConfiguration.marketingVersion),
            "MOSSLING_PHONE_BUNDLE_IDENTIFIER": .string(phoneBundleID),
        ],
        configurations: [
            .debug(name: "Debug", xcconfig: "Config/Base.xcconfig"),
            .release(name: "Release", xcconfig: "Config/Base.xcconfig"),
        ]
    ),
    targets: [
        .target(
            name: "Mossling",
            destinations: [.iPhone],
            product: .app,
            bundleId: phoneBundleID,
            deploymentTargets: .iOS("18.0"),
            infoPlist: .file(path: "Config/iOS-Info.plist"),
            sources: ["Apps/iOS/**/*.swift", "Apps/Shared/**/*.swift"],
            resources: ["Apps/Shared/Assets.xcassets", "Config/PrivacyInfo.xcprivacy"],
            dependencies: [
                .package(product: "MosslingCore"),
                // Tuist embeds an .app watchOS dependency under the phone app's Watch/ directory.
                .target(name: "MosslingWatch"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "SUPPORTS_MACCATALYST": "NO",
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            ])
        ),
        .target(
            name: "MosslingWatch",
            destinations: [.appleWatch],
            product: .app,
            bundleId: phoneBundleID + ".watchkitapp",
            deploymentTargets: .watchOS("11.0"),
            infoPlist: .file(path: "Config/watchOS-Info.plist"),
            sources: ["Apps/Watch/**/*.swift", "Apps/Shared/**/*.swift"],
            resources: ["Apps/Shared/Assets.xcassets", "Config/PrivacyInfo.xcprivacy"],
            dependencies: [.package(product: "MosslingCore")],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "SKIP_INSTALL": "YES",
            ])
        ),
        .target(
            name: "MosslingUITests",
            destinations: [.iPhone],
            product: .uiTests,
            bundleId: phoneBundleID + ".uitests",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .default,
            sources: ["Apps/UITests/**/*.swift"],
            dependencies: [.target(name: "Mossling")],
            settings: .settings(base: ["TEST_TARGET_NAME": "Mossling"])
        ),
    ],
    schemes: [
        .scheme(
            name: "Mossling",
            shared: true,
            buildAction: .buildAction(targets: ["Mossling"]),
            // The first plan is Xcode's default: local and Cloud runs keep the
            // entire suite. CI selects complementary plans on separate runners.
            testAction: .testPlans(
                [.path("Config/Tests/All.xctestplan"),
                 .path("Config/Tests/Focused.xctestplan"),
                 .path("Config/Tests/Remainder.xctestplan")],
                configuration: .debug
            ),
            runAction: .runAction(configuration: .debug, executable: .executable("Mossling")),
            archiveAction: .archiveAction(configuration: .release)
        ),
        .scheme(
            name: "MosslingWatch",
            shared: true,
            buildAction: .buildAction(targets: ["MosslingWatch"]),
            runAction: .runAction(configuration: .debug, executable: .executable("MosslingWatch")),
            archiveAction: .archiveAction(configuration: .release)
        ),
    ],
    additionalFiles: ["Config/Base.xcconfig", "Config/Local.xcconfig.example", "Config/Product.json", "README.md", "docs/**"],
    resourceSynthesizers: []
)
