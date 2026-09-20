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
| Pull request and main verification | GitHub Actions |
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

The repository is public. Standard GitHub-hosted runners provide PR/main verification; Xcode Cloud owns managed signing and manually started delivery. The GitHub Apple gate is unconditional: connecting Cloud does not disable native PR coverage. The former `MOSSLING_XCODE_CLOUD_ACTIVE` migration switch has been removed.

Keep Apple's included Cloud plan and avoid automatic duplicate PR workflows there. Account usage budgets remain separate from repository configuration. See [Release setup](Release.md) for signing/delivery acceptance criteria.

## References

- [Apple project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud)
- [Apple custom scripts and phase resources](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Tuist Cloud integration](https://tuist.dev/en/docs/guides/integrations/continuous-integration)
- [mise tasks](https://mise.jdx.dev/tasks/) and [lockfiles](https://mise.jdx.dev/dev-tools/mise-lock.html)


## Native CI ownership and parallelism

GitHub verifies every PR and main commit. Xcode Cloud owns Apple-hosted signing and delivery; it uses native Test/Archive actions rather than the GitHub simulator helper. The generated shared Mossling scheme defaults to the **All** Xcode test plan, so local Xcode and Cloud keep the complete UI suite.

| GitHub job | Responsibility |
| --- | --- |
| Domain (Linux) | Portable domain tests and tooling contracts |
| Apple builds/archive | Real Cloud preparation adapter, Apple Foundation domain tests, both generic simulator schemes, Release archive and detached archive adapter, generated-project drift |
| iPhone UI / Focused | Two longer persistence/affinity flows on its own standard VM |
| iPhone UI / Remainder | Every other UI test on a separate standard VM |
| Verify all required checks | Fail if any required job or UI partition failed, was cancelled, or was skipped |

`Config/Tests/*.xctestplan` owns test selection, coverage and serial target execution. Focused selects the two long flows; Remainder skips exactly those, so new tests automatically join Remainder. Tooling checks protect the complementary selection. Each native result must report exactly the selected test count, all passed, with no skipped or expected-failure results; empty or incomplete runs fail the gate. Each VM runs one simulator; this avoids the resource contention observed with two simulator workers on one 7 GB host. Both partitions remain mandatory, with no retries or quarantined tests.

Each UI job generates once and builds its own products before booting. Compilation is short relative to real UI automation, so no cross-machine product relocation or custom shard scheduler is needed. The simulator helper is compiled before boot and reused for preparation, test execution and cleanup. Its fresh-device ownership checks also protect local developer simulators and isolate notification permission state. Replacing it with Tuist's existing-device selection would lose that isolation.

Mise owns task dependencies and pinned tools. The pinned Tuist test command normally regenerates a project, while hosted sharding requires a Tuist project account/server. The current CI uses native Xcode test plans and GitHub's matrix instead of adding another service or duplicate generation. Direct `xcodebuild` invocations remain Apple's supported build interface.

## Running and diagnosing UI tests

`mise run test:ui` builds and runs **All** by default, then cleans up its disposable simulator. Select one native plan with `MOSSLING_UI_TEST_PLAN=Focused mise run test:ui` or `Remainder`. The shared local `verify` graph waits for generic simulator builds before UI execution because those tasks share DerivedData.

For phase-level diagnosis, run `test:ui:build`, `test:ui:prepare`, `test:ui:run`, then `test:ui:cleanup`. Run cleanup after interrupted preparation/testing before starting a new session. An existing simulator state is never silently overwritten. These tasks reuse the compiled helper; `tools:ui` rebuilds it when its source/configuration changes.

GitHub exposes phase durations directly in named steps. Routine host snapshots and duplicate custom timing files are removed from the critical path. A failed simulator run attempts a bounded resource snapshot, and every run retains XCTest results and screenshots for seven days. The helper disables the broad system diagnostic collection that previously stalled for 600 seconds; opt in locally with `MOSSLING_UI_DIAGNOSTICS=1` when investigating deliberately.

The accepted serial baseline passed three native runs: **16m52s**, **14m52s**, and **14m14s** on main, with all seven UI flows passing. [PR #12](https://github.com/joshrwolf/mossling/pull/12) contains the evidence. Native-plan parallelism must be measured against that baseline; [issue #8](https://github.com/joshrwolf/mossling/issues/8) records performance evidence and follow-up work. GitHub checks establish unsigned build/test/package behavior; actual Apple Cloud and paired-device acceptance remain separate.
