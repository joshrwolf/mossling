# Working on Mossling

Native iPhone and Apple Watch apps using Swift 6 strict concurrency, SwiftUI and Observation. Deployment targets: iOS 18 and watchOS 11. No backend, accounts, analytics or external Swift package dependencies.

## Code map

- `Packages/MosslingCore`: portable `MosslingCore` domain/persistence/sync and `MosslingApplication` Store targets with Swift Testing. Keep Apple UI/platform frameworks out.
- `Apps/Shared/StoreFactory.swift` wires live Store dependencies; Apple adapters live in `Apps/Shared/Platform`, shared presentation in `Apps/Shared/UI`.
- `Apps/iOS`, `Apps/Watch`, `Apps/UITests`: platform views and XCTest UI scenarios.
- `Project.swift`, `Tuist.swift`, `Config`: project graph, toolchain compatibility and product configuration. `mise.toml` owns development commands.

## Invariants

- Persist validated document mutations atomically before publishing state, celebrating completion or acknowledging received events. Preserve corrupt and unsupported saves; schema changes need migrations and fixtures.
- Phone configuration is authoritative. Completion events and the durable outbox must survive offline use; retain pending events until the peer acknowledges a successful save. Keep duplicate/reordered delivery idempotent and rewards derived from the ledger.
- Keep clocks and calendars explicit in domain logic. Timers must survive suspension and relaunch; animation must never award growth or drive durable state.
- Phone reminders have a finite horizon replenished on foreground. Preserve explicit permission opt-in, serialized notification mutations and visible scheduling failures. Watch delivery follows system routing.
- Honor Reduce Motion, scene activity and reduced Watch luminance in presentation.
- Voice: playful woodland exercise game, with direct instructions and brief celebrations. Call exercise sessions “snacks” and the exercises “activities.” Keep the forest theme; avoid meditation/wellness language, padded reassurance and excessive praise. Retain practical exercise guidance.

## Workflow

- Use the pinned mise/Tuist toolchain and local Xcode. See [development commands](docs/Development.md); use focused checks while editing and relevant full gates before merging. Preserve assertions and coverage.
- Edit the Tuist manifest/configuration, regenerate, and commit generated project changes together. Xcode Cloud requires the tracked project/workspace snapshots. Keep local signing settings and build artifacts ignored.
- GitHub verifies changes; Xcode Cloud signs and distributes. Preserve registered product identifiers, Cloud build numbering and the executable hooks/symlinks in `ci_scripts`. See [release operations](docs/Release.md).
- Inspect existing changes before editing. Keep commits and PRs coherent; obtain independent review at substantial architecture, persistence or release boundaries.
- Keep documentation concise and about current setup, behavior or procedures. Record history, experiments, benchmarks, review findings, plans and handoffs in issues/PRs. Update existing guidance instead of appending status sections or duplicating APIs.
