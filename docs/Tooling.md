# Project and delivery tooling

## Responsibility boundaries

| Layer | Tool | Source of truth |
| --- | --- | --- |
| Targets, resources, dependencies, schemes | Tuist 4.208.0 | `Project.swift`, `Tuist.swift` |
| Tool versions and task dependencies | mise 2026.9.11 | `mise.toml`, `mise.lock` |
| Compilation, linking, app packaging | Xcode 26.2 | Generated project and checked-in xcconfig/plists |
| Portable domain package | Swift Package Manager | `Packages/MosslingCore/Package.swift` |
| Remote execution and retained evidence | GitHub Actions | `.github/workflows/ci.yml` |
| Signed TestFlight delivery | Not activated | `Release.md` |

Tuist replaces XcodeGen and committed generated project files. Its Swift manifest makes the app, Watch embedding, resources and UI test target explicit in one typed graph. mise owns a discoverable lifecycle instead of separate bootstrap/build shell entry points. GitHub Actions invokes that lifecycle; it does not contain a second build implementation.

Tuist does not replace Apple's compiler or sign/distribute TestFlight releases. Its cloud services are optional; this project needs no Tuist account. Fastlane is a possible future release orchestrator, not a prerequisite for this graph. A paid Apple membership is required for TestFlight, not for this CI pipeline.

## Local development

Install Xcode 26.2 with iOS/watchOS simulators, select it as the active developer directory, and install mise 2026.9.11 or newer. Run `mise trust`, `mise install --locked`, and `mise run generate`. Open `Mossling.xcworkspace`.

The manifest pins Xcode 26.2 compatibility to the verified CI baseline. Upgrade the manifest and CI together, then run all gates. Swift comes from Xcode on macOS; Linux CI uses `swift:6.2-noble`. Source uses strict Swift 6 concurrency with minimum iOS 18/watchOS 11.

For local hardware signing, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and supply a unique reverse-DNS bundle prefix and Apple team. This override is ignored. Generated projects/workspaces are also ignored: never hand-edit or commit them. Assets and privacy manifests remain versioned inputs.

## Lifecycle

| Command | Result |
| --- | --- |
| `mise run generate` | Generate apps and UI test target |
| `mise run build` | Unsigned phone/Watch simulator builds |
| `mise run test:core` | Portable Swift tests on Linux or macOS |
| `mise run test:ui` | Fresh simulator, real form operations, persistence checks and screenshots |
| `mise run archive:check` | Unsigned device Release archive and phone/Watch packaging check |
| `mise run --jobs 1 verify` | All gates, with shared generation through the dependency graph |

Each task declares generation when needed. CI runs sequentially to keep resource usage predictable. Validation is never skipped based on timestamps; Xcode still reuses its normal incremental compiler outputs.

Two small Swift tools implement project-specific checks: `RunUITests.swift` owns disposable simulator creation/cleanup, execution and evidence export; `CheckArchive.swift` checks the produced app bundle relationship. They do not implement dependency resolution or compilation. UI test document/preferences hooks compile only into Debug simulator builds. Release/device builds contain no reset path.

CI retains screenshots and the Xcode result bundle for seven days, including failed runs. This evidence does not establish real notification delivery, paired Watch connectivity, accessibility acceptance or physical-device power behavior.

## Release boundary

`archive:check` exercises optimized device compilation before enrollment completes. Its archive is unsigned and cannot be installed or submitted. There is no upload task or credential-bearing PR job. See [Release preparation](Release.md).

## Primary references

- [Tuist 4.208.0](https://github.com/tuist/tuist/releases/tag/4.208.0)
- [mise tasks](https://mise.jdx.dev/tasks/)
- [mise tool lockfiles](https://mise.jdx.dev/dev-tools/mise-lock.html)
- [Fastlane archive orchestration](https://docs.fastlane.tools/actions/build_app/)
- [Xcode Cloud and TestFlight](https://developer.apple.com/xcode-cloud/)
