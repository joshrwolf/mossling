# MosslingCore public API

Pure Foundation, Swift tools 6.0. All value models are Codable, Equatable, Sendable; identifiable models declare Identifiable.

- `Weekday`: use Calendar integers 1 Sunday ... 7 Saturday in `Set<Int>`.
- `ScheduleConfiguration(enabled: Bool = true, weekdays: Set<Int> = [2,3,4,5,6], startMinute: Int = 540, endMinute: Int = 1020, intervalMinutes: Int = 60)`; `.standard`; `validate() throws`; `recurringSlots: [RecurringSlot]` (empty if disabled). End is exclusive. End may equal 1440. Start must be less than end, interval one of 60/90/120, maximum 56 weekly notification slots. Enabled schedule needs >=1 weekday. Invalid schedules throw; engine never silently repairs them.
- `RecurringSlot(weekday: Int, minuteOfDay: Int)`, `id: String` is `w{weekday}-m{minuteOfDay}`.
- `ActivityTargetKind`: `.duration`, `.repetitions`; duration target values are seconds.
- `ActivityDefinition(id: String, title: String, instructions: String, targetKind: ActivityTargetKind, targetValue: Int, isEnabled: Bool = true)`; `.starters: [ActivityDefinition]`; `validate() throws`.
- `AppConfiguration(revision: Int = 0, companionName: String = "Moss", schedule: ScheduleConfiguration = .standard, activities: [ActivityDefinition] = .starters)`; `.standard`; `validate() throws`.
- `Opportunity`: `id: String`, `rewardKey: String`, `scheduledAt: Date`, `expiresAt: Date`, `activity: ActivityDefinition`, `dayKey: String`, `minuteOfDay: Int`; full public initializer. Calendar timezone determines local identity; id is local day + scheduled minute, reward key is local day + scheduled hour. Immutable activity snapshot. `isActive(at: Date) -> Bool`.
- `ScheduleEngine(configuration: AppConfiguration)`; `opportunities(on: Date, calendar: Calendar) throws -> [Opportunity]`, `current(at: Date, calendar: Calendar) throws -> Opportunity?`, `next(after: Date, calendar: Calendar) throws -> Opportunity?`. `current` only active window; `next` is strictly after date, up to next 8 local days. Calendar must carry user's timezone; calendar is normalized to Gregorian while retaining timezone and locale. Strict nonexistent DST slots skipped, repeated slots appear once at first occurrence. Deterministic assignment uses sorted enabled activity IDs, a stable FNV-1a daily starting offset, and the actual slot index. Within a day, every enabled activity appears before the cycle repeats. Manual substitutions, configuration edits, and day boundaries may repeat an activity. No completion-history dependency is introduced.
- `SnackSession(id: UUID = UUID(), opportunity: Opportunity, activity: ActivityDefinition, accumulatedSeconds: TimeInterval = 0, runningSince: Date? = nil, completed: Bool = false)`; `elapsed(at: Date) -> TimeInterval`; mutating `pause(at:)`, `resume(at:)`, `markCompleted(at:)`. Paused timers survive persistence; repeating resume/pause does not double count. Timers never auto-complete. Session does not enforce opportunity validity; store uses completion validation below.
- `CompletionEvent(eventID: UUID = UUID(), sessionID: UUID, opportunityID: String, rewardKey: String, scheduledAt: Date, completedAt: Date, activity: ActivityDefinition, sourceDeviceID: UUID)`; `id` aliases eventID.
- `CompletionValidator.validate(session: SnackSession, completedAt: Date) throws`: rejects already-completed, future or expired opportunities, under-target duration. Repetition completion is manual confirmation. A validated persisted start permits completion before `completionDeadline` (original expiry + five minutes); legacy sessions without a start remain bounded by original expiry. New starts still require the original active window.
- `CompletionLedger(events: [CompletionEvent] = [])`: private-set `events`; mutating `merge(_ incoming: [CompletionEvent])`; computed `progress: CompanionProgress`; `containsReward(key: String) -> Bool`. UUID event dedup + unique reward key reward dedup. Conflicting same eventID deterministically reduced to one canonical event; ordering deterministic. Reject structurally invalid event timestamps/activity/reward key to keep corrupt sync from affecting rewards.
- `CompanionStage`: `.seedling`, `.sprout`, `.guardian`, `.groveKeeper`, with `title`, `minimumGrowth`, and `visualLevel`.
- `ForestUnlock`: `.fern`, `.mushrooms`, `.pond`, `.wildflowers`, `.steppingStones`, `.lanterns`, with title, threshold, and symbol metadata.
- `CompanionProgress`: `completedSnackCount: Int`, `growth: Int`, `stage: CompanionStage`, `forestUnlocks: [ForestUnlock]`, `rewardRuleVersion: Int`, `nextStageGrowth: Int?`, `stageProgress: Double`. 10 growth per unique scheduled-hour reward; stages at 0/30/150/1200 growth; forest unlocks at 10/50/100/300/600/900 growth. Reward rule version 1 stays unchanged; progression catalog version 2 adds content.

App document, atomic persistence contracts, migration, and device sync envelopes also live in the core package. Apple platform adapters live in Apps/Shared/Platform. Source of truth for rewards is completion ledger, never remote XP totals.

## Temporary routine and session APIs

`AppConfiguration.dailyOverride` optionally stores pause and skipped reward keys through a captured local-midnight deadline. `pauseForToday(at:calendar:)` and `skip(_:at:calendar:)` throw; `resumeToday(at:)` preserves skips. Store increments configuration revision with each persisted mutation. `ScheduleEngine.opportunities` retains the raw schedule and original boundaries; `current` and `next` apply suppression.

`SnackSession.start(opportunity:activity:at:)` validates start time and target fit. `startedAt` is immutable, optional for legacy decoding. `completionDeadline` centralizes expiry; pausing the timer cannot extend it.

`ReminderPlan(configuration:at:calendar:completedRewardKeys:)` provides bounded future `opportunities`, unsuppressed/uncompleted `currentOpportunity` for snooze retention, and `coverageEnd`. All dates are supplied explicitly for deterministic tests.

## Companion content

`ProgressionCatalog` owns reward amount, reward-rule version, content version, affinity threshold, and sorted stable-ID milestones. `CompanionProgress` derives `nextMilestone`, `unlockedMilestones`, and `canChooseAffinity` from unique earned reward keys. `CompanionAffinity.sunlit/moonlit` is an optional phone-owned, reversible cosmetic setting; selecting it requires Sprout growth in Store. Imports preserve the current configuration. Milestone journal entries use earned-break thresholds, not reconstructed historical dates.
