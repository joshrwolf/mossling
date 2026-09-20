# Release

Xcode Cloud owns signed archives and TestFlight distribution. Workflow settings live in App Store Connect; repository hooks prepare and validate builds. GitHub verification and `mise run archive:check` produce unsigned validation builds.

## Identity and signing

- App Store Connect: [Mosslinger](https://appstoreconnect.apple.com/apps/6814046299/testflight/ios), app ID `6814046299`.
- [Config/Product.json](../Config/Product.json) owns the registered phone bundle identifier and marketing version. Tuist derives the embedded Watch and UI-test identifiers. Preserve the registered identities.
- Xcode Cloud supplies build numbers and selects the signing team. Keep numbering above previously uploaded builds; do not commit build-number increments or credentials.
- Local device signing uses the ignored `Config/Local.xcconfig`. Generated `Config/Cloud.xcconfig` contains only the Cloud build number.

## Build and delivery

1. Select a reviewed revision with passing GitHub checks. Update marketing versions through product configuration and regenerate when needed.
2. Use the existing Cloud workflow for the root `Mossling.xcworkspace`, shared `Mossling` scheme and toolchain matching `Tuist.swift`. Manage triggers, archive preparation and distribution groups in App Store Connect.
3. Inspect the native Archive action and post-action validation for the phone and embedded Watch. The hooks in `ci_scripts` depend on their executable modes and symlinked resources; preserve both.
4. For TestFlight delivery, verify the workflow's archive preparation and distribution post-action, then confirm the processed build and intended tester group in App Store Connect. Archive success alone does not establish delivery.

The post-clone hook installs locked tools, runs domain tests and verifies project generation. The post-xcodebuild hook preserves native failures and validates successful archives against product identity, version and build number. Inspect failed Cloud action logs in Xcode's Report navigator or App Store Connect.

## Physical-device checks

Use a paired iPhone and Watch with the signed build:

- Allow, deny and revoke notifications; check locked-phone delivery, Focus/mirroring, snooze, skip, pause/resume and reminder replenishment after reopening or timezone changes.
- Lock/relaunch during a timed break and verify elapsed time, completion deadlines and saved progress.
- Complete offline on Watch, relaunch, reconnect and confirm exactly one reward. Check overlapping phone/Watch completions and phone configuration propagation.
- Upgrade an existing installation and exercise backup export/import without losing history, replacing configuration or duplicating rewards.
- Check layouts, accessibility, Reduce Motion and dim Watch presentation.

Record build/device details and results in the release issue or PR. Keep failed-build diagnostics there and fix with a higher build number; preserve existing user data and app identity.
