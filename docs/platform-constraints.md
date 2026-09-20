# Apple platform constraints and verification

## Notifications

The phone owns dated local notifications prepared from the local calendar up to seven days ahead. Requests keep their absolute dates until the next foreground reconciliation; open after timezone travel. There is no server or background hourly timer. Permission, Focus, notification summaries, device state and system routing control actual presentation. Watch mirroring is a user/system preference, not a second independently scheduled reminder source.

The product's 56-dated-request budget reserves eight requests for one-shot snoozes. It is an internal conservative capacity policy, not a guarantee of delivery. Re-snoozing replaces the same opportunity's request. The store must resolve a notification action against its embedded original opportunity ID and scheduled timestamp and recheck current opportunity expiry; tapping yesterday's notification must not complete or snooze today's snack. Both actions bring the app to the foreground so the user can see the result.

Notification center does not expose an atomic schedule transaction. Invalid schedules are rejected before mutation. Obsolete requests are removed before adding replacements to preserve the request budget. An OS add failure is thrown and may leave a partial schedule; show a retry action and reconcile the full persisted configuration. Schedule mutation, snooze, and completion cancellation must be serialized by the store across suspension points. Refreshing the horizon preserves a valid current snooze; suppression, completion, expiry or schedule changes that invalidate it remove it.

Finishing a snack removes that opportunity’s pending and delivered reminder and snooze. Pausing today removes today’s prepared alerts while retaining tomorrow’s dated requests. The finite horizon must be replenished by opening the app; no delayed background restoration is assumed. A watch completion can race an already-delivering phone reminder. Generic notification wording avoids making a false statement about pending activity or growth.

## Phone/watch transport

Phone configuration uses the latest-value `updateApplicationContext` channel. Either device can send immutable events, acknowledgment batches, or reconciliation requests using `transferUserInfo`, which queues without requiring immediate reachability. Byte-identical outstanding packets are not enqueued twice. The 48 KiB adapter limit leaves room for the transport dictionary; the store additionally bounds event batches and encoded packet size.

Only Sendable `Data` and strings extracted in delegate callbacks cross to the main actor. No SDK object or arbitrary `[String: Any]` dictionary is moved between executors. `@preconcurrency import` accommodates SDK annotations; no unchecked Sendable conformance or actor isolation assertion is introduced.

Operating-system transfer success is not an application acknowledgment. The sender must keep its local event outbox until the receiver persists and acknowledges those event IDs. Receiver validation errors must not clear the sender outbox. Activation, reachability and paired-watch changes request reconciliation. These callbacks cannot guarantee immediate background execution: reopening either app is a recovery path. Switching paired watches reactivates WCSession and requires store reconciliation.

## Required Apple-device acceptance checks

1. Build both targets with current Xcode and complete strict Swift concurrency checking. Linux parsing is not an Apple SDK build.
2. Allow, deny and revoke notification permission; verify accurate state and no automatic repeated permission requests.
3. Verify each weekday and end-exclusive active window, device time-zone changes, DST boundaries and schedule edits against the domain's slot policy.
4. Snooze twice, refresh/open the app, complete, and confirm no extra snooze remains. Pause today, close the app, and confirm tomorrow's already prepared reminder still arrives. Verify the displayed coverage horizon and foreground replenishment.
5. Test stale delivered actions, Focus, quiet hours, and the phone/watch routing settings on a physical pair.
6. Complete on an offline watch, terminate/reopen it, reconnect, and confirm one reward after duplicate/reordered delivery. Kill the receiver around persistence and acknowledgment boundaries.
7. Verify configuration changes propagate and offline watch changes never overwrite phone settings. Ensure malformed or newer protocol packets remain a visible sync error without resetting progress.

## Official references

- [UNCalendarNotificationTrigger](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger)
- [UNUserNotificationCenterDelegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
- [WCSession.updateApplicationContext](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:))
- [WCSession.transferUserInfo](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))

The official reference pages were reached during implementation. Their linked Markdown content was unavailable to the web reader; current SDK compilation and physical-device verification remain explicit acceptance gates.
