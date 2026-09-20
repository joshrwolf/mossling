# Development

Follow the [README setup](../README.md#setup) first. Task definitions and tool pins live in [mise.toml](../mise.toml).

## Daily commands

| Command | Use |
| --- | --- |
| `mise run test:core` | Portable domain tests; also runs on Linux |
| `mise run build` | Generate and build both simulator apps |
| `mise run --skip-deps build` | Reuse the generated project for incremental builds |
| `mise run test:tooling` | Cloud hooks, simulator runner and archive/plan guards |
| `mise run test:ui` | Full selected UI plan on a fresh disposable simulator |
| `mise run archive:check` | Unsigned Release archive and phone/Watch packaging checks |
| `mise run project:check` | Regenerate and reject differences from the committed snapshot |
| `mise run --jobs 1 verify` | All local verification gates |

Regenerate after adding/removing files or changing project configuration. Review and commit generated changes before running the drift gate. Keep builds serial: separate terminal invocations share DerivedData, and the UI helper's lock does not cover generation or unrelated Xcode builds.

## Focused UI tests

```sh
mise run test:ui:focus MosslingUITests/MosslingUITests/testCompletedSnackEarnsGrowthOnceAndSurvivesRelaunch
mise run diagnose:ui
mise run test:ui:cleanup
```

The focused command rebuilds incrementally, runs exactly one method, retains its owned simulator and writes a unique `.xcresult` under `.build-artifacts`. Reuse retains system notification permission even when tests reset app data. Run cleanup before fresh-install checks or a full suite; it removes only the validated owned device.

`test:ui` defaults to the All plan. `MOSSLING_UI_TEST_PLAN` selects a native plan for phased CI execution; it cannot override an explicit focused method. GitHub requires every partition and rejects incomplete, failed or skipped results. Focused runs do not replace full acceptance.

## Diagnostics

Inspect `.xcresult` bundles in Xcode. After a focused run, before cleanup, `diagnose:ui` saves Debug lifecycle intervals to `.build-artifacts/ui-lifecycle.log`. The helper shares the session lock; use Instruments to inspect a running test. Release builds omit these diagnostics.

For a reproduced stall, correlate XCTest timestamps with application intervals and profile using Instruments Time Profiler, Swift Concurrency or SwiftUI. UI readiness waits are bounded conditions, not fixed sleeps. Preserve exact state assertions when investigating asynchronous platform services.

If Xcode rewrites a generated scheme during regeneration, quit Xcode, regenerate, check the diff and reopen the workspace. Do not commit editor metadata or hand-edit generated project files.

## Device testing

Copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig`, set your Apple team, and select a connected device in Xcode. Use the Mossling or MosslingWatch scheme. Paired-device checks are described in [Release](Release.md).
