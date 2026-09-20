# Xcode Cloud setup and release contract

## Current boundary

The repository supplies the Cloud integration, not an already-connected Apple service. [PR #3](https://github.com/joshrwolf/mossling/pull/3) records the reviewed implementation and hosted checks. The user is completing Apple account setup. Membership status, the first Xcode Cloud connection, identifier registration, managed signing and a first Apple-hosted build still need account-side acceptance. No paid plan, App Store Connect upload or TestFlight distribution has been activated by these commits.

Cloud owns signing, native Test/Archive actions, monotonically increasing build numbers and eventual delivery. Tuist owns the project graph. mise owns tools and shared preparation/check commands. There is no fastlane dependency, custom uploader or credential store.

## Product identity

`Config/Product.json` is the source for `com.joshrwolf.mossling` and marketing version `0.1.0`. Tuist derives `com.joshrwolf.mossling.watchkitapp` and `com.joshrwolf.mossling.uitests`; the Watch companion setting references the phone identity. These are proposed identifiers until Apple registration succeeds. If unavailable, change Product.json and regenerate before the first release; do not work around the check with a different Cloud product.

Cloud provides `CI_BUNDLE_ID`, `CI_TEAM_ID` and `CI_BUILD_NUMBER`. The adapter rejects a product mismatch, unresolved or malformed identity, and invalid build numbers. It generates ignored `Config/Cloud.xcconfig` with the team/build number only. The phone and Watch must agree, and the archive validator also checks the exact expected release identity, version and number.

Xcode Cloud supplies the build counter; do not reset it below a previously uploaded build. When migrating from another publisher, set Cloud's next build number above the previous maximum in App Store Connect. No build-number commits are created.

## One-time account connection

After membership approval, use a Mac with Xcode 26.2 and sign into the enrolled Apple account:

1. Clone the repository and open the committed `Mossling.xcworkspace`. The reviewed generated project is already present; local mise/Tuist installation is not required just to onboard Cloud. Developers changing the project graph should use the generation commands in [Tooling](Tooling.md).
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
- The real Cloud post-clone bootstrap and native Test action pass; all seven UI tests run rather than being skipped.
- Archive preparation None succeeds, and the post-action verifies the actual phone/Watch identifiers, marketing version and Cloud build number.
- A deliberately failing test/check fails the workflow; no distribution post-action exists.

Then enable Cloud verification for pull requests targeting `main`, with automatic cancellation and one simulator destination. Observe a PR run and configure the actual Cloud status as a required check. Only then set the GitHub repository variable `MOSSLING_XCODE_CLOUD_ACTIVE=true` to suppress duplicate automatic Mac jobs. Keep GitHub Linux checks required. Manual GitHub verification still runs the full Apple gate when troubleshooting.

Leaving the variable unset preserves the current Apple gate during onboarding. It is a migration switch, not proof Cloud is configured. If Cloud is disconnected, restore the GitHub gate and required-check policy.

## Delivery workflow: Mossling TestFlight

The user has now authorized preparing the first TestFlight release. Apple account setup remains user-operated; no build has yet been uploaded or distributed. Use manual starts on a reviewed `main` commit, the same required Test action, and Archive preparation **TestFlight (Internal Testing Only)**. Add an internal TestFlight distribution post-action for the chosen tester group after all required actions pass. Confirm the group's members and App Store Connect roles before sending invitations; this repository does not invite anyone.

Managed signing must cover the phone and embedded Watch. Keep the archive checks enabled. The first installation requires paired-device acceptance for reminders, offline completions/sync and timer behavior; simulator tests cannot establish those behaviors. External testing or App Store submission is a later decision.

## First release handoff: 0.1.0

Use the reviewed `main` commit containing the daily loop, lasting forest and balanced rotation. Record that full commit SHA and the Cloud-generated build number in the release record; a version string alone does not identify the build.

### Account setup inputs

The account holder signs in directly at [Apple Developer](https://developer.apple.com/account/) and [App Store Connect](https://appstoreconnect.apple.com/). Needed setup information is membership status, access to a Mac and its Xcode version, and whether a Mossling app record already exists. Passwords, verification codes and signing private keys stay with the account holder. The Team ID is entered into the ignored local configuration for onboarding; Cloud supplies it automatically thereafter.

Register these two explicit App IDs, with default capabilities unless a current app requirement calls for more:

- iPhone: `com.joshrwolf.mossling`
- Embedded Watch app: `com.joshrwolf.mossling.watchkitapp`

The Watch app requires the iPhone app for initial setup and is declared dependent; it continues to support valid offline completions after receiving its first phone configuration. There is no separate Watch extension target. Do not create a second App Store Connect app record for the companion. Create the phone product using platform **iOS**, primary language **English (U.S.)**, bundle ID `com.joshrwolf.mossling` and SKU `mossling-ios`. Try the name **Mossling**; if unavailable, agree on a store-facing alternative before registration rather than changing the code's bundle identity. Xcode's onboarding can create this app record if it does not already exist.

After the first Cloud setup in Xcode, manage workflows and builds in App Store Connect. Grant Apple's GitHub app access only to this repository. Keep the included Cloud plan and manual starts while validating the first delivery.

### TestFlight metadata draft

**Beta description**

Mossling helps you make room for small movement breaks. Choose your activities and daily rhythm, take a short break, and grow a woodland companion and its forest. Your progress stays with you when you skip a break or rest for the day. Includes an Apple Watch companion.

**What to Test**

Set your usual hours and pick a few movement snacks. Complete a break and confirm its growth and Journal entry remain after reopening the app. Try skipping one break, pausing for the day and resuming. After three completed breaks, choose Sunlit or Moonlit and check that your choice persists. If you use an Apple Watch, try completing a break while disconnected and reconnecting: it should appear once on both devices. Please report unexpected reminders, lost progress, duplicate rewards or a timer that behaves incorrectly after locking the screen.

The account holder supplies the feedback email in App Store Connect. No tester invitations are sent by the repository. Internal testers need appropriate App Store Connect access; external testers use a separate distribution path with Apple's beta review. Confirm which path applies before inviting the first tester.

### Device acceptance after the first internal install

These remain **pending** until checked on the actual signed build. Record the build number, device OS versions and result next to each observation.

| Scenario | Expected result |
| --- | --- |
| First phone launch | Correct icon, welcome and usable activity/rhythm editors |
| Notification permission and locked phone | A prepared reminder arrives within the active rhythm; its action opens the intended opportunity |
| Skip, pause and resume | Skip suppresses that opportunity; pause suppresses today; resume restores remaining opportunities; earned growth stays intact |
| Reminder coverage | Rhythm shows the prepared horizon; reopening replenishes dated reminders; travel followed by reopening replans local times |
| Timed snack and screen lock | Remaining time reflects elapsed time; a session cannot earn after its valid completion deadline |
| Phone/Watch completion overlap | The same hour earns growth only once after synchronization |
| Disconnected Watch | A valid completion survives relaunch and reconciles on reconnect |
| Phone customization sync | Schedule, activities, day overrides and earned affinity reach the Watch after reconnecting |
| Upgrade from an earlier test build | Existing history and progress persist; the upgraded pair exchanges configuration successfully |

If a build fails these checks, stop distributing that build, retain its logs and ship a fix with a higher Cloud build number. Do not reset build numbering or change the bundle identifier to bypass an upload error. Simulator success is evidence for the automated flows, not a substitute for notification delivery or paired-device checks.

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
