# Project and delivery tooling

## Ownership

| Concern | Canonical definition |
| --- | --- |
| Targets, resources, dependencies, shared schemes | `Project.swift` / Tuist 4.208.0 |
| Product identifier and marketing version | `Config/Product.json` |
| Signing defaults and optional overrides | `Config/Base.xcconfig` |
| Pinned tools and task dependencies | `mise.toml`, `mise.lock` |
| Compiler and platform SDK | Xcode 27.0 |
| Portable domain package | Swift Package Manager |
| Hosted verification during Cloud setup | GitHub Actions |
| Managed signing and delivery after account setup | Xcode Cloud |

Tuist is the project source of truth. Apple requires a continuously present project for Cloud discovery, so `Mossling.xcodeproj` and `Mossling.xcworkspace` are committed generated snapshots. Never edit them by hand: change the manifest/configuration, run `mise run generate`, review and commit the resulting snapshot. `project:check` regenerates and rejects tracked differences or new untracked project files. Both GitHub and Cloud retain this gate.

This deliberately replaces the earlier ignored-project policy. Apple's project-discovery requirement is more restrictive than a generic CI runner. Keeping a generated snapshot does not create a second manually maintained project definition.

Optional `Local.xcconfig` and generated `Cloud.xcconfig` are ignored and deliberately excluded from Tuist's additional-file list so they cannot change the project graph. The base configuration includes Local then Cloud; Cloud's team/build values win. Tuist defines concrete bundle identifiers and the marketing version, but does not define the build number or team at a higher settings precedence.

GitHub uses the dedicated `xcode-27` hosted image and its `/Applications/Xcode_27.0.app` alias. The image is currently marked preview by GitHub; CI must validate the actual installed toolchain. Xcode Cloud selects explicit 27.0. The iOS 18 and watchOS 11 deployment targets remain unchanged. Linux continues testing the portable package with Swift 6.2 to preserve its minimum compiler baseline.

## Local commands

Install Xcode 27.0 and its simulator runtimes, then mise 2026.9.11 or newer. Run `mise trust`, `mise install --locked`, `mise run generate`, and open `Mossling.xcworkspace`. No Tuist account is required.

| Command | Result |
| --- | --- |
| `mise run generate` | Generate the canonical Xcode snapshot |
| `mise run project:check` | Verify committed snapshot matches the manifest |
| `mise run build` | Unsigned phone/Watch simulator builds |
| `mise run test:core` | Portable domain tests |
| `mise run test:tooling` | Cloud failure/isolation tests and archive contract tests |
| `mise run test:ui` | Real iPhone forms/persistence in a disposable simulator |
| `mise run archive:check` | Unsigned device archive and embedded Watch validation |
| `mise run --jobs 1 verify` | Complete development/CI gate |

For hardware signing, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and supply the Apple team. Product IDs are versioned in `Config/Product.json`; they are not per-machine overrides. Change the proposed identifier before registration if unavailable, regenerate, and review. Once distributed, changing it creates a different app identity.

`project:check` expects a git checkout and committed generated files. During development, generated changes are expected; review and commit them before the full verification gate. Xcode/macOS upgrades are intentional changes to the manifest, GitHub runner and Cloud workflow together.

## Cloud integration

The two executable shell files under `ci_scripts` are Apple's required entry points. Each delegates immediately to `Tools/XcodeCloud.swift`; they contain no build or signing implementation.

Post-clone validates Apple's product/team/build variables, writes the ignored Cloud settings, verifies the pinned mise binary checksum, installs locked Tuist, runs domain tests and checks the generated snapshot. Xcode Cloud then performs native Test/Archive actions itself. It does not invoke the local simulator runner or nest another `xcodebuild` pipeline.

Post-xcodebuild preserves a failed native action's exit status. For a successful archive it calls the same `CheckArchive.swift` used locally, additionally requiring the exact Cloud bundle identifier, build number and marketing version. Other successful actions do nothing. Build numbering belongs to Xcode Cloud; no repository commits or timestamp incrementer are involved.

Apple copies the `ci_scripts` resources between phases and follows their symbolic links. The links to the Swift adapter, shared archive validator and product configuration intentionally give the post-action everything it needs without relying on the source checkout or post-clone side effects surviving. Keep the links and executable file modes intact.

## Cost and handoff

GitHub's Apple gate stays enabled until real Cloud verification is accepted. After the Cloud PR workflow and required checks are working, set repository variable `MOSSLING_XCODE_CLOUD_ACTIVE=true` to suppress automatic duplicate Mac jobs. Manual GitHub workflow runs retain the Apple job as a diagnostic fallback. Linux domain/tooling checks remain on GitHub.

That variable does not configure Cloud or impose a spending cap. GitHub usage budgets and Apple's included 25-hour plan are separate account settings; they have not been changed by this refactor. See [Release setup](Release.md) for the account-side steps and acceptance criteria.

## References

- [Apple project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud)
- [Apple custom scripts and phase resources](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Tuist Cloud integration](https://tuist.dev/en/docs/guides/integrations/continuous-integration)
- [mise tasks](https://mise.jdx.dev/tasks/) and [lockfiles](https://mise.jdx.dev/dev-tools/mise-lock.html)
