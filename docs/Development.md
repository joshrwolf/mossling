# Development

Follow the [README setup](../README.md#setup) first. Task definitions and tool pins live in [mise.toml](../mise.toml).

## Daily commands

| Command | Use |
| --- | --- |
| `mise run test:core` | Domain and Store tests with real-file persistence; also runs on Linux |
| `mise run test:app` | Store integration tests without a simulator |
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

`test:ui` defaults to the All plan. `MOSSLING_UI_TEST_PLAN` selects a native plan for phased CI execution; it cannot override an explicit focused method. GitHub requires every partition and rejects incomplete, failed or skipped results. Focused runs do not replace full acceptance. UI tests cover controls and presentation; Store tests cover workflow persistence and failure ordering. Debug simulator fixtures reset only the isolated UI-test document/preferences; onboarding and completion retain real process-relaunch checks.

## Diagnostics

Inspect `.xcresult` bundles in Xcode. After a focused run, before cleanup, `diagnose:ui` saves Debug lifecycle intervals to `.build-artifacts/ui-lifecycle.log`. The helper shares the session lock; use Instruments to inspect a running test. Release builds omit these diagnostics.

For a reproduced stall, correlate XCTest timestamps with application intervals and profile using Instruments Time Profiler, Swift Concurrency or SwiftUI. UI readiness waits are bounded conditions, not fixed sleeps. Preserve exact state assertions when investigating asynchronous platform services.

If Xcode rewrites a generated scheme during regeneration, quit Xcode, regenerate, check the diff and reopen the workspace. Do not commit editor metadata or hand-edit generated project files.

## Device testing

Copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig`, set your Apple team, and select a connected device in Xcode. Use the Mossling or MosslingWatch scheme. Paired-device checks are described in [Release](Release.md).

## Artwork

`WoodlandGround`, `WoodlandProps` and `BrackenSprites` in the shared asset catalog supply the painted scene. `ForestArt.swift` owns source-pixel frames, ground-contact anchors and rendered sizes; update these together when replacing an atlas. Preserve transparent gutters around sprites and check both scene and portrait crops. Review an empty clearing, a furnished expanded habitat, placement previews and the small Watch display at native scale; concept boards alone do not verify integration.

`ActivityCatalog` defines movement families and their named variations. A rotation stores one selected variation per family; custom activities remain independent. `ActivityDefinition` snapshots preserve the chosen instructions, target and pose in sessions and journal events. Variation changes go through the normal configuration transaction and retain the rotation row ID.

`ActivityArtwork.swift` maps movements to frame clips in the `Bracken…Motions` imagesets. Each clip has source-pixel rectangles, a poster frame and per-frame timing; keep a shared canvas and fixed contacts across its poses. The detail sheet plays two repetitions, supports replay and stops for scene inactivity or Reduce Motion. Replacing a clip with more frames does not change catalog or persistence data. Check card, detail and Watch crops, plus large text and Reduce Motion.

New forests use a seeded composition with a protected path, edge pond, rear canopy and open building patch. Save the realized `ForestLandscape` with the world; generation only runs when creating a document. Terrain changes require save/transport migration, connectivity tests and native visual review.
