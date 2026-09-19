# Mossling

A private iPhone + Apple Watch app that turns small movement breaks into a growing woodland companion. Working title, not a registered product name.

**Implementation status:** the Tuist-generated iPhone and Watch apps compile with Xcode 26.2 on hosted macOS, and the unsigned Release archive passes phone/Watch packaging checks. CI runs 42 domain tests on Linux and macOS plus three simulator UI acceptance tests with retained screenshots. [PR #2](https://github.com/joshrwolf/mossling/pull/2) tracks the current migration and complete CI result. Paired-device acceptance, signing and TestFlight delivery remain pending. See [Validation](docs/Validation.md).

## What is implemented

- A warm forest home with a round fern spirit, breathing/blinking, cozy rest, happy celebration, three visual growth stages, and permanent fern/mushroom/pond unlocks.
- Configurable weekdays, daytime active window, and 60/90/120-minute cadence. Choose from starter activities or create/edit your own rep- or duration-based activity.
- Persistent snack sessions with pause/resume and explicit completion. Duration snacks require the timer to finish; repetitions are confirmed by the user.
- Phone-owned local reminders, permission opt-in, ten-minute snooze within the current snack window, and normal system notification routing to Watch.
- A watch companion with cached settings, a timer, manual completion, saved offline progress, and bounded synchronization when the paired apps connect.
- A journal showing earned breaks and growth, JSON backup export, and non-destructive progress merge from a backup.
- Persist-before-publish transactions, application-level acknowledgments, deduplicated rewards, supported-version checks, strict Swift 6 concurrency, and testable calendar/clock inputs.

There is no account, backend, analytics SDK, in-app payment, HealthKit requirement, or runtime AI dependency. Art is bundled. No exercise camera/rep detection, Screen Time blocking, independent watch reminder scheduling, or social features are included.

## Open on a Mac

Install Xcode **26.2**, its iOS/watchOS simulator runtimes, and [mise](https://mise.jdx.dev/getting-started.html). The apps support iOS 18+ and watchOS 11+.

```sh
mise trust
mise install --locked
mise run generate
open Mossling.xcworkspace
```

`Project.swift` defines the typed Tuist project graph. Generated Xcode files are disposable and ignored by Git. Choose **Mossling** and an iPhone simulator, or **MosslingWatch** and a paired watch simulator. No Tuist account or paid Apple membership is needed for local generation or simulator checks.

```sh
mise run test:core           # Portable Swift domain tests, Linux or macOS
mise run build               # iPhone + Watch simulator builds
mise run test:ui             # Real forms/persistence in a disposable iPhone simulator
mise run archive:check       # Unsigned Release packaging and embedded Watch validation
mise run --jobs 1 verify     # The same complete lifecycle used by GitHub Actions
```

[mise.toml](mise.toml) owns tools and task dependencies; [Project.swift](Project.swift) owns targets and schemes. Xcode remains the underlying build engine. [Tooling](docs/Tooling.md) explains these boundaries and [Release preparation](docs/Release.md) records what remains before TestFlight. Nothing automatically deploys.

For hardware, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, choose a unique bundle prefix, and enter your Apple team. Never commit that local file. TestFlight remains a later setup step after the Apple acceptance pass.

## Try the loop

1. Open the phone app and meet the creature. Allow reminders if desired; the app remains usable without notification permission.
2. In **Rhythm**, choose today's weekday and an active window containing the current hour. Defaults are Monday–Friday, 09:00–17:00, hourly. The end time is exclusive: 17:00 means the last hourly snack starts at 16:00.
3. In **Snacks**, enable preferred activities or add a short custom test activity.
4. Return to **Forest**, start the currently available snack, finish it, and confirm. A unique scheduled-hour break earns 10 growth.
5. Three rewarded breaks reveal the sprout stage; fifteen reveal the guardian. Forest details unlock along the way. Reopen after a break: the timer and progress persist.
6. Open both paired apps once. Start/complete a watch snack, including with the phone temporarily unavailable, then reconnect/reopen to reconcile. The physical-device test plan checks the actual transport and notification behavior.

An expired snack creates no debt and never subtracts progress. A snack must be completed before the next scheduled slot or quiet hours. The app refuses to start a duration target that cannot fit the remaining window. This is a deliberate MVP rule; a later started-session grace policy can be added in the domain.

## Project map

| Path | Purpose |
| --- | --- |
| `Packages/MosslingCore` | Pure Swift scheduling, progression, save format, transactions, sync protocol and tests |
| `Apps/Shared/Store.swift` | Observable app coordinator, durable state, notification ordering, sync orchestration |
| `Apps/Shared/Platform` | UserNotifications and WatchConnectivity adapters |
| `Apps/Shared/UI` | Shared layered character, animation and forest presentation |
| `Apps/Shared/Assets.xcassets` | Bundled body layer and phone/watch icons |
| `Apps/iOS` | Forest, activity editor, rhythm settings, journal, backup, session, onboarding |
| `Apps/Watch` | Wrist home, activity choice and session |
| `Project.swift`, `Tuist.swift`, `Config` | Typed project graph, schemes, signing overrides and privacy declarations |
| `mise.toml`, `mise.lock`, `.github/workflows` | Pinned tools and the shared local/CI task graph |
| `Apps/UITests`, `Tools` | UI acceptance tests, disposable simulator lifecycle and archive contract checks |
| `docs/reviews` | Architecture, implementation, and UI review findings and resolution |

## Foundation decisions

The shared package owns behavior, not Apple UI frameworks. Both applications use the same reward and schedule rules. Apple adapters transport bytes or schedule notifications; neither is allowed to award growth.

A small versioned JSON document is the local source of truth. Each transaction prepares a candidate, validates it, atomically writes it, then publishes it to the UI. A completion and its sync outbox entry are one transaction. A receiver acknowledges only a successful durable commit. A failed save does not show a celebration.

Phone settings are authoritative; the watch receives versioned snapshots. Each phone installation has an authority ID, so a new phone can replace a higher-revision previous install. Retired authorities cannot roll settings back. Completions are an immutable ledger with deterministic event merge and unique scheduled-hour reward keys. Repeated packets or two devices completing one opportunity cannot double the reward.

The initial SwiftData proposal was intentionally replaced by this small atomic document store. It keeps transactions and recovery explicit, permits real Linux tests, and avoids unneeded query/migration complexity for a personal event ledger. Storage is behind a repository protocol so a future database can replace the file without changing schedule or reward logic.

Read [Architecture](docs/Architecture.md), [Core API](docs/CoreAPI.md), [Sync API](docs/SyncAPI.md), and [Platform constraints](docs/platform-constraints.md) before extending behavior.

## Data and recovery

Progress lives in the app container on each device. Watch synchronization is not an off-device backup. Export JSON from Rhythm periodically; importing a backup from Journal merges completions while preserving this installation's settings and device identity. Re-importing is idempotent. Unknown/corrupt saves are preserved rather than silently reset.

This version has no public save-format migration yet because it is the first unreleased schema. Any future shipped schema change needs an explicit migration and fixtures. Restoring an old whole-device backup may restore an old configuration authority/revision; the sync review documents that edge case. JSON progress-merge recovery avoids replacing authority IDs.

## Asset provenance

Character body and app icon were generated for this project from the selected original round woodland spirit direction. The body deliberately has no face/fern; those layers are native SwiftUI so they can move independently. Icon sizes are deterministic resamples of the generated icon. Artwork is bundled, with no runtime generation or downloaded assets. [Art direction](docs/Art.md) records the production intent and animation scope.
