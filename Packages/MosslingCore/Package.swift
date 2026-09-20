// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosslingCore",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "MosslingCore", targets: ["MosslingCore"]),
        .library(name: "MosslingApplication", targets: ["MosslingApplication"]),
    ],
    targets: [
        .target(name: "MosslingCore"),
        .testTarget(name: "MosslingCoreTests", dependencies: ["MosslingCore"]),
        .target(name: "MosslingApplication", dependencies: ["MosslingCore"]),
        .testTarget(name: "MosslingApplicationTests", dependencies: ["MosslingApplication"])
    ]
)
