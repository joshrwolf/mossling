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

## First hosted UI run follow-up

The actual iOS accessibility hierarchy combines the notification label and value. The test was corrected to query that visible combined label. The recorded Monday tap landed in the switch row center and the pre-save screenshot still showed it enabled; the test now taps the trailing switch control and asserts its off state immediately and after cadence editing before checking persistence across relaunch. Production behavior was unchanged by these two fixes. Hosted Tuist generation, native builds and unsigned Release archive validation passed before this follow-up.

## Xcode Cloud adversarial review

Two independent reviewers examined the current Cloud integration and deliberately challenged build/configuration ownership, phase isolation, failure propagation and release identity. Both independently ran the hook tests (27 rejection/failure cases) and seven archive tests. Neither implemented the reviewed changes.

Confirmed findings and resolutions:

1. Disabling the GitHub Apple job at handoff would remove the only generated-project drift gate. Cloud preparation now runs `project:check` itself.
2. The `Config/*.xcconfig` additional-file glob would incorporate local/generated signing files into the tracked graph. The manifest now lists only the tracked config inputs explicitly.
3. Root inspection of the real generated snapshot found absolute runner/tool paths in Tuist's convenience Generate Project scheme. That optional scheme is disabled with `includeGenerateScheme: false`; normal shared app schemes remain.

The reviewers independently confirmed Apple's documented support for phase-resource symbolic links. Generated settings contain no team/build-number overrides above the base xcconfig, identifiers are concrete, Watch embedding is correct, and the phone scheme enables UI tests. The account setup recipe uses Archive Deployment Preparation None and no distribution post-action. The proposed delivery workflow remains a later activation.

The final approval gate is the hosted macOS run linked from [PR #3](https://github.com/joshrwolf/mossling/pull/3): actual pinned Cloud bootstrap, unchanged regenerated snapshot despite Cloud config, all native tests/builds, and successful validation of the real unsigned archive against the configured ID/version and fixture build 42 from detached phase resources. PR results are authoritative; local tests alone are not presented as this gate passing. Actual Apple onboarding, managed signing and distribution require separate account-side acceptance.

Hosted integration follow-up: canonical generation passes with the committed `.tuist-generated` marker. The real bootstrap exposed mise's single-task argument semantics: passing two task names forwarded the second as a Swift test argument. The adapter now invokes one `cloud:prepare` task with explicit graph dependencies, verified with mise's dry run before hosted execution. This was an adapter invocation defect, not an application test failure.
