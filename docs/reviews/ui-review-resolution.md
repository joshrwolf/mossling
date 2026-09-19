# UI review resolution

Resolved 2026-09-19 against `ui-review.md`. This records source inspection and Swift syntax validation, not an Apple SDK build or a device render.

| Finding | Resolution |
| --- | --- |
| U1: notification navigation | The store publishes `navigationRequest`; the root selects Forest and closes onboarding. Forest closes its presentation, Activities closes editors, Rhythm closes schedule/export, and Journal closes import. Stale notifications remain rejected by the store. |
| U2: hidden save failures / unavailable storage | Phone and watch session sheets show `store.error` inline. Both roots show a blocking preserved-data explanation when `isReady == false`; the startup error cannot be dismissed into a default empty forest. |
| U3: inconsistent evolution | Watch passes its actual stage. Guardian adds permanent secondary fronds and an additional bud. The phone habitat renders fern, mushrooms, and pond according to earned unlocks. |
| U4: hidden snooze feedback | Forest now displays store status directly beneath the snack card. |
| U5: duplicated journal moments | Journal projects one deterministic representative per reward key (earliest completion, UUID tie-break). Underlying independent events remain untouched for synchronization. |

Additional integration fixes:

- Watch activity selection presents the session only after the picker sheet’s dismissal callback.
- Character motion centralizes scene-phase, Reduce Motion, and watch reduced-luminance policy. Blinks are cancellable tasks; repeating breathing resets on disappearance. Sleep and celebration have separate faces, a curled fern stem, and brief squash-and-stretch reactions.
- Watch session timeline reduces its refresh frequency while luminance is reduced. Home refresh loops mutate time only while active.
- App version comes from bundle metadata.
- Activity editing gives human-readable input errors without exposing generated activity IDs.
- Journal supports deliberate backup merge with a confirmation describing retained current settings and duplicate-safe progress. File reads use security-scoped access; oversized files are rejected. Rhythm exports the durable JSON document.

Validation performed: Swift 6.2 frontend parsing of all UI Swift source files succeeded after the changes. Core models and Store signatures were inspected for API alignment.

Required device checks remain: compile with Apple SDKs, render phone/watch at smallest and largest supported sizes, accessibility sizes/VoiceOver, live Reduce Motion toggles, permission states, notification routing from presented editors, picker-to-session transition, file picker cancellation, timer suspension, paired-device synchronization, and persistence failure presentation.
