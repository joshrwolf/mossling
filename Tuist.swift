import ProjectDescription

// Generation is local and account-free. CI and local development use the same Xcode version.
let tuist = Tuist(
    xcodeCache: .xcodeCache(upload: false),
    network: .network(proxy: false),
    project: .tuist(
        compatibleXcodeVersions: .exact("27.0"),
        // This convenience scheme embeds machine-absolute paths and cannot be a portable snapshot.
        generationOptions: .options(includeGenerateScheme: false)
    )
)
