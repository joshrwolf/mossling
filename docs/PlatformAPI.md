# Apple adapter API

All adapter owners and callbacks are `@MainActor`; retain one adapter per app process.

## NotificationService (iOS only)

- `init(center: UNUserNotificationCenter = .current())` installs delegate and foreground Open / Snooze categories.
- `onAction: ((NotificationService.Action) -> Void)?`. Actions carry original `opportunityID` and `scheduledAt`. Resolve against the current opportunity and reject stale/mismatched actions; never infer identity from delivery time or complete automatically.
- `authorizationStatus() async -> Authorization` and `requestAuthorization() async throws -> Authorization` expose explicit opt-in state.
- `replaceSchedule(_ plan: ReminderPlan) async throws`: serialized by Store; up to 56 dated upcoming reminders. Removes obsolete and legacy repeating requests, retains a valid current snooze, and prunes stale delivered notifications. Scheduling failures surface and do not claim complete coverage.
- `snooze(opportunity: Opportunity, until: Date) async throws`: must fire after now and before original expiry; stable ID replaces an earlier snooze; at most eight reserved snoozes.
- `markCompleted(opportunityID: String)` removes the pending/delivered dated reminder and snooze for that opportunity only.
- `static reminderIdentifier(for opportunityID: String) -> String`.

The dated horizon extends through the start of the seventh following local calendar day (up to seven days), refreshed on foreground, settings, completion, sync receipt, and backup import. The app shows successful coverage in Rhythm. Prepared requests use absolute dates; reopen after travel to reconcile the new local timezone. No background extension is assumed.

## WatchConnectivityService (iOS and watchOS)

- `init()`, `activate()`.
- `state: State`: `unsupported`, `inactive`, `activating`, `ready`, `waitingForCompanion`, `failed(String)`; `isReachable: Bool`.
- `onStateChange: (() -> Void)?`, `onResync: (() -> Void)?`, `onError: ((String) -> Void)?`.
- `onReceive: ((Data, Channel) -> Void)?`; Channel `.snapshot` or `.events`.
- `sendSnapshot(_ data: Data) throws`: phone-only, latest-value application context, configuration only.
- `sendEvents(_ data: Data) throws`: either device, durable OS user-info transfer for root's encoded event/ack/inventory packet. Byte-identical outstanding batches aren't enqueued twice. Sender retains durable outbox until peer's application-level acknowledgment.
- `static maximumPayloadBytes = 48 * 1024`. Throw on oversized/unactivated/unavailable operations; transport never silently drops packets. OS delivery is asynchronous; callback errors do not imply receiver committed anything.

Root owns Codable envelopes, event validation, durable persistence, duplicate/reorder handling, retries, bounded batches and acknowledgment semantics. Platform code does not deserialize or reinterpret activity history.
