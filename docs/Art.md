# Mossling art and animation

Selected direction: original round woodland spirit A, a little more cartoony than the first concept, with soft Poring-like squish. Warm cream face, moss/sage body, recognizably curled fern. Cozy rest and enthusiastic celebration. No imitation of an existing game character.

## Bundled assets

- `MossBody.imageset/body.png`: generated transparent1254×1254 RGBA body. No baked eyes, mouth, or fern. This keeps expressions and the crest independent.
- `AppIcon.appiconset`: generated opaque icon master, resampled deterministically to phone/watch asset sizes. It is a complete portrait rather than the layered animation body.
- SwiftUI face, fern, shadow, mushrooms, pond, and decorative foliage: native code layers. They remain editable without regenerating the body.

Body prompt intent: isolate a front-facing round moss blob, warm cream blank face, tiny integrated feet, no fern/face/shadow/background; clean transparent edges and restrained soft painterly texture.

Icon prompt intent: same body identity with simple dark oval eyes, small smile and curled fern, readable small-device silhouette on opaque warm ivory, no text, no baked rounded outer corners.

Both assets were generated with the built-in image-generation capability during this project. Source image output was inspected; body's alpha spans0–255. The generated artwork is included in the source distribution.

## Motion

SwiftUI composes independently animated body/face/crest/shadow. Idle has slight breath/sway and occasional blink; celebration adds a happy expression, squash/stretch and hop; rest closes the eyes. Three stages alter the crest/sprouts. Forest unlocks are actual scene elements, not just labels.

Motion responds to view visibility and scene activity, Reduce Motion, and watch reduced-luminance state. The character does not run continually on the watch face or in background. Animation is presentation; rewards are committed before celebration.

## Review limits

The assets and source were inspected, and Swift syntax checked. Animation timing, alignment, accessibility layouts and energy behavior must still be viewed in Apple simulators/hardware. Do not treat a concept sheet as a screenshot of the running app. No native screenshots are included because this workspace could not run Apple SDKs.
