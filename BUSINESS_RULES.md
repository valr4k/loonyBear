# LoonyBear Business Rules

This file describes the behavioral rules that are currently implemented in code.

## Habits

- A Habit belongs to one type: `build` or `quit`.
- Habits are shown in dashboard sections grouped by type.
- A Habit day can be in one of 3 stored states:
  - completed
  - skipped
  - unset
- A skipped Habit day does not count as completion.
- Completing a Habit on a day that was previously skipped overwrites the skipped state with a positive state.
- Clearing today removes the stored row for today.
- Habit name must not be empty.
- At least one schedule day must be selected.
- The app allows at most 20 Habits.

## Habit History Modes

- Every Habit stores a `historyMode`.
- `scheduleBased` means generated past history follows the schedule.
- `everyDay` means generated past history counts every day from `startDate` through yesterday.
- Missing-history review and Edit save validation require only past editable days that were scheduled by the effective schedule history.
- Dashboard cards exclude the active overdue day from missing-history review while it remains actionable overdue.
- Details and Edit include an active overdue day when that day is in the past, because past scheduled days should be resolved from the calendar surfaces.
- Edit save validation includes an active overdue day when that day is in the past, because past scheduled days cannot be saved empty.
- Habit create, details loading, backup, and restore read the stored history mode. The current Habit Details UI does not display a dedicated history mode row, and the Edit screen does not expose a history mode toggle.
- Saving Edit Habit preserves the stored history mode. Missing scheduled editable past days are not auto-filled; they block saving until the user chooses a state.

## Habit Create and Reconciliation

- Habit create inserts the root Habit row and an initial schedule version.
- After create, the repository generates completed history from `startDate` through yesterday.
- In `scheduleBased` mode, only scheduled days are generated.
- In `everyDay` mode, every day in that range is generated.
- The auto-filled completion source is `auto fill`.
- Habit reconciliation does not backfill missing past history.
- Habit reconciliation does not auto-skip overdue days.
- A scheduled day becomes due at its reminder time. If reminders are disabled, it becomes due at 00:00.
- The active overdue day is the latest due scheduled day only when that latest due day has no completed or skipped state.
- Empty due scheduled days before the active overdue day are history gaps, not skipped rows.
- Stale notification actions for days that have already become history gaps are ignored and only dismiss the notification.
- Restore clears stale overdue anchors, but overdue and history gaps are derived from the restored schedule/history data.
- Existing completed rows are preserved.
- Existing skipped rows are preserved.

## Habit Edit Rules

- Habit history editing is limited to the last 30 days and never earlier than `startDate`.
- Today can be empty, completed, or skipped.
- Past editable scheduled Habit days must be explicitly completed or skipped before saving.
- Save is disabled while any past editable scheduled Habit day is empty.
- Missing past-day review is shown as a dismissible floating warning banner pinned near the bottom of Edit Habit. It does not take space in the calendar layout and disappears once all required past scheduled days are resolved.
- If the only missing Habit day is the active overdue day, the floating warning asks the user to choose `Completed` or `Skipped` for the overdue scheduled day.
- Missing past-day warning copy does not list the missing dates.
- Habit cards show a warning status instead of today's completed/skipped status while recent history needs review.
- Habit cards do not show the history warning only because of the active overdue day; they show it alongside overdue only when some other required past scheduled day is empty.
- Habit card trailing swipe exposes Edit and Info. Edit uses system blue, Info uses system indigo, and Delete is not available from card swipe actions.
- Habit Details shows the same dismissible floating warning banner while any past scheduled day is missing. If the only missing day is the active overdue day, the warning asks the user to open Edit and choose `Completed` or `Skipped` for the overdue scheduled day.
- Saving Edit Habit does not auto-fill missing past days; the user must choose the state.
- Edit Habit delete confirmation uses a system alert with `Cancel` and destructive `Delete` actions.
- If today's state is already finalized and the schedule is changed, the new schedule takes effect from tomorrow instead of rewriting today's schedule meaning.

## Habit Streak Rules

- A completed day increments streak.
- A missed unscheduled day does not reset streak.
- A missed scheduled day in the past resets streak.
- An uncompleted scheduled today does not reset current streak yet.
- Longest streak uses the same logic across the full recorded timeline.

## Pills

- Pills are shown in one ordered dashboard list that is later split into `Today` and `Pending` sections in the UI.
- A Pill day can be in one of 3 stored states:
  - taken
  - skipped
  - unset
- A skipped Pill day does not count toward total taken days.
- Taking a Pill on a day that was previously skipped overwrites the skipped state with a positive state.
- Clearing today removes the stored row for today.
- Pill order is persisted through `sortOrder`.

## Pill History Modes

- Every Pill stores a `historyMode`.
- `scheduleBased` means generated past history follows the schedule.
- `everyDay` means generated past history counts every day from `startDate` through yesterday.
- Missing-history review and Edit save validation require only past editable days that were scheduled by the effective schedule history.
- Dashboard cards exclude the active overdue day from missing-history review while it remains actionable overdue.
- Details and Edit include an active overdue day when that day is in the past, because past scheduled days should be resolved from the calendar surfaces.
- Edit save validation includes an active overdue day when that day is in the past, because past scheduled days cannot be saved empty.
- Pill create, details loading, backup, and restore read the stored history mode. The current Pill Details UI does not display a dedicated history mode row, and the Edit screen does not expose a history mode toggle.
- Saving Edit Pill preserves the stored history mode. Missing scheduled editable past days are not auto-filled; they block saving until the user chooses a state.

## Pill Create and Reconciliation

- Repository create generates taken history from `startDate` through yesterday.
- In `scheduleBased` mode, generated `takenDays` include only scheduled days.
- In `everyDay` mode, generated `takenDays` include all days in that range.
- Repository create inserts `manual edit` intake rows for all generated `takenDays`.
- Today is not prefilled.
- Pill reconciliation does not backfill missing past history.
- Pill reconciliation does not auto-skip overdue days.
- A scheduled day becomes due at its reminder time. If reminders are disabled, it becomes due at 00:00.
- The active overdue day is the latest due scheduled day only when that latest due day has no taken or skipped state.
- Empty due scheduled days before the active overdue day are history gaps, not skipped rows.
- Stale notification actions for days that have already become history gaps are ignored and only dismiss the notification.
- Restore clears stale overdue anchors, but overdue and history gaps are derived from the restored schedule/history data.
- Existing taken rows are preserved.
- Existing skipped rows are preserved.

## Pill Edit Rules

- Pill history editing is limited to the last 30 days and never earlier than `startDate`.
- Today can be empty, taken, or skipped.
- Past editable scheduled Pill days must be explicitly taken or skipped before saving.
- Save is disabled while any past editable scheduled Pill day is empty.
- Missing past-day review is shown as a dismissible floating warning banner pinned near the bottom of Edit Pill. It does not take space in the calendar layout and disappears once all required past scheduled days are resolved.
- If the only missing Pill day is the active overdue day, the floating warning asks the user to choose `Taken` or `Skipped` for the overdue scheduled day.
- Missing past-day warning copy does not list the missing dates.
- Pill cards show a warning status instead of today's taken/skipped status while recent history needs review.
- Pill cards do not show the history warning only because of the active overdue day; they show it alongside overdue only when some other required past scheduled day is empty.
- Pill card trailing swipe exposes Edit and Info. Edit uses system blue, Info uses system indigo, and Delete is not available from card swipe actions.
- Pill Details shows the same dismissible floating warning banner while any past scheduled day is missing. If the only missing day is the active overdue day, the warning asks the user to open Edit and choose `Taken` or `Skipped` for the overdue scheduled day.
- Saving Edit Pill does not auto-fill missing past days; the user must choose the state.
- Edit Pill delete confirmation uses a system alert with `Cancel` and destructive `Delete` actions.
- If today's state is already finalized and the schedule is changed, the new schedule takes effect from tomorrow instead of rewriting today's schedule meaning.

## Schedule Rules

- Schedules are represented by `WeekdaySet` bitmasks.
- Editing schedule days appends a new schedule version row instead of rewriting older versions.
- The current schedule is the latest schedule version whose `effectiveFrom` is not later than the relevant day.
- If a schedule change is saved after today already has an explicit state, the new schedule version starts tomorrow.
- Schedule rules support Weekly selection plus Intervals: Daily, Weekdays, Weekends, Weekly, Biweekly, and Custom every 2 to 20 days.
- Custom `Every 14 days` uses the same schedule math as Biweekly and is summarized as `Biweekly` on cards and details.
- Create and Edit screens edit schedule days from an in-place popover instead of pushing a separate Schedule screen.
- Details screens show the schedule in a read-only popover.
- Schedule popovers use full weekday names, Intervals single-selection rows, no row dividers, and compact row spacing.
- Schedule rows open popovers without a pressed-row visual effect.
- Create/Edit schedule popovers include `Use schedule for history?` only on flows that expose that option.
- Schedule ordering uses:
  - `effectiveFrom`
  - then `version`
  - then `createdAt`

## Reminder Rules

- Reminders are scheduled only when enabled and authorized.
- Notification permission must be requested on first launch
- Turning on a reminder from Create/Edit requests notification authorization when needed.
- If notification access is denied, the reminder toggle is turned back off and the app shows an alert with an `Open Settings` action instead of an inline validation banner.
- iOS only shows the system notification permission prompt once. After the user chooses `Don’t Allow`, the app can only route the user to Settings.
- Reminder time rows show a capsule value and open a time picker popover without the compact DatePicker pressed-control effect.
- Editable Start Date rows show a capsule value and open a calendar popover without the compact DatePicker pressed-control effect.
- Reminders are generated only for the next 2 days.
- A reminder is not created for a day that is already completed or taken.
- A reminder is not created for a day that is already skipped.
- A reminder is not created for a day earlier than `startDate`.
- If 3 or more reminders share the same scheduled time, they may be aggregated into a summary notification.

## Reminder Action Rules

- Habit notification actions are `Mark as Completed` and `Mark as Skipped`.
- Pill notification actions are `Mark as Taken`, `Mark as Skipped`, and `Remind me in 10 mins`.
- Reminder actions resolve the logical day from `localDate` in the payload first.
- If `localDate` is missing or invalid, they fall back to the notification delivery date.

## Pill Remind Later Rules

- `Remind me in 10 mins` creates a new Pill reminder 10 minutes from now.
- Snoozed Pill reminders are kept separate from regular scheduled reminders.
- Global Pill reschedule removes only regular Pill reminders.
- Snoozed Pill reminders are removed when:
  - the same pill/day is taken
  - the same pill/day is skipped
  - the pill is deleted

## Badge Rules

- Badge count equals overdue Habits plus overdue Pills.
- An item is overdue when the latest due scheduled day has no positive or skipped state.
- Overdue labels are `Today`, `Yesterday`, or a date like `26.04.2026`.
- Badge calculation is derived state only. Reconciliation does not persist skipped rows for overdue catch-up.
- Restore/history gaps are not badge-counted overdue unless they are also the latest due scheduled day.
- Dashboard cards do not count an active overdue day as a missing-history gap while it remains the latest due scheduled day; Details and Edit still surface a past active overdue day as requiring review.
- Badge refresh can reuse already-loaded dashboard projections and only writes the app icon badge when the count changes, unless a force apply is requested.

## Backup Rules

- Backup is JSON encoded and gzip compressed.
- Main backup file is `LoonyBear.json.gz`.
- Previous backup file is `LoonyBear.previous.json.gz`.
- Restore snapshot file is `LoonyBear.restore-snapshot.json.gz`.
- Backup includes app appearance settings: selected theme mode and selected app tint.
- Restore validates schema and payload integrity before replacing the store.
- Restore applies backed-up theme mode and app tint when the backup contains app settings.
- Legacy backups without app settings keep the current theme mode and app tint unchanged.
- If snapshot payload creation fails because the local store is corrupted, restore can continue.
- If snapshot writing fails, restore aborts.
- Backup screen shows `Last backup`, `Total size`, and `Folder`.
- `Last backup` uses the same color as its cloud status icon: green when a readable backup exists and red when it does not.
- Backup actions are full-width capsule buttons. Create Backup uses the primary label color, and Restore Backup stays system red.
- Create Backup and Restore Backup confirmations use system alerts, not popover confirmation dialogs. Alert action labels are shortened to `Backup` and `Restore`.
- Choosing a folder does not restore data automatically.
- Backup screen derives its action notice from the actual selected folder state, not from a temporary screen session flag.
- Each readable backup file is fingerprinted from its compressed data.
- After Create Backup succeeds, the current backup fingerprint is remembered as created by this app install.
- After Restore Backup succeeds, the restored backup fingerprint is remembered as restored by this app install.
- Backup feedback appears as dismissible floating banners pinned near the bottom of the visible screen. Banners auto-hide after 4 seconds and clear when leaving the Backup screen.
- If the selected folder has no readable backup, Backup shows `No backup found. Tap Create Backup to save one.` as a blue floating informational banner.
- If the selected folder has a readable backup whose fingerprint has not been created or restored by this app install, Backup shows `Backup found. Tap Restore Backup to apply it.` as a blue floating informational banner and disables `Create Backup`.
- If the selected folder has the backup that was created or restored by this app install, Backup does not show a restore-needed action notice.
- If backup files exist but cannot be read, Backup shows `Backup file can’t be read. Choose another folder or create a new backup.` as a red floating banner.
- Successful `Backup Created` and `Restore Complete` feedback uses green floating success banners.

## Appearance Rules

- Settings supports theme mode selection: System, Light, and Dark.
- Settings supports app color selection: Blue, Indigo, Green, and Amber.
- Blue is the default app tint and appears first in the palette.
- Tints apply to supported app accent surfaces.
- Page backgrounds stay on the system grouped background; the tint background wash is currently disabled.
- Legacy stored tint values `default`, `gray`, `yellow`, `cyan`, `teal`, `brown`, `red`, and `white` are treated as Blue.
- Editable schedule checkmarks, Settings app-row icons, and Calendar Taken/Completed markers use the selected app color.
- Read-only schedule checkmarks, scheduled-day calendar dots, skipped markers, overdue/warning colors, card Edit/Info swipe actions, backup action rows, toggles, and segmented picker selection remain fixed system colors.

## Calendar UI Rules

- Custom month calendars are navigated only with the left and right header arrows.
- Custom month calendars do not support horizontal swipe paging.
- Custom month calendars keep a stable six-week grid footprint while changing vertical spacing between week rows for shorter months.
- Habit and Pill Details/Edit calendars show scheduled days with a small tertiary system-gray dot under the date number, derived from the effective schedule history.
- History review warnings are floating overlays instead of inline calendar rows, so resolving the last missing day does not move the calendar.

## Device UI Rules

- iPhone is locked to portrait orientation.
- iPad supports portrait and landscape orientations.
- Settings child screens use the custom tinted back button while preserving the native left-edge swipe-back gesture.
