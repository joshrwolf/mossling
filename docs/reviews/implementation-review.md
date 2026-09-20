# Independent implementation review

Reviewed 2026-09-19. Scope: domain, atomic document persistence, synchronization, shared store, Apple adapters, project generation and CI. The UI was still being completed during this review. This is a source/invariant review with executable portable verification, not an Apple SDK acceptance report.

## Verdict

The core persistence and reward design is sound for the household MVP. Forty tests in six suites pass with Swift 6.2 on Linux. The actual `MosslingStore` also passes Swift 6 strict-concurrency typechecking with its iOS branch enabled and inert, actor-equivalent adapter stubs. That second check establishes store language/isolation correctness only; it does not validate SDK protocols, API availability, SwiftUI rendering, or device behavior.

No confirmed remaining data-loss or double-reward blocker was found after the fixes below. Both Apple target builds and paired-device acceptance remain required before describing the app as installable and usable.

## Findings addressed during review

### P1 — Phone reinstallation could permanently strand watch settings

Confirmed in the original `Packages/MosslingCore/Sources/MosslingCore/DocumentSync.swift`, `receive(_:into:)`: accepting only a greater revision means a reinstalled phone at revision zero cannot replace a watch's previously received revision. The event inventory repairs history but does not repair configuration.

Implemented fix: `ConfigurationSnapshot.authorityID` carries the phone installation identity. The watch records its current authority and retired authorities in `AppDocument`. A new authority may start at zero; a previously retired authority cannot roll back the new phone with delayed delivery. Same-authority stale revisions remain rejected. The portable `phoneReinstallAcceptsNewAuthorityAndRejectsDelayedRetiredAuthority` regression passes, including persistence round trips.

Remaining boundary: restoring an old backup with the **same** installation identity and lower revision is not equivalent to a new installation. Restoring an already retired installation is also rejected. A future explicit configuration-recovery handshake should address backup restoration; simply accepting all lower revisions would reintroduce rollback races.

### P2 — First launch and denied permission produced avoidable global errors

Confirmed in original `Apps/Shared/Store.swift`, `bootstrap()` → `reconcileNotifications()`, and `Apps/Shared/Platform/NotificationService.swift`, `replaceSchedule(_:)`. The default schedule is enabled, so passive reconciliation before the onboarding permission request threw `permissionRequired` and raised the root error alert. Declining notification permission repeated this on every foreground launch.

Implemented fix: passive reconciliation checks scheduling authorization and treats an ungranted permission as ordinary status. Disabled schedules still reconcile an empty set. An explicit snooze without permission can still report its actionable error.

### P2 — Privacy manifest omitted the onboarding preference API

Confirmed: `Apps/iOS/MosslingRootView.swift` uses `@AppStorage("hasSeenWelcome")`; the original manifest declared no required-reason API usage.

Implemented fix: `Config/PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults` with own-application reason `CA92.1`. Keep the tooling document consistent. Archive validation is still required for distribution.

### P2 — Durable composition needed direct tests

The original tests checked ledger merge/protocol and repository atomicity separately, leaving `DocumentSync` composition untested. `DocumentSyncTests.swift` now exercises completion/outbox/session transactions, write failures, ACK persistence, restart recovery, peer completions, stale configuration, and reinstall authority. These regression tests pass.

### P3 — A transport failure after a successful commit claimed state was unchanged

Original `MosslingStore.receive(_:channel:)` used one catch message for decoding, durable merge, and sending the ACK. An ACK enqueue error after a durable merge therefore claimed progress had not changed. The message now correctly says saved progress is retained and sync can be retried.

## Required Apple verification, not confirmed source defects

1. Run `scripts/verify-apple.sh` on the pinned Xcode baseline. The Linux store check cannot establish `WCSessionDelegate`/`UNUserNotificationCenterDelegate` conformance or SwiftUI availability. The explicit `nonisolated` delegate methods extract `Data`/value types before hopping to MainActor; no obvious cross-actor SDK object capture was found.
2. Verify background cold-start synchronization. At review time, both `Apps/iOS/MosslingApp.swift` and `Apps/Watch/MosslingWatchApp.swift` bootstrap connectivity in view `.task` and active-scene changes. There is no watch background-task delegate. Foreground activation/reopening is the dependable recovery boundary in this source; do not promise automatic background convergence until tested. If needed, initialize transport independently of view appearance and integrate the watch background task lifecycle without completing its task before pending callbacks durably commit.
3. Exercise notification callbacks on a paired phone/watch: fresh permission, denied permission, snooze followed by completion, schedule edit while snooze is awaiting, next-week recurrence after completion, and Focus/mirroring behavior. The store serializes notification mutations, but `UNUserNotificationCenter` itself has no atomic replace operation.
4. Validate AppIcon assets, embedded watch bundle/signing, and a Release archive. These are real SDK/distribution gates; generated-project consistency and unsigned simulator builds alone do not validate a TestFlight archive.

## Invariants verified by inspection and tests

- `DocumentController.transact` copies the document, validates, atomically saves, then publishes. Failed writes cannot publish candidate progress.
- `DocumentSync.complete` commits the event, delivery obligation, and session clearing in one document. Store celebration follows commit.
- Received event ACKs are sent only after `commit` returns success. An ACK is not inferred from transport delivery.
- Growth derives from unique immutable reward keys, not remote XP totals. Concurrent phone/watch completion yields one growth reward after merge.
- Sessions retain their original opportunity/activity snapshot. Settings edits do not reinterpret earned events or paused timers.
- Watch settings changes are blocked at the store and transport boundary. The watch cannot start with its unsynchronized default schedule.
- Event packets are bounded by both count and encoded bytes; full-history recovery is streamed as bounded packets. Exact outstanding transfer deduplication does not permanently suppress later retries.
- `markCompleted` removes pending one-shot snoozes and delivered notifications; it does not delete recurring pending requests.
- Delegate/store ownership is retained for the process, callbacks use weak store references, and notification operation sequencing is serialized. No confirmed Task return/inference or store actor-isolation error was found.

## Future hardening

The full JSON ledger is encoded on the main actor and history reconciliation resends all events on an inventory mismatch. This is reasonable for a small, low-frequency household app, but profile multi-year histories before adding more event types. Add migrations before changing a distributed schema; the current unreleased schema additions do not establish a migration framework. Time-zone travel may make removal of an already delivered reminder imprecise because the receipt path derives its weekday/minute from the current zone; this does not affect reward identity, future recurring reminders, or saved history.

## Everyday snack loop review (September 2026)

An independent reviewer examined the full daily-loop diff, separately from the domain, notification-adapter, UI-test, and integration authors. Confirmed findings:

1. Backup import merged rewards without removing pending reminders for them. Successful import now reconciles the dated plan, like completion and Watch event receipt.
2. Version-1 configuration decoders silently ignored temporary routine fields. New configuration snapshots use protocol version 2; both apps must update. Migrating a version-1 save clears the Watch's received-configuration flag so an equal-revision current snapshot repairs the cache.
3. Clearing that flag could retire the same phone authority during repair. Retirement now requires a different authority ID. Regression coverage accepts the equal-revision refresh, then a higher revision from the same phone, without retiring it.

The reviewer found no further blocking issues in grace, override boundaries, ledger rewards, finite reminder planning, or the UI clock harness. Native compilation and real UI execution remain required PR gates; physical notification delivery and paired-device acceptance remain separate.

## Companion and rotation review

A separate review of progression and balanced rotation found no blocking defects. The catalog keeps reward-rule version 1 and all existing thresholds, while adding permanent content. Selection is a phone-owned cosmetic preference, independent of temporarily incomplete Watch history. Milestone dates are not fabricated; the Journal shows the required break count.

Review identified an additive-field upgrade concern: an older Watch can discard a new optional affinity while caching the same configuration revision. Equal-revision snapshots from the sole active phone now refresh the complete cache. The reviewer implemented this small sync repair separately; root inspected its diff. Tests cover realistic missing-field cache repair, duplicate replay, stale rejection, and relaunch, and the complete package passed 66 tests across 13 suites. The author of this repair did not author the progression or rotation being reviewed.

The sender contract remains explicit: every actual phone configuration change, including migrations that change values, increments revision. No new background sync guarantee is implied. Native SDK, UI, and visual verification remain hosted gates.
