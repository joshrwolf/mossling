# Validation report — 19 September 2026

## Executed checks

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Swift package compilation | PASS | Swift6.2 on Linux and Xcode26.2 on hosted macOS, strict Swift6 language mode |
| Portable tests | PASS | **42 tests across7 suites** on both Linux and macOS, `scripts/verify-core.sh` |
| Native Apple SDK builds | PASS | Both iOS Simulator and watchOS Simulator schemes compile with Xcode26.2 (17C52), signing disabled |
| Hosted project drift | PASS | Regeneration leaves project, schemes and generated plists unchanged |
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

## Hosted CI evidence

[Verify run 35469879666](https://github.com/joshrwolf/mossling/actions/runs/35469879666) passed both jobs for source commit `1bac23f672f9c31d61085d2196817ec13de56dc7` on 19 September 2026. The Apple job built both simulator schemes, ran all 42 tests against Apple's Foundation, and passed the project drift check. The Linux job independently passed all 42 tests. All 18 committed PNG Git blob hashes match their local source files.

The first hosted build exposed four unsupported titled-section/footer initializers in `RhythmView.swift`. They were corrected with explicit header builders in a follow-up commit. Independent comparison confirmed that content, bindings, accessibility identifiers and behavior were unchanged. The succeeding run above verifies the correction against the real Apple SDKs. Xcode's only warnings were skipped App Intents metadata extraction; no App Intents dependency is used.

## Remaining Apple gates

This workspace is Linux; the Apple build checks ran remotely on GitHub-hosted macOS. The native targets are now **Apple-build-verified**, but have **not yet been visually or behaviorally accepted on simulators or physical devices**. Compilation does not establish notification delivery, paired-device synchronization or visual quality.

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
