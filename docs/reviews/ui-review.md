# Independent UI implementation review

Reviewed: 2026-09-19. Reviewer authored the platform adapters, not the UI. Scope: `Apps/iOS`, `Apps/Watch`, `Apps/Shared/UI`, read-only inspection of the Store contract and core reward behavior.

Final source-review verdict: U1–U5 are resolved in the implementation. No remaining concrete source-level blocker was found in this scoped review. Apple SDK compilation and rendered/physical-device acceptance remain required; this review does not establish runtime acceptance.

## Independent resolution verification

The reviewer re-read the actual modified source after the UI author's fixes, rather than relying on the author's resolution notes.

| Finding | Verified source change | Status |
| --- | --- | --- |
| U1 | Store increments `navigationRequest` only after stale-opportunity validation; root selects Forest; activity/schedule/export/import/playground/session presentation responds by dismissing unrelated UI. | Resolved in source; native transition test required |
| U2 | Both session sheets render `store.error` inline; iPhone and watch replace the normal forest with an unavailable-data screen when `isReady` is false. | Resolved in source |
| U3 | Watch passes the actual progress stage; shared `FernCrest` renders extra guardian fronds for `stage > 1`. | Resolved in source |
| U4 | Forest displays Store status immediately below the opportunity card, including snooze confirmation. | Resolved in source |
| U5 | Journal projects one deterministic representative per reward key, ordering by completion time then event UUID, without modifying the retained ledger. | Resolved in source |

Additional observed fixes: motion permission is centralized in the character and includes scene phase, Reduce Motion and watch reduced luminance; disappear cancels animation state; watch session timeline cadence reduces to one minute when dimmed; refresh projections only run in active scene phase. The watch activity picker retains its deferred session presentation. No expanded testing was performed during this final source pass.

The findings below are retained as the historical review record.

## Findings requiring follow-up

### U1 — Notification Open does not navigate to the available snack (high)

`MosslingStore.handleNotification` handles snooze but leaves Open as a comment. `MosslingRootView.TabView` has no selection binding or notification route. Reproduction by inspection: leave the app on Rhythm/Journal or an editor, tap the notification's “Start snack” action, and the existing UI remains selected. Bringing the process foreground is not the promised navigation behavior.

Publish a navigation intent after validating the notification's opportunity. Root should select Forest and close unrelated sheets in a controlled way. Retain stale-action validation; never silently start or complete an expired snack.

### U2 — Session save failures need feedback inside the presented sheet (high)

Both session views call pause/resume/complete, which can fail durable persistence and set `store.error`. Their error presentation is attached to the underlying root view; neither session sheet displays the error. Root alert presentation while another controller is presented is an unsafe place to rely on for the only save-failure feedback and must be verified on Apple UI.

Add inline error state or an alert in each session sheet, keep the existing session visible, and allow retry. Also guard or disable interaction when `store.isReady` is false so a dismissed startup error does not leave what looks like an empty working forest.

### U3 — Creature progression is not represented consistently (medium)

Watch home creates `MosslingCharacter` without passing progress stage, so it always renders stage zero. The phone passes stage numbers correctly, but `FernCrest` and `ForestHabitat` only distinguish `stage > 0`; sprout and guardian share the same appearance. Pass the stage on watch and give guardian a small distinct permanent visual feature. This needs no additional artwork generation.

### U4 — Snooze success feedback is hidden from the action's screen (medium)

Store writes “A gentle reminder in 10 minutes” to `status`; Forest does not display `status`, while Rhythm and watch do. A successful home-screen snooze appears to do nothing. Show local confirmation on Forest, ideally without making sync status and user-action confirmation overwrite one another.

### U5 — Journal mixes unique reward counts with duplicate reward-key rows (medium)

The ledger deliberately preserves independent event IDs while awarding one reward per opportunity hour. Journal displays every event, but its header counts unique rewarded breaks. After offline phone/watch completion of the same slot, one moment can produce two visually identical rows. Select a deterministic representative per reward key for this view, or explicitly distinguish a second nonrewarded activity record. Do not discard the underlying events needed for sync.

## Findings fixed during review

- Watch's activity picker originally dismissed itself and presented the session sheet in the same event. Latest source defers session presentation to the picker sheet's `onDismiss`.
- Character now reacts to mood changes when choosing animation timing and resets its repeat animation without animation before restarting.
- Watch home now checks `isLuminanceReduced` as well as scene phase before animating the character.

## Lower-priority checks

- Session countdowns correctly project persisted elapsed time and require explicit confirmation after time has elapsed. Pause/relaunch does not depend on a running app task. Validate paused/expired state after actual suspension and wrist lowering.
- Periodic session timelines and 20-second refresh tasks rely on system throttling outside foreground. Prefer phase-aware refresh and a lower-frequency/static watch timer presentation when luminance is reduced; do not keep exercise runtime alive merely for this UI.
- Phone snack/onboarding/playground character calls use the default `animate: true`, unlike the home view. Centralizing scene phase handling in `MosslingCharacter` would prevent future callers forgetting the power policy.
- Shared animation honors Reduce Motion; validate toggling it while an existing repeat animation is running. The watch uses light green text against the system dark background, without the phone's forced light scheme.
- Rhythm's displayed version is hardcoded `1.0`, while project marketing version is `0.1.0`; read the bundle value to avoid misleading build identification.
- Test the longest custom titles, VoiceOver, the largest accessibility text size, the smallest supported watch, picker sheets, file export cancellation, and nested-sheet error presentation with Xcode/device rendering.

## Verification evidence and limits

Swift 6.2 `swiftc -frontend -parse` passed all ten UI source files. This checks syntax only: SwiftUI, WatchKit, UIKit, SDK availability, strict concurrency annotations and generic overload resolution require an actual Apple SDK build. No simulator, Xcode or paired physical watch was available for this review.

Reviewed official API reference locations: [isLuminanceReduced](https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced), [periodic timelines](https://developer.apple.com/documentation/swiftui/timelineschedule/periodic(from:by:)), [fileExporter](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)). Their JavaScript pages were reachable but full reference content was not available to the web reader.
