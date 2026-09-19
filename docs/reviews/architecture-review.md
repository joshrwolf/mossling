# Independent architecture review

Reviewed: 2026-09-19, before implementation. Scope: initial architecture plus revised Swift 6 / native SwiftUI / local JSON persistence proposal.

Verdict: sound foundation for a household MVP, provided the invariants below are implemented. Prefer a small working native app with a rigorous domain over speculative frameworks, accounts, or automatic exercise verification.

## Required decisions and invariants

### 1. Recurring notifications cannot skip one occurrence

A repeating calendar request represents all future occurrences. Removing it after completion also removes next week's reminder. Do not cancel repeating requests on completion. Remove delivered notifications for the current slot and pending one-shot snoozes only. Configure reminders with generic text because their content cannot consult live completion state at delivery.

Define a snack as available from its scheduled time until the next scheduled snack or the end of active hours. Do not expose completion of a future opportunity: this avoids the common case where an early completion is followed by an unavoidable reminder. A watch completion may still race a phone notification; this is an accepted system limitation, not a correctness failure.

Treat active windows as start-inclusive/end-exclusive: weekdays 09:00–17:00 means 09:00 through 16:00, eight opportunities. Display that convention in settings. Snooze must remain before both the next slot and quiet hours. Re-snoozing replaces one stable per-opportunity request instead of consuming unbounded notification slots.

### 2. Schedule identity is not revision identity

Store an immutable scheduled local date, local time, time-zone identifier and absolute scheduled instant on sessions/completions. Reconciliation must never recalculate old reward keys using today's schedule, device time zone, or receipt time. Configuration revision is useful provenance but must not allow duplicate growth after an edit.

If rewards are capped at one per local date/hour, restrict initial schedule intervals to 60 minutes or longer. Otherwise legitimate 30-minute snacks receive inconsistent rewards. This cap is an intentional product rule, not robust anti-cheat; avoid engineering a fraud system for this personal app.

Overnight windows can be deferred. Reject unsupported windows with a useful validation error. Preserve an in-progress session across configuration edits; new opportunities use the new configuration. A stale offline watch completion remains valid if it references a previously cached schedule/session snapshot.

### 3. DST and travel require explicit, testable policy

Use Gregorian calendar calculations with an explicit zone input. A nonexistent local time is skipped; a repeated local time produces one opportunity. Do not assume adding 3,600 seconds gives the next configured wall-clock slot. A daily interval means increments in configured wall-clock minutes inside the window, not globally elapsed time.

Following local time is reasonable. A completion's original slot identity is immutable, and switching time zones must not reinterpret old events. The same local date/hour reward key deliberately suppresses a repeated hour during travel or fall-back. Include a stale-zone watch/phone test and document that reminders follow each phone's local system clock; an offline watch temporarily uses its last known or own local clock consistently.

### 4. Persist before celebrating or acknowledging

All state transitions must be serialized through one store owner. Calculate the next state, atomically write the complete versioned snapshot, then publish it to the UI. Never mutate the in-memory source of truth and report success before a write that can fail. Filesystem failure must leave the previous valid state usable and show a retryable error.

Watch completion and outbox insertion belong in the same snapshot transaction. Phone merge and the durable acknowledgment state belong in the same transaction. A transport callback is not evidence the receiving application saved an event. Send application-level acknowledgments only after the receiver's durable commit. Repeated/reordered deliveries and acknowledgments must be harmless.

Completion UUIDs deduplicate exact transport copies. A separate stable reward key deduplicates two independently completed sessions on two devices. Derive growth from unique reward keys; never merge absolute XP counters by addition. If duplicate events disagree, select a deterministic representative for display so arrival order does not change history.

### 5. Keep sync payloads bounded and recoverable

Application context is a latest-value channel suitable for phone-owned configuration; it must not be the sole event transport. Durable outboxes plus background transfer and application-level acknowledgment are the correctness path. Immediate messaging is an optional latency improvement.

Do not send an ever-growing full ledger in every application context. Use bounded event batches with an explicit encoded-size budget, or use a file transfer for larger reconciliation snapshots. Acknowledge only IDs actually committed. Unknown protocol versions must fail visibly and retain the watch outbox. Receiving an older configuration must never roll back newer state.

For this small app, an append-only completion ledger with atomic JSON snapshots is a reasonable simplification. Do not add compaction before a clear retention/reconciliation policy exists. Include export of the versioned document so progress is not trapped on one installation. A corrupt or newer-schema document must not be silently overwritten with an empty forest.

### 6. Timers are persisted state, not a running process

The countdown view is a projection of persisted start/deadline/pause state. Suspension must not reset it, and reaching zero never grants a reward automatically. Pause duration and remaining time must be restored after process death. Manual completion is a deliberate user confirmation. Do not use a HealthKit workout solely to keep a short snack timer alive.

## Pragmatic scope

- Phone: forest home, available snack, exercise selection and custom activity editor, rep/timer session, schedule settings, permission state, history, export.
- Watch: cached configuration, current snack, rep/timer session, durable offline completion, clear syncing/unavailable state.
- Creature: one species, three visual stages and permanent habitat milestones; idle/rest/celebration with Reduce Motion support.
- Notifications: phone-owned repeats plus one-shot snooze; no promise of exact interruption under Focus or denied permission.
- Defer independent watch notifications, pause-today, Screen Time blocking, HealthKit, cloud sync, multiple species and automatic rep recognition.

Use a placeholder development bundle ID and document changing it before account setup. No credentials, team ID, deployment or paid developer setup is required to produce the source and simulator project.

## Required verification before calling the MVP usable

Domain tests: end-exclusive window, disabled day, interval validation, next-day rollover, DST gap/repeat, revised schedule preserving completed growth, duplicate event/reward handling, delayed offline completion, reversed delivery order, paused/relaunched timer.

Persistence/sync tests: failing writer does not publish success; duplicate merge is idempotent; receiver crash before/after commit cannot lose acknowledged events; older configuration cannot roll back current; malformed/newer-schema file is preserved; bounded batch selection does not strand events.

Apple platform gates: compile and test both targets with current Xcode, then paired-device notification routing, snooze, app suspension, offline watch completion and reconnection. Linux domain tests do not establish Apple target build success. Record unavailable gates plainly rather than marking them passed.

## Platform references

- [UNCalendarNotificationTrigger](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger)
- [WatchConnectivity transferUserInfo](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))
- [WatchConnectivity updateApplicationContext](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:))

The above are API reference locations. Their JavaScript pages were reachable during review, but the browsing tool could not retrieve their linked Markdown content; validate exact SDK signatures during the Apple build gate. The architecture recommendations are reviewer analysis.
