# Validation report — 19 September 2026

## Executed checks

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Swift package compilation | PASS | Swift6.2 on Linux and Xcode26.2 on hosted macOS, strict Swift6 language mode |
| Portable tests | PASS | **42 tests across7 suites** on both Linux and macOS, `mise run test:core` |
| Native Apple SDK builds | PASS | Both iOS Simulator and watchOS Simulator schemes compile with Xcode26.2 (17C52), signing disabled |
| Unsigned Release archive | PASS | Device compilation and phone/Watch packaging contract verified in hosted run 35471434396 |
| iPhone UI automation | CI GATE | Three tests exercise onboarding and persisted activity/schedule forms; latest result and artifacts are linked from PR #2 |
| Native Swift source syntax | PASS | Swift frontend parse of phone/watch/shared files; not Apple SDK typechecking |
| Store concurrency/type integration | PASS with limitation | Independent reviewer typechecked the actual iOS Store branch under Swift6 using inert actor-equivalent adapter stubs; does not validate SDK conformance |
| Xcode project generation | PASS | Tuist4.208.0 generates both apps and UI test target from typed manifests; generated project snapshots are now tracked for Cloud discovery and checked for drift |
| Project/plist/asset checks | PASS | Generated source membership, watch embedding, local package, asset references, icon dimensions, plist/XML and shell syntax inspected |
| Architecture review | COMPLETE | `reviews/architecture-review.md` invariants incorporated |
| Implementation review | COMPLETE | `reviews/implementation-review.md`; confirmed findings fixed |
| UI review | COMPLETE | `reviews/ui-review.md` and `reviews/ui-review-resolution.md`; independent source re-review verified U1–U5 fixes |
| Repository | PUBLISHED | Private `joshrwolf/mossling`; coherent foundation commits, with hosted checks tracked in the pull request |
| Deployment | NOT PERFORMED | No signing configuration, TestFlight or App Store upload |

Tests cover civil-time boundaries, DST gap/repeated hour, local-zone identity, validated notification capacity, timer restoration, immutable activity snapshots, no future/expired completion, unique rewards, commutative event merge, bounded sync packets, malformed protocol rejection, persist-before-publish, completion/outbox atomicity, durable ACK sequencing, restart recovery, phone authority replacement and retired-authority rejection, and idempotent non-destructive backup recovery.

## Tuist lifecycle and simulator evidence

[PR #2](https://github.com/joshrwolf/mossling/pull/2) records the earlier Tuist migration source and complete hosted CI outcome. [Run 35471434396](https://github.com/joshrwolf/mossling/actions/runs/35471434396) established successful Tuist generation, 42 tests on both platforms, both simulator builds, and a real unsigned Release archive with a valid embedded Watch bundle. The archive checks platform, resolved identifiers, matching versions, companion relationship, executables, compiled assets and privacy manifests.

That first simulator run also passed snack creation/editing and persistence across relaunch. Two other assertions exposed test interaction mistakes: the notification label is combined by iOS accessibility, and a row-center tap missed the weekday switch. Captured screenshots, interaction events and accessibility hierarchy established these causes. The follow-up tests target the actual accessibility label/control and require the weekday to change before saving, remain changed after cadence editing, and survive relaunch. The final PR checks remain the authoritative acceptance result; the failing run alone is not counted as a complete UI pass.

Screenshot review covered the actual welcome, resting forest, activity list/editor and schedule form on the selected iPhone simulator. The character body/face/fern and text render together without observed corruption. This is a limited default-size visual pass, not full accessibility or Watch rendering acceptance. UI result bundles and screenshots are retained as workflow artifacts for seven days. [Independent tooling review](reviews/tooling-review.md) records the isolation and assertion review.

## Earlier foundation evidence

[Verify run 35469879666](https://github.com/joshrwolf/mossling/actions/runs/35469879666) passed both jobs for source commit `1bac23f672f9c31d61085d2196817ec13de56dc7` on 19 September 2026. The Apple job built both simulator schemes, ran all 42 tests against Apple's Foundation, and passed the project drift check. The Linux job independently passed all 42 tests. All 18 committed PNG Git blob hashes match their local source files.

The first hosted build exposed four unsupported titled-section/footer initializers in `RhythmView.swift`. They were corrected with explicit header builders in a follow-up commit. Independent comparison confirmed that content, bindings, accessibility identifiers and behavior were unchanged. The succeeding run above verifies the correction against the real Apple SDKs. Xcode's only warnings were skipped App Intents metadata extraction; no App Intents dependency is used.

## Remaining Apple gates

This workspace is Linux; the Apple build checks ran remotely on GitHub-hosted macOS. The native targets are now **Apple-build-verified**, but have **not yet completed the full simulator/accessibility matrix or physical-device acceptance**. Compilation does not establish notification delivery, paired-device synchronization or visual quality.

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

## Xcode Cloud integration

[PR #3](https://github.com/joshrwolf/mossling/pull/3) records the exact accepted source and hosted gate outcome for the Cloud integration. The gate runs the real checksum-verified Cloud preparation adapter with a fixture team and build 42, confirms clean project regeneration, performs the native unsigned archive and UI tests, and invokes the post-action from an isolated copy of its phase resources. Shared archive validation requires the configured identity, marketing version and build 42, including the embedded Watch relationship.

Local adversarial tests cover 27 rejected/failing Cloud cases and seven archive contract cases. Two independent reviews found loss of drift enforcement after the CI handoff and optional signing files contaminating the generated graph. Both were corrected; see [Cloud review](reviews/tooling-review.md#xcode-cloud-adversarial-review).

Repository integration and hosted macOS simulation do not establish actual Xcode Cloud activation. The account connection, real Apple-hosted workflow, managed signing, distribution and physical-device acceptance remain pending. The initial Cloud workflow explicitly uses Archive preparation None and no distribution post-action.
