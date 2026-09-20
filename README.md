# Mossling

Short movement breaks grow a woodland companion. A native iPhone app with an Apple Watch companion, configurable activities and reminders, offline progress, and JSON backup export/import. Listed in App Store Connect as **Mosslinger**.

Progress stays on your devices. There are no accounts, backend, analytics or HealthKit integration. The phone owns configuration and reminders; the Watch records breaks offline and syncs when connected. Open the phone app regularly to replenish its reminder schedule. Watch sync is not an off-device backup.

## Setup

Install Xcode **27.0**, iOS/watchOS simulator runtimes, and [mise](https://mise.jdx.dev). The apps support iOS 18+ and watchOS 11+.

```sh
mise trust
mise install --locked
mise run generate
open Mossling.xcworkspace
```

Select the **Mossling** or **MosslingWatch** scheme and a compatible simulator.

```sh
mise run test:core       # Domain and Store tests
mise run build           # Both simulator apps
mise run test:ui          # Full UI suite on a fresh simulator
```

[Development](docs/Development.md) covers focused tests and diagnostics. [Release](docs/Release.md) covers signing, Cloud and device checks. [AGENTS.md](AGENTS.md) describes code boundaries and contribution rules.

The Tuist manifests own the project graph; generated Xcode snapshots are tracked for Cloud discovery. GitHub verifies changes and Xcode Cloud handles signed archives and distribution.

Bundled character and icon artwork was generated for this project. Expressions, foliage and animation are native SwiftUI layers.
