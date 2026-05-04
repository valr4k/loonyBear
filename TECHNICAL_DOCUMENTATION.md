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

Settings uses route-based navigation:
- `SettingsRoute.backup`
- `SettingsRoute.rulesLogic`

`RootTabView` stores the selected tab and active Settings route in `@SceneStorage` so a tint-driven root rebuild or restored appearance setting does not drop the user out of the Settings/Backup flow.

Settings child screens use the shared custom tinted back button while preserving the native left-edge interactive pop gesture through `AppInteractivePopGestureEnabler`.

### 1.4 Device Orientation
The app is configured as portrait-only on iPhone.

iPad keeps the default portrait and landscape orientations.

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
- `none -> positive`

### 4.3 EditableHistoryContract
`EditableHistoryContract.normalizedSelection(...)`
- normalizes all dates to `startOfDay`
- computes missing required past days
- fills them with either positive or skipped default state
- removes any skipped day that is also positive

Current Habit and Pill update flows pass an empty required-day set and `pastDefaultSelection: .none`, so saving an edit does not auto-fill missing editable past days.

`EditableHistoryValidation.missingPastDays(...)`
- checks editable days before today
- requires each past editable day to have either a positive state or a skipped state
- allows today to stay empty
- returns missing past editable days so the UI and repositories can block save with a clear validation error

### 4.4 HistoryScheduleApplicability
Functions:
- `pastEditableDays(...)`
- `pastScheduledEditableDays(...)`
- `pastRequiredEditableDays(...)`
- `scheduledDays(...)`
- `effectiveWeekdays(on:from:calendar:)`

These helpers are used to determine which past editable days must be finalized according to schedule and history mode. Editable history never includes days before `startDate` or future days. `scheduledDays(...)` returns the normalized schedule-matching dates through a supplied end date so Details/Edit calendars can draw schedule indicators, including future scheduled dots, without changing stored history.

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
- start date may be selected from the last 30 days through the end of the second next calendar month

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

After that, the repository generates initial completed days from `startDate` through yesterday and inserts one `HabitCompletion` per generated day.
If `startDate` is in the future, no initial history rows are generated and the item has no overdue, today action/status, notifications, or history review before that date.

### 5.5 Habit Auto Fill
Initial Habit history generation inserts `HabitCompletion` rows with source:
- `auto fill`

Rules:
- if `useScheduleForHistory == true`, only scheduled days are generated
- if `useScheduleForHistory == false`, every day in the range is generated
- does not overwrite existing positive completion rows
- does not overwrite existing skipped rows
- does not insert a row if history objects already exist for that day

### 5.6 Habit Reconciliation
`reconcilePastDays(today:)`:
- is a no-op for stored history rows
- does not insert `skipped` rows for overdue catch-up
- leaves missing scheduled days empty so the projection layer can classify them as active overdue or history gaps

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

Card leading swipe actions call the day-specific variants for `activeOverdueDay` when it is set. Otherwise they target today. History gaps cannot be repaired from the card; they must be fixed in Edit.

Card trailing swipe actions expose:
- Edit with system blue
- Info with system indigo

Delete is not available from card swipe actions.

### 5.8 Habit Update
`updateHabit(from:)`:
- updates name
- updates reminder flags and time
- inserts a new `HabitScheduleVersion` if the schedule rule changed
- uses the resolved `Apply From` date shown in Edit as the new schedule version `effectiveFrom`
- if the selected Apply From date already has an explicit state or does not match a weekly rule, it is resolved forward to the next available scheduled day; for interval rules, the resolved date becomes the new interval anchor
- preserves the persisted `historyModeRaw` already stored on the Habit
- builds editable day set from `EditableHistoryWindow.dates(startDate:)`
- normalizes selected days with `EditableHistoryContract.normalizedSelection(...)`
- uses `pastDefaultSelection: .none`
- validates that every past editable scheduled day is either `manual edit`/completed or `skipped`
- throws `EditableHistoryValidationError.missingHabitPastDays` if a past editable scheduled day is empty
- Edit Habit includes a past active overdue day in save validation and disables Save until it is resolved
- Edit Habit surfaces missing past-day review through the dismissible `AppFloatingWarningBanner`; if only the active overdue day is missing, the banner uses overdue-specific copy
- Habit Details computes missing past days from `requiredPastScheduledDays`; it shows the same floating banner with active-overdue-specific copy when the only missing day is the active overdue day, otherwise it asks the user to open Edit and resolve the missing scheduled days
- Edit Habit delete confirmation uses a system alert with `Cancel` and destructive `Delete` actions
- missing past-day warning copy intentionally omits the date list; the validation error still carries the missing dates for logic/tests
- rewrites rows day by day using `manual edit` or `skipped`
- removes duplicate history rows for the same day except the primary latest row
- deletes any editable-day row whose normalized selection is none

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
- `needsHistoryReview`
- `activeOverdueDay`
- sort order

If `activeOverdueDay` is set, Habit cards show a red `Today`, `Yesterday`, or date label. `activeOverdueDay` is derived from the latest due scheduled day: if that latest due day is empty, it is active overdue; if it already has completed/skipped state, there is no active overdue even if older due days are empty. `needsHistoryReview` excludes the active overdue day, so Habit cards show the amber history warning icon alongside overdue only when another required past scheduled day is empty. `HabitDetailsProjection.requiredPastScheduledDays` still includes the active overdue day for Details and Edit validation. If neither applies, the card shows today's completed/skipped status.

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
- start date may be selected from the last 5 years through the end of the second next calendar month

Repository-level create rule:
- maximum number of pills is `20`

### 6.4 Pill Create Generation
Repository create generates `takenDays` from `startDate` through yesterday.
If `startDate` is in the future, no initial history rows are generated and the item appears in Pending with no overdue, today action/status, notifications, or history review before that date.

Rules:
- if `useScheduleForHistory == true`, only scheduled days are included
- if `useScheduleForHistory == false`, every day in the range is included

### 6.5 Pill Creation
Create flow writes:
- one `Pill`
- one initial `PillScheduleVersion`
- `historyModeRaw`
- one `PillIntake` row per generated `takenDay` with source `manual edit`
- today is not prefilled

### 6.6 Pill Reconciliation
`reconcilePastDays(today:)`:
- is a no-op for stored history rows
- does not insert `skipped` rows for overdue catch-up
- leaves missing scheduled days empty so the projection layer can classify them as active overdue or history gaps

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

Card leading swipe actions call the day-specific variants for `activeOverdueDay` when it is set. Otherwise they target today. History gaps cannot be repaired from the card; they must be fixed in Edit.

Card trailing swipe actions expose:
- Edit with system blue
- Info with system indigo

Delete is not available from card swipe actions.

### 6.8 Pill Update
`updatePill(from:)`:
- updates name, dosage, details
- updates reminder flags and time
- inserts a new `PillScheduleVersion` if the schedule rule changed
- uses the resolved `Apply From` date shown in Edit as the new schedule version `effectiveFrom`
- if the selected Apply From date already has an explicit state or does not match a weekly rule, it is resolved forward to the next available scheduled day; for interval rules, the resolved date becomes the new interval anchor
- preserves the persisted `historyModeRaw` already stored on the Pill
- builds editable day set from `EditableHistoryWindow.dates(startDate:)`
- normalizes selected days with `EditableHistoryContract.normalizedSelection(...)`
- uses `pastDefaultSelection: .none`
- validates that every past editable scheduled day is either `manual edit`/taken or `skipped`
- throws `EditableHistoryValidationError.missingPillPastDays` if a past editable scheduled day is empty
- Edit Pill includes a past active overdue day in save validation and disables Save until it is resolved
- Edit Pill surfaces missing past-day review through the dismissible `AppFloatingWarningBanner`; if only the active overdue day is missing, the banner uses overdue-specific copy
- Pill Details computes missing past days from `requiredPastScheduledDays`; it shows the same floating banner with active-overdue-specific copy when the only missing day is the active overdue day, otherwise it asks the user to open Edit and resolve the missing scheduled days
- Edit Pill delete confirmation uses a system alert with `Cancel` and destructive `Delete` actions
- missing past-day warning copy intentionally omits the date list; the validation error still carries the missing dates for logic/tests
- rewrites rows day by day using `manual edit` or `skipped`
- removes duplicate history rows for the same day except the primary latest row
- deletes any editable-day row whose normalized selection is none

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
- `needsHistoryReview`
- `activeOverdueDay`
- sort order

If `activeOverdueDay` is set, Pill cards show a red `Today`, `Yesterday`, or date label. `activeOverdueDay` is derived from the latest due scheduled day: if that latest due day is empty, it is active overdue; if it already has taken/skipped state, there is no active overdue even if older due days are empty. `needsHistoryReview` excludes the active overdue day, so Pill cards show the amber history warning icon alongside overdue only when another required past scheduled day is empty. `PillDetailsProjection.requiredPastScheduledDays` still includes the active overdue day for Details and Edit validation. If neither applies, the card shows today's taken/skipped status.

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
For streak, overdue, notification, history-review, and calendar indicator calculations, schedule for a day is the latest schedule version whose `effectiveFrom` is not later than that day, ordered by:
- `effectiveFrom`
- `version`
- `createdAt`

Weekly schedules use the stored weekday mask. `Every N days` schedules use the active schedule version `effectiveFrom` as the interval anchor. Legacy `daily`, `weekdays`, and `weekends` schedule kind values are read as weekly masks; new writes store those choices as `weekly`.

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

Create/Edit reminder permission behavior:
- toggling Reminder on calls the shared authorization helper
- `.notDetermined` can show the system notification permission prompt
- `.denied` cannot show that prompt again, so the toggle is reverted and the UI shows an alert with `Open Settings`
- the old inline notification-permission validation banner is not used for denied permissions

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
- `activeOverdueDay != nil`
- the active overdue day is the latest due scheduled day
- the latest due scheduled day has reminder time passed, or 00:00 has passed when reminders are disabled
- the latest due scheduled day is neither completed nor skipped
- the active overdue day is excluded from Dashboard card missing-history review while it remains the latest due scheduled day
- Details and Edit still require a past active overdue day to be completed or skipped
- older empty due scheduled days remain missing history and require manual review

### 9.3 Overdue Pill Rule
A Pill is overdue when:
- `activeOverdueDay != nil`
- the active overdue day is the latest due scheduled day
- the latest due scheduled day has reminder time passed, or 00:00 has passed when reminders are disabled
- the latest due scheduled day is neither taken nor skipped
- the active overdue day is excluded from Dashboard card missing-history review while it remains the latest due scheduled day
- Details and Edit still require a past active overdue day to be taken or skipped
- older empty due scheduled days remain missing history and require manual review

Badge and overdue calculation do not use overdue anchors as source of truth.
Repository reconciliation does not auto-skip missing overdue/history days.
The active overdue label shown on cards is `Today`, `Yesterday`, or a date like `26.04.2026`.

### 9.4 Badge API
- on iOS 17+: `UNUserNotificationCenter.setBadgeCount`
- on older systems: `UIApplication.shared.applicationIconBadgeNumber`
- `refreshBadge(habitDashboard:pillDashboard:now:forceApply:)` computes from already-loaded dashboard projections
- the service caches the last badge count and skips redundant badge writes unless `forceApply` is true

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
- `settings`
- `pills`
- `pillScheduleVersions`
- `pillIntakeRecords`

`settings` is optional for backward compatibility and uses `BackupAppSettings`:
- `appearanceMode`
- `appTint`

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
- adds current app appearance settings from `UserDefaults`
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
- applies backed-up app appearance settings when present
- resets the read context after replacement

### 10.5 Restore Validation
Validation includes:
- schema version
- valid app appearance mode and app tint values when `settings` is present
- valid habit type
- valid habit history mode
- valid pill history mode
- valid reminder times
- valid weekday masks
- valid completion and intake source values
- foreign key existence for schedules, completions, and intakes
- duplicate identifier detection across all backup entity arrays

### 10.6 Backup Settings Screen
Defined in `LoonyBear/Features/BackupSettings/BackupSettingsView.swift`.

Status rows:
- `Last backup`
- `Total size`
- `Folder`

UI behavior:
- `Last backup` uses the same color as the cloud status icon
- green means a readable backup exists
- red means no readable backup is available
- `Create Backup` and `Restore Backup` are full-width capsule buttons
- `Create Backup` uses the primary label color
- `Restore Backup` stays system red
- create and restore confirmation prompts use system alerts instead of popover-style confirmation dialogs; action labels are shortened to `Backup` and `Restore`
- Folder selection only grants access and reloads backup metadata; it never applies the backup automatically
- `BackupStatus.fileState` describes the selected folder as `none`, `available`, `created`, `restored`, or `unreadable`
- readable backup files are fingerprinted from their compressed file data using SHA-256
- after a successful create, the current fingerprint is stored as the last created backup fingerprint
- after a successful restore, the current fingerprint is stored as the last restored backup fingerprint
- if a selected folder contains a readable backup whose fingerprint is neither created nor restored in this app install, the screen shows `Backup found. Tap Restore Backup to apply it.` as a blue floating informational banner
- while that restore-available notice is visible, `Create Backup` is disabled so the next action is explicitly `Restore Backup`
- if a selected folder contains no readable backup, the screen shows `No backup found. Tap Create Backup to save one.` as a blue floating informational banner
- if the selected backup fingerprint was created or restored by this app install, no action notice is shown
- if backup files exist but cannot be read, the screen shows `Backup file can’t be read. Choose another folder or create a new backup.` as a red floating banner
- all Backup banners are dismissible overlays pinned near the bottom of the visible screen; they auto-hide after 4 seconds and clear when leaving the Backup screen
- successful create/restore still records the fingerprint, and success feedback is shown as green floating banners: `Backup Created` and `Restore Complete`
- successful restore refreshes dashboards, rebuilds notifications, shows the green restore success banner, and clears the restore-needed notice for that fingerprint

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
- skips scheduling work when the same content is already saved or pending
- saves snapshot to `WidgetSnapshotStore` on a utility queue
- updates the saved-content cache only after a successful save attempt
- retries the same dashboard content if a previous write failed
- logs success or failure
- reloads all widget timelines after a successful changed save if `WidgetKit` is available

## 13. Settings and Reference Content

### 13.1 Settings Screen
Defined in `LoonyBear/Features/Settings/SettingsView.swift`.

Contains:
- Appearance segmented picker
- Color palette with `Blue`, `Indigo`, `Green`, and `Amber`
- Backup navigation
- Rules & Logic navigation
- app version and build footer

Navigation behavior:
- Settings child screens keep the custom tinted back button and support the native left-edge swipe-back gesture.

Appearance behavior:
- `Blue` is the default app tint and appears first in the palette.
- `Blue`, `Indigo`, `Green`, and `Amber` use system colors. `Amber` maps to `UIColor.systemOrange`.
- Tints apply to supported accent surfaces.
- Page backgrounds remain `systemGroupedBackground`; the app tint background wash is currently disabled in `AppBackground`.
- Legacy stored tint values `default`, `gray`, `yellow`, `cyan`, `teal`, `brown`, `red`, and `white` are migrated to `Blue`.
- The root `TabView` is not globally tinted; tab item colors refresh through `UITabBarAppearance` so tint does not leak into child controls.
- `LoonyBearApp` also updates visible `UITabBar` and `UINavigationBar` instances when app tint or appearance mode changes, so current screens update without requiring a tab switch.
- Editable schedule checkmarks, Settings app-row icons, and Calendar Taken/Completed markers use the selected app tint.
- The following remain fixed system colors and do not follow app tint: read-only schedule checkmarks, scheduled-day calendar dots, toggles, segmented picker selection, skipped markers, overdue and warning colors, card Edit/Info swipe actions, and Backup action rows.

Shared warning overlay behavior:
- `AppFloatingWarningBanner` is defined in `LoonyBear/Shared/AppDesign.swift`.
- Edit Habit, Edit Pill, Habit Details, and Pill Details use it for missing past-day review.
- The banner is an overlay pinned near the bottom of the visible screen, uses `ultraThinMaterial` with a fixed system-red warning tint, can be dismissed, and disappears automatically when the missing-day condition is resolved.
- Because the banner is not part of the scroll content, resolving the final missing day does not shift the calendar upward.

### 13.2 Rules & Logic Screen
Defined in `LoonyBear/Features/Settings/RulesLogicView.swift`.

Behavior:
- loads `RulesLogicContent.json` from bundle
- shows loading state first
- shows unavailable state if content cannot be loaded or decoded

### 13.3 Shared Month Calendar
Defined in `LoonyBear/Shared/MonthCalendarView.swift`.

Behavior:
- renders available months with a shared month grid
- month navigation is controlled by the header chevron buttons
- horizontal swipe paging is disabled
- the day grid uses a stable six-week footprint and adjusts vertical row spacing for months with fewer visible week rows
- Habit and Pill Details/Edit calendar day views can draw a small `tertiaryLabel` dot under dates that match the effective schedule history

### 13.4 Shared Schedule UI
Defined in `LoonyBear/Shared/AppDesign.swift`.

Create/Edit schedule behavior:
- schedule rows open `AppScheduleEditorPopoverContent` from `AppSchedulePickerRow`
- schedule rows use a tap gesture instead of a visible pressed `Button` highlight
- the popover uses full weekday names
- the popover has no Weekly/Intervals mode switch; weekday rows and the Intervals row are shown together
- the Intervals row uses a native Stepper for every 2 to 5 days
- weekday summaries are canonicalized as Daily, Weekdays, Weekends, Weekly for one selected weekday, or Custom for other combinations
- day rows use compact `schedulePopoverRowVerticalPadding`
- dividers between weekday rows are not shown
- `Use schedule for history?` appears only when the caller supplies a binding
- helper copy is shown inside the popover when supplied
- the popover content has no extra inner card/background layer; the system popover bubble provides the visual container

Details schedule behavior:
- Details screens open `AppReadOnlySchedulePopoverContent`
- Details schedule rows use a tap gesture instead of a visible pressed `Button` highlight
- read-only schedule popovers use the same full weekday names and compact row spacing
- selected read-only days show a neutral secondary checkmark

### 13.5 Reminder Time UI
Defined in `LoonyBear/Shared/AppDesign.swift`.

Behavior:
- Create/Edit reminder time rows render the selected time in a capsule value
- tapping the row opens a wheel-style time picker popover
- the visible row does not use compact `DatePicker` styling, so it does not show a pressed capsule effect

### 13.6 Editable Start Date UI
Defined in `LoonyBear/Shared/AppDesign.swift`.

Behavior:
- Create screens render the selected start date in a capsule value
- tapping the row opens a graphical calendar popover
- the visible row does not use compact `DatePicker` styling, so it does not show a pressed capsule effect

## 14. Startup Health Check

Defined in `LoonyBear/Core/Services/ReliabilitySupport.swift`.

After the first initial dashboard load, `ContentView` runs `AppStartupHealthCheckCoordinator.runIfNeeded()` in a background task.

The startup health check validates:
- Habit and Pill required fields
- enum-backed stored values such as habit type, history mode, and history source
- reminder hour/minute fields when reminders are enabled
- latest schedule weekday masks
- duplicate HabitCompletion and PillIntake rows for the same owner/day

It logs success or a `DataIntegrityError`; it does not block the initial dashboard load.

## 15. Demo Data

Defined in `LoonyBear/Core/Data/DemoDataWriter.swift`.

Preview seeding rules:
- runs only if there are no Habit rows yet
- seeds 3 Habits
- creates one schedule and one completed day for each seeded Habit
- does not create Pills
