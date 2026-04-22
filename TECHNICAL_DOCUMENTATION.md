# Technical Documentation

This document describes the current implementation of the LoonyBear app based only on the code that is present in the repository.

## 1. Application Structure

### 1.1 Entry Points
- App entry point: `LoonyBear/LoonyBearApp.swift`
- Environment composition: `LoonyBear/App/AppEnvironment.swift`
- Main content root: `LoonyBear/ContentView.swift`
- Main tab container: `LoonyBear/App/RootTabView.swift`

### 1.2 Main Runtime Components
The app is composed from these main runtime components:
- `HabitAppState`
- `PillAppState`
- `NotificationService`
- `PillNotificationService`
- `AppBadgeService`
- `AppNotificationCoordinator`
- `WidgetSyncService`
- `BackupService`

### 1.3 Top-Level Navigation Model
The app has exactly 3 tabs:
- `My Pills`
- `My Habits`
- `Settings`

The default selected tab is `My Pills`.

Create, Details, and Edit flows for Habits and Pills open as modal sheets.

## 2. Persistence

### 2.1 Core Data Container
Defined in `LoonyBear/Persistence.swift`.

- Persistent container name: `LoonyBear`
- Main context: `container.viewContext`
- Main context settings:
  - `automaticallyMergesChangesFromParent = true`
  - `mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy`
- Background contexts are created with `newBackgroundContext()` and use the same merge policy.

### 2.2 Repository Write Coordination
Shared repository helpers are defined in `LoonyBear/Core/Data/CoreDataSupport.swift`.

`CoreDataRepositoryContext` is responsible for:
- creating write contexts
- executing writes inside `performAndWait`
- rolling back on error
- refreshing the read context after successful writes

### 2.3 Read Context Refresh
After successful writes, `refreshReadContext()` is called.

Behavior:
- if `readContext` is main queue and the current thread is main, `refreshAllObjects()` is called directly
- otherwise `readContext.performAndWait { refreshAllObjects() }` is used

## 3. Domain Models

### 3.1 Habits
Defined in `LoonyBear/Core/Domain/HabitModels.swift`.

#### HabitType
Values:
- `build`
- `quit`

#### CompletionSource
Values:
- `swipe`
- `manual edit`
- `notification`
- `restore`
- `auto fill`
- `skipped`

`countsAsCompletion == false` only for `skipped`.

#### HabitHistoryMode
Values:
- `scheduleBased`
- `everyDay`

### 3.2 Pills
Defined in `LoonyBear/Core/Domain/PillModels.swift`.

#### PillCompletionSource
Values:
- `swipe`
- `manual edit`
- `notification`
- `restore`
- `skipped`

`countsAsIntake == false` only for `skipped`.

#### PillHistoryMode
Values:
- `scheduleBased`
- `everyDay`

### 3.3 ReminderTime
Defined in `LoonyBear/Core/Domain/HabitModels.swift`.

`ReminderTime` stores:
- `hour`
- `minute`

`ReminderTime.default()`:
- reads current hour and minute
- rounds minutes up to a 5-minute boundary
- if the rounded minute becomes `60`, hour is incremented and minute becomes `0`

### 3.4 WeekdaySet
Defined in `LoonyBear/Core/Domain/HabitModels.swift`.

Bitmask-based `OptionSet` with:
- `monday`
- `tuesday`
- `wednesday`
- `thursday`
- `friday`
- `saturday`
- `sunday`

Predefined groups:
- `weekdays`
- `weekends`
- `daily`

## 4. Shared History Logic

Defined in `LoonyBear/Core/Data/CoreDataSupport.swift`.

### 4.1 EditableHistoryWindow
`EditableHistoryWindow.dates(startDate:today:maxDays:calendar:)`
- default `maxDays = 30`
- returns up to 30 days ending at today
- excludes dates earlier than `startDate`

`EditableHistoryWindow.pastDates(...)`
- returns the same window without today

### 4.2 EditableHistoryStateMachine
`EditableHistoryStateMachine.nextSelection(...)`

For `today`:
- `none -> positive`
- `positive -> skipped`
- `skipped -> none`

For past days:
- `positive -> skipped`
- `skipped -> positive`
- `none -> skipped`

### 4.3 EditableHistoryContract
`EditableHistoryContract.normalizedSelection(...)`
- normalizes all dates to `startOfDay`
- computes missing required past days
- fills them with either positive or skipped default state
- removes any skipped day that is also positive

### 4.4 HistoryScheduleApplicability
Functions:
- `pastEditableDays(...)`
- `pastScheduledEditableDays(...)`
- `pastRequiredEditableDays(...)`
- `effectiveWeekdays(on:from:calendar:)`

These helpers are used to determine which past editable days must be finalized according to schedule and history mode.

## 5. Habit Pipeline

### 5.1 Application Layer
Files:
- `LoonyBear/Core/Application/CreateHabitUseCase.swift`
- `LoonyBear/Core/Application/UpdateHabitUseCase.swift`
- `LoonyBear/Core/Application/LoadDashboardUseCase.swift`
- `LoonyBear/Core/Application/ReconcilePastHistoryUseCase.swift`
- `LoonyBear/Core/Application/HabitAppState.swift`
- `LoonyBear/Core/Application/HabitSideEffectCoordinator.swift`

### 5.2 CreateHabitUseCase Rules
Validation rules:
- name must not be empty after trimming
- at least one schedule day must be selected

Repository-level create rule:
- maximum number of habits is `20`

### 5.3 Habit Repository
Protocol: `LoonyBear/Core/Data/HabitRepository.swift`
Implementation: `LoonyBear/Core/Data/CoreDataHabitRepository.swift`

### 5.4 Habit Creation
Create flow writes:
- one `Habit`
- one initial `HabitScheduleVersion`
- `historyModeRaw`
- optional reminder values

After that, `autoFillMissingCompletedCompletions(...)` is executed.

### 5.5 Habit Auto Fill
`autoFillMissingCompletedCompletions(...)` inserts `HabitCompletion` rows with source:
- `auto fill`

Rules:
- does not overwrite existing positive completion rows
- does not overwrite existing skipped rows
- does not insert a row if history objects already exist for that day

### 5.6 Habit Reconciliation
`reconcilePastDays(today:)`:
- loads all habits
- validates required fields
- loads schedule history and completion history
- computes required past days from `HabitHistoryMode`
- inserts missing completed rows through the same auto-fill helper
- saves only if inserted count is greater than `0`

### 5.7 Habit Today Mutations
`completeHabitToday(id:)`
- if today already has a skipped row, converts it to `swipe`
- if today already has a positive row, leaves it unchanged
- if today has no row, inserts a positive `swipe` row

`skipHabitToday(id:)`
- if today already has a skipped row, no-op
- if today has no row, inserts a skipped row

`clearHabitDayStateToday(id:)`
- deletes today's row if present

### 5.8 Habit Update
`updateHabit(from:)`:
- updates name
- updates reminder flags and time
- inserts a new `HabitScheduleVersion` if the weekday mask changed
- reads the persisted `historyModeRaw` already stored on the Habit
- builds editable day set from `EditableHistoryWindow.dates(startDate:)`
- normalizes selected days with `EditableHistoryContract.normalizedSelection(...)`
- uses `pastDefaultSelection: .positive`
- rewrites rows day by day using `manual edit` or `skipped`
- removes duplicate history rows for the same day except the primary latest row
- deletes today's row if the normalized selection for today is none

### 5.9 Habit Dashboard Projection
`fetchDashboardHabits()` builds `HabitCardProjection` values.

Projection fields include:
- type
- name
- latest schedule summary
- current streak
- reminder text
- reminder time hour/minute
- `isReminderScheduledToday`
- `isCompletedToday`
- `isSkippedToday`
- sort order

## 6. Pill Pipeline

### 6.1 Application Layer
Files:
- `LoonyBear/Core/Application/PillAppState.swift`
- `LoonyBear/Core/Application/PillSideEffectCoordinator.swift`

### 6.2 Pill Repository
Protocol: `LoonyBear/Core/Data/PillRepository.swift`
Implementation: `LoonyBear/Core/Data/CoreDataPillRepository.swift`

### 6.3 Pill Create Rules
Create form validation rules:
- name must not be empty after trimming
- dosage must not be empty after trimming
- at least one schedule day must be selected

There is no repository-level max-count rule for pills.

### 6.4 Pill Create Generation
Before repository create is called, `CreatePillView` generates `takenDays` from `startDate` through yesterday.

Rules:
- if `useScheduleForHistory == true`, only scheduled days are included
- if `useScheduleForHistory == false`, every day in the range is included

### 6.5 Pill Creation
Create flow writes:
- one `Pill`
- one initial `PillScheduleVersion`
- `historyModeRaw`
- one `PillIntake` row per generated `takenDay` with source `manual edit`

After that, `autoFinalizeMissingSkippedIntakes(...)` is executed.

### 6.6 Pill Reconciliation
`reconcilePastDays(today:)`:
- loads all pills
- validates required fields
- loads schedules and intakes
- computes required past days from `PillHistoryMode`
- inserts missing skipped rows
- saves only if inserted count is greater than `0`

### 6.7 Pill Today Mutations
`markTakenToday(id:)`
- if today already has skipped, converts it to `swipe`
- if today already has positive, leaves it unchanged
- if today has no row, inserts `swipe`

`skipPillToday(id:)`
- if today already has skipped, no-op
- if today has no row, inserts skipped

`clearPillDayStateToday(id:)`
- deletes today's row if present

### 6.8 Pill Update
`updatePill(from:)`:
- updates name, dosage, details
- updates reminder flags and time
- inserts a new `PillScheduleVersion` if weekday mask changed
- reads the persisted `historyModeRaw` already stored on the Pill
- builds editable day set from `EditableHistoryWindow.dates(startDate:)`
- computes required finalized days:
  - `scheduleBased -> pastScheduledEditableDays`
  - `everyDay -> pastEditableDays`
- normalizes selected days with `EditableHistoryContract.normalizedSelection(...)`
- rewrites rows day by day using `manual edit` or `skipped`
- removes duplicate history rows for the same day except the primary latest row
- deletes today's row if the normalized selection for today is none

### 6.9 Pill Dashboard Projection
`fetchDashboardPills()` builds `PillCardProjection` values.

Projection fields include:
- name
- dosage
- latest schedule summary
- total taken days
- reminder text
- reminder time hour/minute
- `isReminderScheduledToday`
- `isScheduledToday`
- `isTakenToday`
- `isSkippedToday`
- sort order

## 7. Streak Engine

Defined in `LoonyBear/Core/Domain/StreakEngine.swift`.

### 7.1 Current Streak
Behavior:
- every completed day increments the running streak
- a missing unscheduled day does not reset the streak
- a missed scheduled day in the past resets the streak
- today does not reset the streak only because it is not completed yet

### 7.2 Longest Streak
`longestStreak(...)` runs the same metrics logic up to the latest completion day and returns the maximum running value encountered.

### 7.3 Effective Schedule Resolution
For streak calculations, schedule for a day is the latest `HabitScheduleVersion` whose `effectiveFrom` is not later than that day, ordered by:
- `effectiveFrom`
- `version`
- `createdAt`

## 8. Notifications

### 8.1 Shared Notification Support
Defined in `LoonyBear/Core/Services/NotificationSupport.swift`.

Includes:
- notification names for store change and tab opening
- `NotificationStoreContext`
- authorization helper
- stale delivered notification cleanup
- pending notification removal helpers
- local date identifier encoding and parsing

`localDate` identifier format is `YYYYMMDD`.

### 8.2 AppNotificationCoordinator
Defined in `LoonyBear/Core/Services/AppNotificationCoordinator.swift`.

Responsibilities:
- register all Habit and Pill categories
- act as `UNUserNotificationCenterDelegate`
- route notification responses to Habit or Pill notification services based on payload `type`
- refresh badge after a notification response is handled
- present banner, sound, and list while app is foregrounded

### 8.3 Habit Notification Service
Defined in `LoonyBear/Core/Services/NotificationService.swift`.

Constants:
- category identifier: `habit.reminder`
- summary category: `habit.reminder.summary`
- actions:
  - `habit.complete`
  - `habit.skip`
- scheduling window: `2` days
- aggregation threshold: `3`

Candidate rules:
- reminder enabled
- valid reminder time
- day is not before start date
- weekday matches schedule
- day not completed
- day not skipped
- reminder time still in the future

Default tap behavior:
- opens `My Habits`

Action behavior:
- resolves logical day from payload `localDate`
- if missing or invalid, falls back to notification date
- `habit.complete` creates a positive `notification` completion if needed
- `habit.skip` creates a skipped completion if needed

### 8.4 Pill Notification Service
Defined in `LoonyBear/Core/Services/PillNotificationService.swift`.

Constants:
- category identifier: `pill.reminder`
- summary category: `pill.reminder.summary`
- actions:
  - `pill.take`
  - `pill.skip`
  - `pill.remind_later`
- scheduling window: `2` days
- aggregation threshold: `3`
- remind later interval: `600` seconds

Default tap behavior:
- opens `My Pills`

Action behavior:
- resolves logical day from payload `localDate`
- if missing or invalid, falls back to notification date
- `pill.take` creates a positive `notification` intake if needed
- `pill.skip` creates a skipped intake if needed
- `pill.remind_later` creates a delayed pill reminder `10` minutes from now

### 8.5 Snoozed Pill Notification Rules
The Pill notification service distinguishes regular scheduled notifications from remind-later notifications.

Behavior:
- global reschedule removes only regular pill reminders
- active remind-later notifications survive global reschedule
- remind-later notifications are removed when:
  - the same pill and day are taken
  - the same pill and day are skipped
  - the pill is deleted

## 9. Badge Service

Defined in `LoonyBear/Core/Services/AppBadgeService.swift`.

### 9.1 Badge Count
Badge count is:
- overdue Habit count
- plus overdue Pill count

### 9.2 Overdue Habit Rule
A Habit is overdue when:
- `isReminderScheduledToday == true`
- it is not completed today
- it is not skipped today
- reminder hour and minute exist
- reminder time for today is less than or equal to `now`

### 9.3 Overdue Pill Rule
A Pill is overdue when:
- `isReminderScheduledToday == true`
- it is not taken today
- it is not skipped today
- reminder hour and minute exist
- reminder time for today is less than or equal to `now`

### 9.4 Badge API
- on iOS 17+: `UNUserNotificationCenter.setBadgeCount`
- on older systems: `UIApplication.shared.applicationIconBadgeNumber`

## 10. Backup and Restore

### 10.1 Backup Models
Defined in `LoonyBear/Core/Domain/BackupModels.swift`.

Main archive type: `BackupArchive`

Fields:
- `schemaVersion`
- `exportedAt`
- `habits`
- `scheduleVersions`
- `completionRecords`
- `ordering`
- `pills`
- `pillScheduleVersions`
- `pillIntakeRecords`

### 10.2 BackupService
Defined in `LoonyBear/Core/Services/BackupService.swift`.

Constants:
- app name: `LoonyBear`
- schema version: `1`
- file names:
  - `LoonyBear.json.gz`
  - `LoonyBear.previous.json.gz`
  - `LoonyBear.restore-snapshot.json.gz`

### 10.3 Backup Create Flow
`createBackup()`:
- resolves security-scoped folder URL
- builds archive from Core Data
- encodes JSON
- gzip-compresses the payload
- deletes old `.previous` file if present
- moves old primary backup to `.previous` if present
- writes the new primary backup atomically

### 10.4 Backup Restore Flow
`restoreBackup()`:
- resolves security-scoped folder URL
- tries to create restore snapshot of current store
- if snapshot payload creation fails with `DataIntegrityError`, restore can continue
- if snapshot encode/compress/write fails, restore aborts
- loads archive
- validates archive
- replaces store
- resets the read context after replacement

### 10.5 Restore Validation
Validation includes:
- schema version
- valid habit type
- valid habit history mode
- valid pill history mode
- valid reminder times
- valid weekday masks
- valid completion and intake source values
- foreign key existence for schedules, completions, and intakes
- duplicate identifier detection across all backup entity arrays

## 11. Reliability Support

Defined in `LoonyBear/Core/Services/ReliabilitySupport.swift`.

### 11.1 Types
- `DataIntegrityIssue`
- `DataIntegrityReport`
- `DataIntegrityError`
- `IntegrityReportBuilder`
- `ReminderValidation`
- `WeekdayValidation`
- `ReliabilityLog`

### 11.2 DataIntegrityError
`errorDescription` format:
- `Data integrity problem during <operation>. <count> corrupted record(s) detected.`

### 11.3 ReminderValidation Rules
If reminder is enabled:
- hour must exist
- minute must exist
- hour must be in `0...23`
- minute must be in `0...59`

### 11.4 WeekdayValidation Rules
A weekday mask is valid only if:
- raw value is not negative
- no bits are used outside `WeekdaySet.daily.rawValue`

## 12. Widgets

### 12.1 Widget Snapshot Models
Defined in `LoonyBear/Core/Domain/WidgetSnapshotModels.swift`.

Stored widget snapshot includes:
- generation date
- habit sections
- habits inside each section with:
  - id
  - name
  - schedule summary
  - current streak
  - `isCompletedToday`

### 12.2 WidgetSnapshotStore
Defined in `LoonyBear/Core/Services/WidgetSnapshotStore.swift`.

App group identifier:
- `group.com.valr4k.LoonyBear`

Storage path:
- app group container if available
- otherwise `Application Support/LoonyBear/widget-snapshot.json`

### 12.3 WidgetSyncService
Defined in `LoonyBear/Core/Services/WidgetSyncService.swift`.

Behavior:
- builds a widget snapshot from Habit dashboard only
- saves snapshot to `WidgetSnapshotStore`
- logs success or failure
- reloads all widget timelines if `WidgetKit` is available

## 13. Settings and Reference Content

### 13.1 Settings Screen
Defined in `LoonyBear/Features/Settings/SettingsView.swift`.

Contains:
- Appearance segmented picker
- Backup navigation
- Rules & Logic navigation
- informational rows for Apple Watch notifications and iPhone widgets
- app version and build footer

### 13.2 Rules & Logic Screen
Defined in `LoonyBear/Features/Settings/RulesLogicView.swift`.

Behavior:
- loads `RulesLogicContent.json` from bundle
- shows loading state first
- shows unavailable state if content cannot be loaded or decoded

## 14. Demo Data

Defined in `LoonyBear/Core/Data/DemoDataWriter.swift`.

Preview seeding rules:
- runs only if there are no Habit rows yet
- seeds 3 Habits
- creates one schedule and one completed day for each seeded Habit
- does not create Pills
