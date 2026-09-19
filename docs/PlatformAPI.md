# Apple adapter API

All adapter owners and callbacks are `@MainActor`; retain one adapter per app process.

## NotificationService (iOS only)

- `init(center: UNUserNotificationCenter = .current())` installs delegate and foreground Open / Snooze categories.
- `onAction: ((NotificationService.Action) -> Void)?`. Action has `kind: .open | .snooze`, `requestIdentifier: String`, `deliveredAt: Date`, `opportunityID: String?`. Resolve a recurring reminder's opportunity using its delivered date, and reject stale actions. No automatic completion.
- `authorizationStatus() async -> Authorization` (`notDetermined`, `denied`, `authorized`, `provisional`, `ephemeral`, `unknown`).
- `requestAuthorization() async throws -> Authorization`.
- `replaceSchedule(_ slots: [MosslingCore.RecurringSlot]) async throws`; serialize mutations in store. At most 56 unique weekly slots. Empty clears recurring requests and pending snoozes. Changes to the recurring slot set clear snoozes; refreshing the same slot set preserves them.
- `snooze(opportunityID: String, until: Date, expiresAt: Date) async throws`; stable one-shot ID; must be > now and < expiry. Caller decides duration. Replaces prior snooze, reserve cap of 8 one-shots.
- `markCompleted(opportunityID: String, deliveredReminderID: String?)` cancels pending snooze, delivered snooze, and delivered recurring reminder only. NEVER removes repeating request.
- `static reminderIdentifier(for: RecurringSlot) -> String`; use to remove delivered notification after completion.

## WatchConnectivityService (iOS and watchOS)

- `init()`, `activate()`.
- `state: State`: `unsupported`, `inactive`, `activating`, `ready`, `waitingForCompanion`, `failed(String)`; `isReachable: Bool`.
- `onStateChange: (() -> Void)?`, `onResync: (() -> Void)?`, `onError: ((String) -> Void)?`.
- `onReceive: ((Data, Channel) -> Void)?`; Channel `.snapshot` or `.events`.
- `sendSnapshot(_ data: Data) throws`: phone-only, latest-value application context, configuration only.
- `sendEvents(_ data: Data) throws`: either device, durable OS user-info transfer for root's encoded event/ack/inventory packet. Byte-identical outstanding batches aren't enqueued twice. Sender retains durable outbox until peer's application-level acknowledgment.
- `static maximumPayloadBytes = 48 * 1024`. Throw on oversized/unactivated/unavailable operations; transport never silently drops packets. OS delivery is asynchronous; callback errors do not imply receiver committed anything.

Root owns Codable envelopes, event validation, durable persistence, duplicate/reorder handling, retries, bounded batches and acknowledgment semantics. Platform code does not deserialize or reinterpret activity history.
