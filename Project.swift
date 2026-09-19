import ProjectDescription

// The manifest is the source of truth. Generated Xcode files are disposable.
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
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "CODE_SIGN_STYLE": "Automatic",
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
            bundleId: "$(BUNDLE_ID_PREFIX).mossling",
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
            bundleId: "$(BUNDLE_ID_PREFIX).mossling.watchkitapp",
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
            bundleId: "$(BUNDLE_ID_PREFIX).mossling.uitests",
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
            testAction: .targets(
                ["MosslingUITests"],
                configuration: .debug,
                options: .options(coverage: true)
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
    additionalFiles: ["Config/*.xcconfig", "README.md", "docs/**"],
    resourceSynthesizers: []
)
