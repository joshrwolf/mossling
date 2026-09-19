# Xcode Cloud setup and release contract

## Current boundary

The repository supplies the Cloud integration, not an already-connected Apple service. [PR #3](https://github.com/joshrwolf/mossling/pull/3) records the reviewed implementation and hosted checks. Apple Developer enrollment approval, the first Xcode Cloud connection, identifier registration, real managed signing and a first Apple-hosted build still need account-side acceptance. No paid plan, App Store Connect upload or TestFlight distribution has been activated by these commits.

Cloud owns signing, native Test/Archive actions, monotonically increasing build numbers and eventual delivery. Tuist owns the project graph. mise owns tools and shared preparation/check commands. There is no fastlane dependency, custom uploader or credential store.

## Product identity

`Config/Product.json` is the source for `com.joshrwolf.mossling` and marketing version `0.1.0`. Tuist derives `com.joshrwolf.mossling.watchkitapp` and `com.joshrwolf.mossling.uitests`; the Watch companion setting references the phone identity. These are proposed identifiers until Apple registration succeeds. If unavailable, change Product.json and regenerate before the first release; do not work around the check with a different Cloud product.

Cloud provides `CI_BUNDLE_ID`, `CI_TEAM_ID` and `CI_BUILD_NUMBER`. The adapter rejects a product mismatch, unresolved or malformed identity, and invalid build numbers. It generates ignored `Config/Cloud.xcconfig` with the team/build number only. The phone and Watch must agree, and the archive validator also checks the exact expected release identity, version and number.

Xcode Cloud supplies the build counter; do not reset it below a previously uploaded build. When migrating from another publisher, set Cloud's next build number above the previous maximum in App Store Connect. No build-number commits are created.

## One-time account connection

After membership approval, use a Mac with Xcode 26.2 and sign into the enrolled Apple account:

1. Clone the repository, install mise, run `mise trust`, `mise install --locked`, and `mise run generate`; open `Mossling.xcworkspace`.
2. Copy the local signing example to `Config/Local.xcconfig` and enter the enrolled team. Register/confirm the phone and Watch identifiers and the phone's App Store Connect product. Keep automatic signing. Review any proposed identifier change before registration.
3. In Xcode, select the **Mossling** scheme and configure Xcode Cloud for this product. Authorize access to only the `joshrwolf/mossling` repository using Apple's GitHub connection. No GitHub token or signing private key needs to be committed or pasted into chat.
4. Edit the suggested workflow to the validation settings below **before starting the first build**. Select the included 25 compute-hour plan; do not buy an upgrade. If Xcode 26.2 is unavailable in Cloud, update the verified toolchain across Tuist/GitHub/Cloud together rather than selecting an untested version silently.
5. Run the first validation build manually and inspect the acceptance evidence. Apple requires Xcode for initial product onboarding; subsequent workflow edits and manual builds are available in App Store Connect.

## Validation workflow: Mossling Verify

| Setting | Value |
| --- | --- |
| Repository / branch | `joshrwolf/mossling`, `main` for first manual acceptance |
| Project / scheme | Root `Mossling.xcworkspace`, shared `Mossling` scheme |
| Xcode | 26.2, matching the manifest and verified GitHub baseline |
| Starts initially | Manual; remove suggested automatic branch triggers during onboarding |
| Test action | iOS, scheme settings, one available iPhone simulator, Required To Pass |
| Archive action | iOS, Release scheme configuration, Deployment Preparation **None** |
| Distribution post-actions | None |
| Custom environment | None required; Apple supplies identity, team and build variables |
| Clean builds | Off initially; enable only to diagnose a cache problem |

Apple explicitly defines Archive preparation **None** as ineligible for TestFlight and App Store distribution. Use this setting for validation. Do not substitute “TestFlight and App Store” and assume omitting a post-action prevents upload. Test builds the app already, so an extra Build action is unnecessary. The phone target builds its embedded Watch dependency.

The post-clone hook runs domain tests and project drift verification; Cloud runs the UI tests and native archive. The post-xcodebuild hook validates the real archive. It must receive Apple's phase resources via the tracked `ci_scripts` symlinks; copying only the two shell files is insufficient.

## Acceptance and CI handoff

Before changing CI ownership, verify:

- The same committed project generates without drift with Cloud settings present.
- The real Cloud post-clone bootstrap and native Test action pass; all three UI tests run rather than being skipped.
- Archive preparation None succeeds, and the post-action verifies the actual phone/Watch identifiers, marketing version and Cloud build number.
- A deliberately failing test/check fails the workflow; no distribution post-action exists.

Then enable Cloud verification for pull requests targeting `main`, with automatic cancellation and one simulator destination. Observe a PR run and configure the actual Cloud status as a required check. Only then set the GitHub repository variable `MOSSLING_XCODE_CLOUD_ACTIVE=true` to suppress duplicate automatic Mac jobs. Keep GitHub Linux checks required. Manual GitHub verification still runs the full Apple gate when troubleshooting.

Leaving the variable unset preserves the current Apple gate during onboarding. It is a migration switch, not proof Cloud is configured. If Cloud is disconnected, restore the GitHub gate and required-check policy.

## Later delivery workflow: Mossling TestFlight

Create this only when the first distribution is authorized. Use manual starts on a reviewed `main` commit, the same required Test action, and Archive preparation **TestFlight (Internal Testing Only)**. Add an internal TestFlight distribution post-action for the chosen tester group after all required actions pass. Confirm the group's members and App Store Connect roles before sending invitations; this repository does not invite anyone.

Managed signing must cover the phone and embedded Watch. Keep the archive checks enabled. The first installation requires paired-device acceptance for reminders, offline completions/sync and timer behavior; simulator tests cannot establish those behaviors. External testing or App Store submission is a later decision.

## Cost controls

Stay on Apple's included 25 compute-hour/month allowance. Start releases manually, use one simulator, retain auto-cancel when enabling PR triggers, and avoid duplicate Mac jobs after acceptance. Inspect actual Cloud compute usage before increasing test coverage. No cost cap or billing setting was changed here. For the existing private GitHub repository, confirm an Actions budget that stops paid usage beyond the included allowance; a repository workflow cannot impose an account billing cap.

## Evidence and limits

GitHub exercises the actual post-clone adapter with a clearly fictitious team and build 42, runs unsigned native builds/archive/tests, and invokes the post-action from a dereferenced copy of `ci_scripts` against the resulting archive. This proves the adapter and configuration precedence in hosted macOS, once that PR gate passes. It does not simulate Apple's authentication, product discovery, signing service or upload processing. [Validation](Validation.md) and the PR checks record actual results.

## Primary references

- [Apple first workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow)
- [Workflow actions and deployment preparation](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)
- [Cloud environment](https://developer.apple.com/documentation/xcode/environment-variable-reference)
- [Cloud numbering](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)
- [TestFlight distribution](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight)
- [Included compute allowance](https://developer.apple.com/xcode-cloud/)
