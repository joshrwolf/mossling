# Tuist lifecycle and release preparation review

Reviewed 19 September 2026 by an independent agent.

The migration replaces XcodeGen, committed generated Xcode projects and shell build entry points with typed Tuist manifests and a mise task graph. No signed release or upload operation is introduced.

## Findings and resolution

- The notification permission test initially asserted an unqueried placeholder status and checked app alerts instead of system alerts. The Store now starts at `Checking…`; the test waits for the real permission result and checks SpringBoard as well.
- Isolating only app documents/preferences would leave real notification and WatchConnectivity adapters affecting an existing simulator. The runner now creates and deletes its own simulator for every invocation.
- Archive validation now also checks that the Watch identifier extends the phone identifier, alongside matching versions, companion relationship, platform, resources and executable payload.

## Review evidence

The reviewer inspected the actual UI hooks, test assertions, Tuist manifests, mise tasks, CI and Swift tools. Hooks are compiled only for Debug simulator builds and delete only isolated test state. UI tests drive normal forms and verify saved state after process relaunch. The runner preserves test failure status, exports result evidence and cleans up its own device. CI runs the task graph sequentially; generation is a shared dependency.

Both tooling helpers independently typechecked under Swift 6.2. The project author compiled the exact Tuist 4.208.0 ProjectDescription sources and typechecked both manifests with warnings-as-errors. Synthetic archive cases exercised success and malformed bundle rejection. Actual Tuist generation, Apple builds, archive packaging and simulator execution are separate hosted CI gates; see the PR and Validation report for their results.
