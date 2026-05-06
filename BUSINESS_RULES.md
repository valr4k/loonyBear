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
- Habit name, schedule, end-date, create-limit, and unexpected action errors are shown with dismissible floating warning banners instead of inline form banners.
- Create Habit allows a start date from the last 5 years through the end of the second next calendar month.
- A future Habit remains in its normal Build or Quit dashboard section, but it has no today action/status, no overdue state, no notifications, and no history review before its start date.
- Future Habit cards show `Starts 03 May 2026` style dates.
- Habits use an `End Repeat` options row and, only when `On Date` is selected, an `End Date` date row. If no end date is selected, `End Repeat` displays `Never`.
- Habits can be manually archived from Edit. Archived Habits move to the separate Habit Archive page and do not produce today actions, overdue state, notifications, badge count, or history review. Archived Habits preserve their stored reminder, repeat, end date, and history as historical data.
- My Habits shows the Archive toolbar button only when at least one archived Habit exists. The button opens archived Habits without Build/Quit sections.

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
- Habit card clear-state swipe uses the `arrow.uturn.backward` system symbol.
- Future and archived Habit cards do not expose day-state leading swipe actions.
- Habit Details shows the same dismissible floating warning banner while any past scheduled day is missing. If the only missing day is the active overdue day, the warning uses the short `Finish updating overdue days on the Edit screen.` copy; otherwise it uses `Finish updating past days on the Edit screen.`
- Saving Edit Habit does not auto-fill missing past days; the user must choose the state.
- Edit Habit delete confirmation uses a system alert with `Cancel` and destructive `Delete` actions.
- Edit Habit does not expose `Start Date`.
- If the Repeat rule is changed for an active Habit, the app does not show an Apply From field. The new schedule version receives a hidden `effectiveFrom` based on `max(today, startDate)`. The technical maximum is the end of the second next calendar month. The current UI selects the lower bound, so the normal saved value is `max(today, startDate)`. If an out-of-range internal draft value ever appears, the repository falls back to the lower bound. This hidden resolver does not check whether that date matches the new Repeat and does not inspect explicit completed/skipped states; actual scheduled days are derived later by normal schedule applicability.
- Edit Habit shows Archive below Delete only for active Habits. Archive uses the confirmation `Archive Habit?` / `This habit will move to Archive.`
- Archived Habits do not expose Edit or Restore. They can be opened from the Habit Archive page into read-only Details, where Delete is available at the bottom with confirmation.

## Habit Streak Rules

- A completed day increments streak.
- A missed unscheduled day does not reset streak.
- A missed scheduled day in the past resets streak.
- An uncompleted scheduled today does not reset current streak yet.
- Longest streak uses the same logic across the full recorded timeline.

## Pills

- Pills are shown in one ordered dashboard list that is later split into `Today` and `Pending` sections in the UI.
- Pill name and dosage must not be empty.
- A valid Repeat rule must be selected. `Repeat = Never` is valid for Pills.
- The app allows at most 20 Pills.
- Pill name, dosage, schedule, end-date, create-limit, and unexpected action errors are shown with dismissible floating warning banners instead of inline form banners.
- Create Pill allows a start date from the last 5 years through the end of the second next calendar month.
- A future Pill appears in Pending, but it has no today action/status, no overdue state, no notifications, and no history review before its start date.
- A Pill day can be in one of 3 stored states:
  - taken
  - skipped
  - unset
- A skipped Pill day does not count toward total taken days.
- Taking a Pill on a day that was previously skipped overwrites the skipped state with a positive state.
- Clearing today removes the stored row for today.
- Pill order is persisted through `sortOrder`.
- Future Pill cards show `Starts 03 May 2026` style dates.
- Pills use an `End Repeat` options row and, only when `On Date` is selected, an `End Date` date row. If no end date is selected, `End Repeat` displays `Never`.
- Pills can use `Repeat = Never`, which means one scheduled day on the Pill start date. Habits do not expose this option.
- Pills can be manually archived from Edit. Archived Pills move to the separate Pill Archive page and do not produce today actions, overdue state, notifications, badge count, or history review. Archived Pills preserve their stored reminder, repeat, end date, and history as historical data.
- My Pills shows the Archive toolbar button only when at least one archived Pill exists. The button opens archived Pills without Today/Pending sections.

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
- Pill card clear-state swipe uses the `arrow.uturn.backward` system symbol.
- Future and archived Pill cards do not expose day-state leading swipe actions.
- Pill Details shows the same dismissible floating warning banner while any past scheduled day is missing. If the only missing day is the active overdue day, the warning uses the short `Finish updating overdue days on the Edit screen.` copy; otherwise it uses `Finish updating past days on the Edit screen.`
- Saving Edit Pill does not auto-fill missing past days; the user must choose the state.
- Edit Pill delete confirmation uses a system alert with `Cancel` and destructive `Delete` actions.
- Edit Pill does not expose `Start Date`.
- If the Repeat rule is changed for an active Pill, the app does not show an Apply From field. The new schedule version receives a hidden `effectiveFrom` based on `max(today, startDate)`. The technical maximum is the end of the second next calendar month. The current UI selects the lower bound, so the normal saved value is `max(today, startDate)`. If an out-of-range internal draft value ever appears, the repository falls back to the lower bound. This hidden resolver does not check whether that date matches the new Repeat and does not inspect explicit taken/skipped states; actual scheduled days are derived later by normal schedule applicability.
- Edit Pill shows Archive below Delete only for active Pills. Archive uses the confirmation `Archive Pill?` / `This pill will move to Archive.`
- Archived Pills do not expose Edit or Restore. They can be opened from the Pill Archive page into read-only Details, where Delete is available at the bottom with confirmation.

## Schedule Rules

- Schedules are represented by `ScheduleRule`: weekday rules, `Every N days` interval rules, or `Never repeat` for Pills.
- Editing schedule days appends a new schedule version row instead of rewriting older versions.
- The current schedule is the latest schedule version whose `effectiveFrom` is not later than the relevant day.
- If a Repeat change is saved from Edit, `effectiveFrom` is resolved internally and is not editable in the UI. The base date is `max(today, startDate)`. The technical maximum is the end of the second next calendar month. The resolver normalizes the selected/base date, raises values earlier than the minimum to the minimum, and rejects values later than the maximum; repository update falls back to the minimum if resolution fails. The resolver is intentionally schedule-agnostic: it does not move to the next matching weekday and does not skip days that already have explicit history state. `Every N days` schedules use this hidden `effectiveFrom` as the interval anchor.
- Calendar preview drops replaced future schedule versions so visible dots match the post-save schedule.
- Schedule rules are selected from the pushed Repeat screen using `Days` and `Interval` sections. `Days` supports weekday combinations, while `Interval` supports `Every N days`, limited to 2 through 5 days, and `Never` for Pills only.
- Weekday summaries are canonicalized as Daily for Monday through Sunday, Weekdays for Monday through Friday, Weekends for Saturday and Sunday, `Weekly on Mon` style labels for one selected weekday, and abbreviated day lists such as `Mon, Wed, Fri` for other weekday combinations.
- Create and Edit screens edit Repeat from a pushed `Repeat` screen inside the sheet.
- The Repeat screen has `Days` and `Interval` sections.
- `Use schedule for history?` is no longer exposed in the UI. New items still use schedule-based history generation.
- Details screens show Repeat as read-only text and do not open a schedule picker.
- Schedule ordering uses:
  - `effectiveFrom`
  - then `version`
  - then `createdAt`

## End Repeat, End Date, and Archive Rules

- End Date is optional for both Pills and Habits.
- The visible Schedule UI splits the concept into two rows: `End Repeat` chooses `Never` or `On Date`; the `End Date` picker row appears only when `On Date` is selected.
- If a date is selected, the final active scheduled day is the last scheduled day on or before that date.
- The End Date picker lower bound is `max(today, startDate)`. The native picker binding keeps visible picker values inside that range while editing, but Save does not silently raise End Date during `normalizedDraft()`.
- A selected End Date is valid only when at least one scheduled day exists between the active lower bound and the selected date. If no scheduled day exists in that range, Save stays disabled and a dismissible floating warning says `End date must be on or after the first scheduled day.`
- End Date validation is run on Create and Edit for both domains. Pill `Repeat = Never` ignores End Date validation because the End Date is cleared and disabled for one-time Pills.
- Once the final scheduled day has a completed/taken or skipped state, the item is archived automatically without confirmation.
- If the final scheduled day is still empty, the item remains active and can become overdue with the same `Today`, `Yesterday`, or date labels as other overdue items.
- Manual Archive asks for confirmation.
- Manual Archive does not require the current Edit form to be valid.
- Manual and automatic archive only toggle `isArchived`, update `updatedAt`, and clear stale overdue anchors. They preserve reminder settings, Repeat, End Repeat/End Date, and history rows as historical data.
- Restore is not available for archived items. For a new cycle, the user creates a new item.
- `Repeat = Never` for Pills behaves like a one-time schedule on the start date. After that day is taken or skipped, the Pill archives automatically. If it is not acted on, it stays active and can become overdue.

## Reminder Rules

- Reminders are scheduled only when enabled and authorized.
- Notification permission must be requested on first launch
- Turning on a reminder from Create/Edit requests notification authorization when needed.
- If notification access is denied, the reminder toggle is turned back off and the app shows an alert with an `Open Settings` action instead of an inline validation banner.
- iOS only shows the system notification permission prompt once. After the user chooses `Don’t Allow`, the app can only route the user to Settings.
- Reminder time rows use the native compact system time picker when reminders are enabled.
- Editable Start Date rows use the native compact system date picker on Create screens.
- Schedule blocks keep native compact date/time pickers, the native End Repeat options popover, and the pushed Repeat navigation, but protect them from simultaneous UIKit presentations.
- While the End Repeat options popover is open, neighboring compact date/time picker rows ignore picker hit-testing.
- Time and End Repeat touch-downs briefly block the opposite presentation path for 200 ms so same-frame Time picker + End Repeat taps cannot present two UIKit controllers at once.
- This touch-down protection is implemented as a window-level observer that does not cancel touches or steal Schedule card scroll gestures.
- Repeat navigation dismisses any open End Repeat popover and briefly blocks End Repeat option presentation so the popover cannot remain over the pushed Repeat screen.
- The Start Date picker participates in the Schedule block exclusive-touch scope but does not install an extra touch-down gesture.
- Reminders are generated only for the next 2 days.
- A reminder is not created for a day that is already completed or taken.
- A reminder is not created for a day that is already skipped.
- A reminder is not created for a day earlier than `startDate`.
- A reminder is not created for an archived item.
- A reminder is not created after the item's final scheduled day.
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
- Overdue labels are `Today`, `Yesterday`, or a date like `03 May 2026`.
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
- `Last backup` uses `03 May at 22:35` style date formatting.
- Backup actions are full-width capsule buttons. Create Backup uses the primary label color, and Restore Backup stays system red.
- Create Backup and Restore Backup confirmations use system alerts, not popover confirmation dialogs. Alert action labels are shortened to `Backup` and `Restore`.
- The Home Screen app icon exposes a dynamic `Create Backup` quick action after the app has launched. It opens Settings > Backup only; it does not start backup creation.
- Choosing a folder does not restore data automatically.
- Backup screen derives its action notice from the actual selected folder state, not from a temporary screen session flag.
- Each readable backup file is fingerprinted from its compressed data.
- After Create Backup succeeds, the current backup fingerprint is remembered as created by this app install.
- After Restore Backup succeeds, the restored backup fingerprint is remembered as restored by this app install.
- Backup feedback appears as dismissible floating banners pinned near the bottom of the visible screen. Banners auto-hide after 4 seconds and clear when leaving the Backup screen.
- If the selected folder has no readable backup, Backup shows `No backup found. Create one to get started.` as a blue floating informational banner.
- If the selected folder has a readable backup whose fingerprint has not been created or restored by this app install, Backup shows `Backup available. Restore when ready.` as a blue floating informational banner and disables `Create Backup`.
- If the selected folder has the backup that was created or restored by this app install, Backup does not show a restore-needed action notice.
- If backup files exist but cannot be read, Backup shows `Backup can’t be read. Choose another location or create a new one.` as a red floating banner.
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
