# Validation report — 19 September 2026

## Executed in this workspace

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Swift package compilation | PASS | Official Swift6.2 Linux toolchain, strict Swift6 language mode |
| Portable tests | PASS | **42 tests across7 suites**, `scripts/verify-core.sh` |
| Native Swift source syntax | PASS | Swift frontend parse of phone/watch/shared files; not Apple SDK typechecking |
| Store concurrency/type integration | PASS with limitation | Independent reviewer typechecked the actual iOS Store branch under Swift6 using inert actor-equivalent adapter stubs; does not validate SDK conformance |
| Xcode project generation | PASS | Unmodified XcodeGen2.46.0 generated both targets, plists and shared schemes |
| Project/plist/asset checks | PASS | Generated source membership, watch embedding, local package, asset references, icon dimensions, plist/XML and shell syntax inspected |
| Architecture review | COMPLETE | `reviews/architecture-review.md` invariants incorporated |
| Implementation review | COMPLETE | `reviews/implementation-review.md`; confirmed findings fixed |
| UI review | COMPLETE | `reviews/ui-review.md` and `reviews/ui-review-resolution.md`; independent source re-review verified U1–U5 fixes |
| Repository | PUBLISHED | Private `joshrwolf/mossling`; coherent foundation commits, with hosted checks tracked in the pull request |
| Deployment | NOT PERFORMED | No signing configuration, TestFlight or App Store upload |

Tests cover civil-time boundaries, DST gap/repeated hour, local-zone identity, validated notification capacity, timer restoration, immutable activity snapshots, no future/expired completion, unique rewards, commutative event merge, bounded sync packets, malformed protocol rejection, persist-before-publish, completion/outbox atomicity, durable ACK sequencing, restart recovery, phone authority replacement and retired-authority rejection, and idempotent non-destructive backup recovery.

## Remaining Apple gates

This workspace is Linux and has no Xcode or Apple SDKs. The native targets are implemented and source-reviewed, but **not yet Apple-build-verified or proven usable on devices**. Do not describe the result as a tested shipping app.

The next gate can run on a GitHub-hosted macOS runner after the source is pushed to a private repository. The included Actions workflow compiles both simulator targets, runs domain tests on macOS, and verifies generated project drift without signing. It does not require leaving a personal Mac running. Physical hardware and visual acceptance still need a paired iPhone/watch.

### Mac or hosted Mac build gate

- Run `scripts/verify-apple.sh` on Xcode26.2 or validated newer stable Xcode.
- Resolve any Apple SDK availability, SwiftUI type-inference, delegate-conformance, asset-catalog or embedding diagnostics before installation.
- Confirm both schemes run on their simulator destinations and the companion installs beside the phone app.

### Simulator and hardware acceptance

- First launch: no premature permission failure, onboarding can be skipped, deny/allow permissions reflected truthfully.
- Create/edit/disable activities; reject invalid targets or an empty enabled pool. Configuration survives relaunch.
- Set today's window and start a snack; timer pause/resume survives closing/reopening. Zero alone never grants growth.
- Complete one opportunity from both devices while disconnected; reconnect and confirm one reward and one journal moment.
- Offline watch completion survives process termination; reopen/reconnect eventually acknowledges it and clears pending status.
- Reminder arrives with app closed. Snooze stays before expiry; completion clears one-shot snooze without removing next week's recurring request.
- Change schedule; confirm obsolete pending reminders are removed and future reminders match the new schedule.
- Tap a notification from Rhythm, Journal, an activity editor and a session; Forest navigation resolves correctly.
- Check actual system DST/zone/Focus behavior; domain date tests are not notification delivery tests.
- Show all creature moods/stages and unlocks on a small phone and watch. Inspect alpha edges, face alignment, fern attachment, legibility, and clipping.
- Check large Dynamic Type, VoiceOver, Reduce Motion, dark watch UI, dim/always-on watch state, and foreground energy use.
- Export from Rhythm; import from Journal; verify current settings stay unchanged and repeating the merge adds no rewards.
- Check cold background watch launch/WatchConnectivity lifecycle. Current reliable recovery path explicitly includes reopening the apps; automatic cold-background acknowledgments have not been established.

### Later TestFlight gate

Set unique bundle IDs/developer team, validate Release archive/signing, recheck required-reason privacy declarations and icon acceptance, then configure internal testers and upload. This is intentionally not enabled by current CI.

## Known scope limits

No overnight schedule, sub-hour cadence, arbitrary explicit-time list, automatic activity verification, started-session grace period, cloud backup, or independent watch reminders. Whole-device backup restoration can restore an old authority/revision; JSON progress merge preserves the live identity and avoids that path. Unreleased schema1 requires a proper migration plan before any later shipped schema change.
