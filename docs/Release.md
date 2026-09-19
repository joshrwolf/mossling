# Release readiness

Development and verification do not need an Apple account. CI can generate the project, run tests, build simulator apps and create an **unsigned Release archive** while Apple Developer Program enrollment is pending.

The archive check runs `swift Tools/CheckArchive.swift <path.xcarchive>`. It verifies that the archive contains the iPhone app and its embedded Watch app, with resolved identifiers, matching marketing and build versions, the correct companion relationship, device platforms, executables, compiled assets and privacy manifests. This catches packaging problems that separate simulator builds cannot catch. It does not prove that signing, App Store Connect upload or installation on paired devices works.

Tuist defines the native project and dependency graph. The repository's mise tasks provide the shared local and CI entry points; Xcode performs Apple-platform compilation and archiving. Tuist's [archive command](https://tuist.dev/en/docs/cli/xcodebuild/archive) wraps Xcode, while [Tuist previews](https://tuist.dev/en/docs/cli/share) are a different distribution channel from TestFlight.

No TestFlight or App Store release pipeline is activated. Enrollment confirmation alone will not upload anything. After confirmation, choose one delivery boundary:

- **Xcode Cloud:** Apple manages the signing and TestFlight delivery workflow after its account and repository connection are configured.
- **GitHub-hosted delivery:** retain the existing macOS runner and add a focused release workflow, with fastlane as an option for signing and App Store Connect upload orchestration.

Both choices use the same native app targets and archive. We do not need to introduce Ruby, upload credentials or a second project definition to validate the application now. The delivery decision should settle credential ownership and build numbering before implementing signed uploads.

The first delivery setup will require the approved developer team, registered phone and Watch identifiers, an App Store Connect app record and signing configuration. The first upload remains a separate, deliberate action after archive checks. A successful upload still needs a paired-device acceptance pass; archive validation does not replace it. Internal TestFlight distribution is the intended initial destination; public App Store submission is outside the current scope.
