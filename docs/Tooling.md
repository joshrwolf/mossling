# Build and delivery foundation

## Baseline

- Swift 6 language mode with complete concurrency checking; domain package requires Swift tools 6.0 and is tested using Swift 6.2.
- Xcode 26.2 is the CI baseline, a verified installed version on GitHub's `macos-15` runner image. Newer stable Xcode can be used locally; SDK/runtime changes should be tested before changing the CI pin.
- Minimum deployment targets: iOS 18 and watchOS 11. The SDK used to build is newer than the minimum supported device OS.
- XcodeGen 2.46.0 defines two modern application targets in `project.yml`. The watch is a single watchOS application target, not the obsolete app-plus-extension structure.
- Shared source files and the local `MosslingCore` package compile into both apps. The iPhone app embeds the watch product in its `Watch` directory. Watch and phone bundle identifiers share a configurable prefix.
- No CocoaPods, Carthage, hosted backend, analytics SDK, or signing credentials in source control.

## Local Mac setup

1. Install stable Xcode 26.2 or newer from Apple, open it once, accept its license, and install iOS/watchOS simulator runtimes.
2. Select that Xcode in Settings → Locations → Command Line Tools.
3. Run `./scripts/bootstrap.sh`. This downloads the exact XcodeGen release into `.tools`, verifies its published SHA-256, and leaves global tools untouched.
4. Run `./scripts/generate.sh` and open `Mossling.xcodeproj`.
5. Choose the **Mossling** scheme and an iPhone simulator, then Run. Choose **MosslingWatch** and a watch simulator for the companion. Pair phone/watch simulators in Xcode's Devices and Simulators window for connectivity verification.
6. For personal hardware, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your own reverse-DNS bundle prefix and Apple development team. That local file is ignored by Git. Configure the same prefix/team in future cloud builds when signing is enabled.

`project.yml` is authoritative. Regenerate after adding source files or changing project settings. Commit the generated `.xcodeproj` and generated Info.plists so Xcode and Xcode Cloud can discover the project immediately. Do not hand-edit generated project settings.

## Verification

```sh
./scripts/verify-core.sh
./scripts/verify-apple.sh
```

The first command runs executable domain tests on Linux or macOS. The second generates the project, compiles both applications against their simulator SDKs without signing, and reruns the domain tests on Apple's Foundation implementation. Build artifacts are ignored. Running domain tests on Linux does **not** establish that SwiftUI, UserNotifications, WatchConnectivity, artwork, or device behavior work; the Apple build and manual device pass remain separate gates.

GitHub Actions runs these checks on pull requests and pushes to `main`. Permissions are read-only, repeated branch runs cancel obsolete runs, the checkout action is pinned to a verified commit, and no deployment or credential storage is configured. The Swift Docker image has an explicit version tag; a future release-hardening task can additionally pin the image digest. The macOS job checks that regeneration does not drift from the committed project.

## Xcode Cloud and TestFlight, later

A `ci_scripts/ci_post_clone.sh` hook installs the pinned generator and regenerates the project. After the repository is hosted, configure an Xcode Cloud workflow for the **Mossling** scheme and choose Xcode 26.2 or a validated newer stable version. Start with build/test actions only. The scheme includes the local package tests for Xcode Cloud testing.

Do not enable archive distribution until the Apple team, unique bundle IDs, App Store Connect record, and physical-device acceptance pass are ready. Then add an archive action and internal TestFlight group; no public App Store release is needed. Internal TestFlight eligibility, 90-day expiration, and role requirements still apply. This project contains no automatic upload or publishing step.

## Privacy manifest

The checked-in manifest declares no tracking or collected data. The onboarding preference uses SwiftUI AppStorage (UserDefaults), declared with NSPrivacyAccessedAPICategoryUserDefaults and reason CA92.1 for preferences within the app's own container. Forest persistence uses local Codable data and app-container file operations; no file timestamp, disk free-space, or device-uptime calls are intentionally used. Reevaluate the manifest whenever adding an SDK or platform API. A manifest is a declaration, not a substitute for a privacy review.

## Primary references checked

- [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md)
- [XcodeGen 2.46.0 release and artifact checksums](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)
- [GitHub macOS 15 runner toolchain inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [Swift installation on Linux](https://www.swift.org/install/linux/)
- [Apple: configuring your project for Xcode Cloud](https://developer.apple.com/documentation/xcode/configuring-your-project-for-xcode-cloud)
- [Apple: privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
