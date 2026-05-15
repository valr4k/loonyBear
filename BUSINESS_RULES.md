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
- Habit name fields use the shared `Name` placeholder and word-capitalization input behavior.
- At least one schedule day must be selected.
- The app allows at most 20 Habits.
- Habit name, schedule, end-date, create-limit, and unexpected action errors are shown with dismissible floating warning banners instead of inline form banners.
- Create Habit uses the native compact system date picker for Start Date with no app-level selectable range.
- A future Habit remains in its normal Build or Quit dashboard section, but it has no today action/status, no overdue state, no notifications, and no history review before its start date.
- Future Habit cards show `Starts 03 May 2026` style dates.
- Habits use an `End Repeat` options row and, only when `On Date` is selected, an `End Date` date row. If no end date is selected, `End Repeat` displays `Never`.
- Habits can be archived from active Habit Details. Archived Habits move to the separate Archive page and do not produce today actions, overdue state, notifications, badge count, or history review. They preserve their stored reminder, repeat, end date, and history as historical data.
- My Habits shows the Archive toolbar button only when at least one archived Habit exists. The button opens archived Habits without Build/Quit sections.

## Habit History Modes

- Every Habit stores a `historyMode`.
- `scheduleBased` means generated past history follows the schedule.
- `everyDay` means generated past history counts every day from `startDate` through yesterday.
- Missing-history review and active Details save validation require only past editable days that were scheduled by the effective schedule history.
- Dashboard cards exclude the active overdue day from missing-history review while it remains actionable overdue.
- Active Habit Details includes an active overdue day when that day is in the past, because past scheduled days should be resolved from the calendar surface.
- Active Details save validation includes an active overdue day when that day is in the past, because past scheduled days cannot be saved empty.
- Habit create, details loading, backup, and restore read the stored history mode. The current Habit Details UI does not display a dedicated history mode row and does not expose a history mode toggle.
- Saving active Habit Details preserves the stored history mode. Missing scheduled editable past days are not auto-filled; they block saving until the user chooses a state.

## Habit Create and Reconciliation

- Habit create inserts the root Habit row and an initial schedule version.
- After create, the repository generates completed history from `startDate` through yesterday.
- In `scheduleBased` mode, only scheduled days are generated.
- In `everyDay` mode, every day in that range is generated.
- Generated create-time history is stored as one cold schedule-aware range before the editable window plus monthly bucket state inside the editable window, not as one database row per generated day.
- The auto-filled completion source is `auto fill`.
- Habit reconciliation does not backfill missing past history.
- Habit reconciliation does not auto-skip overdue days.
- A scheduled day becomes due at its reminder time. If reminders are disabled, it becomes due at 00:00.
- The active overdue day is the latest due scheduled day only when that latest due day has no completed or skipped state.
- Empty due scheduled days before the active overdue day are history gaps, not skipped states.
- Stale notification actions for days that have already become history gaps are ignored and only dismiss the notification.
- Restore clears stale overdue anchors, but overdue and history gaps are derived from the restored schedule/history data.
- Existing completed states are preserved.
- Existing skipped states are preserved.

## Habit Edit Rules

- Habit history editing is limited to the last 30 days and never earlier than `startDate`.
- Today can be empty, completed, or skipped.
- Past editable scheduled Habit days must be explicitly completed or skipped before saving.
- Save is disabled while any past editable scheduled Habit day is empty.
- Missing past-day review is shown as a dismissible floating warning banner pinned near the bottom of active Habit Details. It does not take space in the calendar layout and disappears once all required past scheduled days are resolved.
- If the only missing Habit day is the active overdue day, the floating warning asks the user to choose `Completed` or `Skipped` for the overdue scheduled day.
- Missing past-day warning copy does not list the missing dates.
- Habit cards show a warning status instead of today's completed/skipped status while recent history needs review.
- Habit cards do not show the history warning only because of the active overdue day; they show it alongside overdue only when some other required past scheduled day is empty.
- Tapping an active Habit card opens the editable `Habit Details` sheet.
- Habit cards do not expose trailing swipe actions. Delete is not available from card swipe actions.
- Habit card clear-state swipe uses the `arrow.uturn.backward` system symbol.
- Future and archived Habit cards do not expose day-state leading swipe actions.
- Active Habit Details is the current editable sheet opened from an active Habit card. It shows the same dismissible floating warning banner while any past scheduled day is missing.
- If the only missing Habit day is the active overdue day, the current editable sheet uses `Mark each overdue day as Completed or Skipped.`
- If any other past scheduled Habit day is missing, the current editable sheet uses `Mark all past days as Completed or Skipped.`
- The shorter `Finish updating overdue days.` and `Finish updating past days.` strings are retained only for the older `HabitDetailsView` calendar-review helper and are not the current dashboard card tap flow.
- Saving active Habit Details does not auto-fill missing past days; the user must choose the state.
- Active Habit Details exposes two destructive actions at the bottom: `Archive` and `Delete`.
- `Archive` uses the confirmation `Archive this Habit?` / `This Habit will be moved to Archive.` and moves the Habit to Archive without requiring the current form edits to be valid.
- Active `Delete` is permanent and uses `Permanently delete this Habit?` / `This Habit will be permanently deleted.`
- Habit Details shows `Start Date` as read-only; Start Date is not editable after create.
- If the Repeat rule is changed for an active Habit, the app does not show an Apply From field. The new schedule version receives a hidden `effectiveFrom` based on `max(today, startDate)`. The technical maximum is the end of the second next calendar month. The current UI selects the lower bound, so the normal saved value is `max(today, startDate)`. If an out-of-range internal draft value ever appears, the repository falls back to the lower bound. This hidden resolver does not check whether that date matches the new Repeat and does not inspect explicit completed/skipped states; actual scheduled days are derived later by normal schedule applicability.
- Archived Habits open from Archive into a read-only item screen. The read-only screen shows `Restore` and `Delete` at the bottom.
- Archived `Delete` is permanent and uses `Permanently delete this Habit?` / `This Habit will be permanently deleted.`
- `Restore` opens a Restore Draft screen where the Habit is still archived until Restore succeeds. The user can edit the new cycle before returning it to the active dashboard.

## Habit Streak Rules

- A completed day increments streak.
- A missed unscheduled day does not reset streak.
- A missed scheduled day in the past resets streak.
- An uncompleted scheduled today does not reset current streak yet.
- Longest streak uses the same logic across the full recorded timeline.

## Pills

- Pills are shown in one ordered dashboard list that is later split into `Today` and `Pending` sections in the UI.
- Pill name and dosage must not be empty.
- Pill name fields use the shared `Name` placeholder and word-capitalization input behavior.
- Pill description fields use the optional `Add notes…` placeholder.
- A valid Repeat rule must be selected. `Repeat = Never` is valid for Pills.
- The app allows at most 20 Pills.
- Pill name, dosage, schedule, end-date, create-limit, and unexpected action errors are shown with dismissible floating warning banners instead of inline form banners.
- Create Pill uses the native compact system date picker for Start Date with no app-level selectable range.
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
- Pills can be archived from active Pill Details. Archived Pills move to the separate Archive page and do not produce today actions, overdue state, notifications, badge count, or history review. They preserve their stored reminder, repeat, end date, and history as historical data.
- My Pills shows the Archive toolbar button only when at least one archived Pill exists. The button opens archived Pills without Today/Pending sections.

## Pill History Modes

- Every Pill stores a `historyMode`.
- `scheduleBased` means generated past history follows the schedule.
- `everyDay` means generated past history counts every day from `startDate` through yesterday.
- Missing-history review and active Details save validation require only past editable days that were scheduled by the effective schedule history.
- Dashboard cards exclude the active overdue day from missing-history review while it remains actionable overdue.
- Active Pill Details includes an active overdue day when that day is in the past, because past scheduled days should be resolved from the calendar surface.
- Active Details save validation includes an active overdue day when that day is in the past, because past scheduled days cannot be saved empty.
- Pill create, details loading, backup, and restore read the stored history mode. The current Pill Details UI does not display a dedicated history mode row and does not expose a history mode toggle.
- Saving active Pill Details preserves the stored history mode. Missing scheduled editable past days are not auto-filled; they block saving until the user chooses a state.

## Pill Create and Reconciliation

- Repository create generates taken history from `startDate` through yesterday.
- In `scheduleBased` mode, generated `takenDays` include only scheduled days.
- In `everyDay` mode, generated `takenDays` include all days in that range.
- Repository create writes generated `takenDays` as one cold schedule-aware range before the editable window plus monthly bucket state inside the editable window, not as one database row per generated day.
- Today is not prefilled.
- Pill reconciliation does not backfill missing past history.
- Pill reconciliation does not auto-skip overdue days.
- A scheduled day becomes due at its reminder time. If reminders are disabled, it becomes due at 00:00.
- The active overdue day is the latest due scheduled day only when that latest due day has no taken or skipped state.
- Empty due scheduled days before the active overdue day are history gaps, not skipped states.
- Stale notification actions for days that have already become history gaps are ignored and only dismiss the notification.
- Restore clears stale overdue anchors, but overdue and history gaps are derived from the restored schedule/history data.
- Existing taken states are preserved.
- Existing skipped states are preserved.

## Pill Edit Rules

- Pill history editing is limited to the last 30 days and never earlier than `startDate`.
- Today can be empty, taken, or skipped.
- Past editable scheduled Pill days must be explicitly taken or skipped before saving.
- Save is disabled while any past editable scheduled Pill day is empty.
- Missing past-day review is shown as a dismissible floating warning banner pinned near the bottom of active Pill Details. It does not take space in the calendar layout and disappears once all required past scheduled days are resolved.
- If the only missing Pill day is the active overdue day, the floating warning asks the user to choose `Taken` or `Skipped` for the overdue scheduled day.
- Missing past-day warning copy does not list the missing dates.
- Pill cards show a warning status instead of today's taken/skipped status while recent history needs review.
- Pill cards do not show the history warning only because of the active overdue day; they show it alongside overdue only when some other required past scheduled day is empty.
- Tapping an active Pill card opens the editable `Pill Details` sheet.
- Pill cards do not expose trailing swipe actions. Delete is not available from card swipe actions.
- Pill card clear-state swipe uses the `arrow.uturn.backward` system symbol.
- Future and archived Pill cards do not expose day-state leading swipe actions.
- Active Pill Details is the current editable sheet opened from an active Pill card. It shows the same dismissible floating warning banner while any past scheduled day is missing.
- If the only missing Pill day is the active overdue day, the current editable sheet uses `Mark each overdue day as Taken or Skipped.`
- If any other past scheduled Pill day is missing, the current editable sheet uses `Mark all past days as Taken or Skipped.`
- The shorter `Finish updating overdue days.` and `Finish updating past days.` strings are retained only for the older `PillDetailsView` calendar-review helper and are not the current dashboard card tap flow.
- Saving active Pill Details does not auto-fill missing past days; the user must choose the state.
- Active Pill Details exposes two destructive actions at the bottom: `Archive` and `Delete`.
- `Archive` uses the confirmation `Archive this Pill?` / `This Pill will be moved to Archive.` and moves the Pill to Archive without requiring the current form edits to be valid.
- Active `Delete` is permanent and uses `Permanently delete this Pill?` / `This Pill will be permanently deleted.`
- Pill Details shows `Start Date` as read-only; Start Date is not editable after create.
- If the Repeat rule is changed for an active Pill, the app does not show an Apply From field. The new schedule version receives a hidden `effectiveFrom` based on `max(today, startDate)`. The technical maximum is the end of the second next calendar month. The current UI selects the lower bound, so the normal saved value is `max(today, startDate)`. If an out-of-range internal draft value ever appears, the repository falls back to the lower bound. This hidden resolver does not check whether that date matches the new Repeat and does not inspect explicit taken/skipped states; actual scheduled days are derived later by normal schedule applicability.
- Archived Pills open from Archive into a read-only item screen. The read-only screen shows `Restore` and `Delete` at the bottom.
- Archived `Delete` is permanent and uses `Permanently delete this Pill?` / `This Pill will be permanently deleted.`
- `Restore` opens a Restore Draft screen where the Pill is still archived until Restore succeeds. The user can edit the new cycle before returning it to the active dashboard.

## Events

- Events live on a separate `Events` tab between `My Habits` and `Settings`.
- Events are not Habits or Pills and do not participate in reminders, notifications, overdue state, badge count, history review, Archive, Restore, widgets, or streak calculation.
- Event name fields use the shared `Name` placeholder and word-capitalization input behavior.
- The Events dashboard has one global empty state when no Events exist:
  - `No Events Yet`
  - `Create your first event to get started.`
- The `Countdown` section is shown only when at least one Countdown event exists.
- The `Count Up` section is shown only when at least one Count Up event exists.
- Event cards use the same card language as Pill/Habit dashboard cards.
- Event cards show:
  - name on the left
  - duration on the right
- Event duration is formatted with the same compact duration style used by streak/taken totals, such as `2yr 2mo 7d`.
- Event duration normally uses the selected app tint.
- Countdown events count full local calendar days from today to the event date.
- Countdown date can be today or in the future when saving. Past dates are invalid.
- When a Countdown event reaches or passes its date, it remains on screen and shows `0d` in red forever.
- Count Up events count the selected date as day 1.
- Count Up date can be today or in the past when saving. Future dates are invalid.
- Count Up events continue counting indefinitely until the user deletes them.
- Add new Event defaults:
  - mode: Countdown
  - date: today
- Switching Event mode keeps the draft valid:
  - Countdown to Count Up moves a future date to today
  - Count Up to Countdown moves past dates to today
- Event validation uses dismissible floating warning banners:
  - `Countdown date must be in the future.`
  - `Count Up date must be in the past.`
- Event Details opens from tapping an Event card.
- Event Details is editable and has the same fields as Add new Event: name, mode, and date.
- Event Delete is permanent and uses the confirmation `Delete this Event?` / `This Event will be permanently deleted.`
- Events are never automatically deleted.

## Schedule Rules

- Schedules are represented by `ScheduleRule`: weekday rules, `Every N days` interval rules, or `Never repeat` for Pills.
- Editing schedule days appends a new schedule version row instead of rewriting older versions.
- The current schedule is the latest schedule version whose `effectiveFrom` is not later than the relevant day.
- If a Repeat change is saved from active Details, `effectiveFrom` is resolved internally and is not editable in the UI. The base date is `max(today, startDate)`. The technical maximum is the end of the second next calendar month. The resolver normalizes the selected/base date, raises values earlier than the minimum to the minimum, and rejects values later than the maximum; repository update falls back to the minimum if resolution fails. The resolver is intentionally schedule-agnostic: it does not move to the next matching weekday and does not skip days that already have explicit history state. `Every N days` schedules use this hidden `effectiveFrom` as the interval anchor.
- Calendar preview drops replaced future schedule versions so visible dots match the post-save schedule.
- Schedule rules are selected from the pushed Repeat screen using `Days` and `Interval` sections. `Days` supports weekday combinations, while `Interval` supports `Every N days`, limited to 2 through 5 days, and `Never` for Pills only.
- Weekday summaries are canonicalized as Daily for Monday through Sunday, Weekdays for Monday through Friday, Weekends for Saturday and Sunday, `Weekly on Mon` style labels for one selected weekday, and abbreviated day lists such as `Mon, Wed, Fri` for other weekday combinations.
- Create screens and active Details screens edit Repeat from a pushed `Repeat` screen inside the sheet.
- The Repeat screen has `Days` and `Interval` sections.
- `Use schedule for history?` is no longer exposed in the UI. New items still use schedule-based history generation.
- Archive read-only item screens show Repeat as read-only text and do not open a schedule picker until the user enters Restore Draft.
- Schedule ordering uses:
  - `effectiveFrom`
  - then `version`
  - then `createdAt`

## End Repeat, End Date, Archive, and Restore Rules

- End Date is optional for both Pills and Habits.
- The visible Schedule UI splits the concept into two rows: `End Repeat` chooses `Never` or `On Date`; the `End Date` picker row appears only when `On Date` is selected.
- When `On Date` is selected for the first time on Create, the default End Date value is today, not the selected Start Date.
- If a date is selected, the final active scheduled day is the last scheduled day on or before that date.
- The End Date row uses the native compact system date picker with no app-level selectable range. Save does not silently raise End Date during `normalizedDraft()`.
- A selected End Date is valid only when it is not in the past and at least one scheduled day exists between the active lower bound and the selected date. If the selected date is earlier than local today, Save stays disabled and a dismissible floating warning says `End date can’t be in the past.` If the selected date is not in the past but the range contains no scheduled day, Save stays disabled and the warning says `End date must include at least one scheduled day.`
- End Date validation is run on Create and active Details for both domains. Pill `Repeat = Never` ignores End Date validation because the End Date is cleared and disabled for one-time Pills.
- Once the final scheduled day has a completed/taken or skipped state, the item moves to Archive automatically without confirmation.
- If the final scheduled day is still empty, the item remains active and can become overdue with the same `Today`, `Yesterday`, or date labels as other overdue items.
- Manual Archive asks for confirmation.
- Manual Archive does not require the current Details form to be valid.
- Manual Archive and automatic Archive set `isArchived = true`, store `archivedAt`, update `updatedAt`, and clear stale overdue anchors. They preserve reminder settings, Repeat, End Repeat/End Date, and stored history as historical data.
- Archived items are excluded from notifications, badge count, today actions, overdue state, and missing-history review.
- Archive pages list archived cards without Today/Pending or Build/Quit sections. The Archive toolbar button appears only when at least one archived item exists for that dashboard.
- Restore closes the read-only Archive item screen and opens a separate Restore Draft screen. Until the Restore Draft screen is saved, the stored item remains archived.
- Restore Draft shows the same edit-like layout plus an editable `Active From` row under read-only Start Date.
- `Active From` defaults to today.
- `Active From` minimum is `max(archivedAt, today - 29 days)`. This gives the user up to the normal 30-day editable window including today, but never allows Active From before the archive date.
- `Active From` can be the archive date, any later date, today, or a future date.
- In Restore Draft, End Repeat defaults to `Never` and End Date is cleared. The read-only archived screen still shows the stored historical End Repeat/End Date until Restore Draft starts.
- The Restore Draft screen uses the normal `Save` action. When Save succeeds, the app saves the draft edits, sets `isArchived = false`, clears `archivedAt`, writes `activeFrom`, and inserts a new schedule version effective from Active From.
- Before writing the new Restore gap, Restore removes archived history states on and after Active From. This prevents stale future Archived days from an earlier Restore attempt from staying inside the new active cycle.
- Restore writes `archived` history states from `archivedAt` through the day before Active From. If Active From is the archive day, this gap is empty and no archived states are created.
- Restore writes archived gap rows only into empty days. Existing Completed/Taken/Skipped rows in the archive gap are preserved and continue to count normally.
- Archived history states never count as Completed, Taken, or Skipped, and they are never editable.
- Archived history states appear in custom calendars as quiet system-gray circles that do not use the app tint.
- If Active From is in the past, scheduled days from Active From through yesterday that are still empty are auto-filled as Completed/Taken with source `restore`, matching the app's existing historical start-date autofill behavior.
- After Restore, editable history starts from Active From inside the normal editable window. Days before Active From remain historical and are not editable for the new cycle.
- If Active From is today, the item returns to the active dashboard immediately. If Active From is in the future, Pills go to Pending and Habits stay in Build/Quit without today action/status, overdue state, notifications, or history review before Active From.
- If the user changes tabs after tapping Restore but before the Restore Draft sheet opens, the pending Restore Draft is cancelled.
- Manual and automatic Archive use the actual archive day as `archivedAt`. Auto Archive does not backdate `archivedAt` to the logical End Date.
- `Repeat = Never` for Pills behaves like a one-time schedule on the start date. After that day is taken or skipped, the Pill moves to Archive automatically. If it is not acted on, it stays active and can become overdue.

## Reminder Rules

- Reminders are scheduled only when enabled and authorized.
- Notification permission must be requested on first launch
- Turning on a reminder from Create or active Details requests notification authorization when needed.
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
- Badge calculation is derived state only. Reconciliation does not persist skipped states for overdue catch-up.
- Restore/history gaps are not badge-counted overdue unless they are also the latest due scheduled day.
- Dashboard cards do not count an active overdue day as a missing-history gap while it remains the latest due scheduled day; active Details still surface a past active overdue day as requiring review.
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
- Backup screen shows `Last backup`, `Total size`, `Folder`, and `Auto Backup`.
- Settings shows the Backup destination with the subtitle `Manual and automatic backups`.
- `Last backup` uses the same color as its cloud status icon: green when a readable backup exists and red when it does not.
- `Last backup` uses `03 May at 22:35` style date formatting.
- `Auto Backup` is an explicit user toggle. The app never silently turns it on or off.
- Turning `Auto Backup` on with a usable folder selected enables automatic backups immediately.
- Turning `Auto Backup` on without a selected folder opens the folder picker. If the user chooses a folder successfully, Auto Backup becomes On. If the picker is cancelled, Auto Backup remains Off.
- If the remembered folder later becomes unavailable, Auto Backup remains in the user's chosen On/Off state. Automatic backup attempts cannot complete until the folder is available again.
- Auto Backup writes the same backup files with the same schema and rotation as manual Create Backup.
- Auto Backup runs only when Auto Backup is On, the selected folder is accessible, data is dirty, and no other backup operation is already running.
- Auto Backup waits 20 seconds after an important data change; another change inside that window resets the timer.
- Auto Backup also checks for pending dirty data at app startup, foreground, and background.
- Auto Backup failures are silent outside the Backup screen. Dirty state remains pending and is retried later.
- Successful manual or automatic backup clears dirty state only when no newer change happened while the backup was running.
- Manual Create Backup remains available regardless of the Auto Backup toggle and has priority over automatic backup.
- Backup actions are full-width capsule buttons. Create Backup uses the primary label color, and Restore Backup stays system red.
- Create Backup and Restore Backup confirmations use system alerts, not popover confirmation dialogs. Alert action labels are shortened to `Backup` and `Restore`.
- The Home Screen app icon exposes a dynamic `Create Backup` quick action after the app has launched. It opens Settings > Backup only; it does not start backup creation.
- Auto Backup has no Home Screen quick action, app icon badge, toolbar badge, or dashboard banner.
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
- Read-only schedule checkmarks, scheduled-day calendar dots, skipped markers, overdue/warning colors, backup action rows, toggles, and segmented picker selection remain fixed system colors.

## Calendar UI Rules

- Custom month calendars are navigated only with the left and right header arrows.
- Custom month calendars do not support horizontal swipe paging.
- Custom month calendars keep a stable six-week grid footprint while changing vertical spacing between week rows for shorter months.
- Habit and Pill Details calendars show scheduled days with a small tertiary system-gray dot under the date number, derived from the effective schedule history.
- History review warnings are floating overlays instead of inline calendar rows, so resolving the last missing day does not move the calendar.

## Device UI Rules

- iPhone is locked to portrait orientation.
- iPad supports portrait and landscape orientations.
- Settings child screens use the custom tinted back button while preserving the native left-edge swipe-back gesture.
