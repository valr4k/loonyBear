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
- `scheduleBased` means required past history follows the schedule.
- `everyDay` means required past history counts every past editable day.
- Habit create, edit, details, reconciliation, backup, and restore all read the stored history mode.

## Habit Create and Reconciliation

- Habit create inserts the root Habit row and an initial schedule version.
- After create, missing required past days are auto-filled as completed.
- The auto-filled completion source is `auto fill`.
- Habit reconciliation also inserts missing completed rows for required past days.
- Existing completed rows are preserved.
- Existing skipped rows are preserved.

## Habit Edit Rules

- Habit history editing is limited to the last 30 days and never earlier than `startDate`.
- Today can be empty, completed, or skipped.
- Past required editable Habit days are not allowed to stay empty after normalization.
- Habit past default normalization is positive, not skipped.

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
- `scheduleBased` means required past history follows the schedule.
- `everyDay` means required past history counts every past editable day.
- Pill create, edit, details, reconciliation, backup, and restore all read the stored history mode.

## Pill Create and Reconciliation

- Before repository create, the create screen generates `takenDays` from `startDate` through yesterday.
- In `scheduleBased` mode, generated `takenDays` include only scheduled days.
- In `everyDay` mode, generated `takenDays` include all days in that range.
- Repository create inserts `manual edit` intake rows for all generated `takenDays`.
- After create, remaining required past days are finalized as skipped.
- Pill reconciliation inserts missing skipped rows for required past days.
- Existing taken rows are preserved.
- Existing skipped rows are preserved.

## Pill Edit Rules

- Pill history editing is limited to the last 30 days and never earlier than `startDate`.
- Today can be empty, taken, or skipped.
- Past required editable Pill days are not allowed to stay empty after normalization.
- In `scheduleBased` mode, only required scheduled past editable days are finalized.
- In `everyDay` mode, all past editable days are finalized.

## Schedule Rules

- Schedules are represented by `WeekdaySet` bitmasks.
- Editing schedule days appends a new schedule version row instead of rewriting older versions.
- The current schedule is the latest schedule version whose `effectiveFrom` is not later than the relevant day.
- Schedule ordering uses:
  - `effectiveFrom`
  - then `version`
  - then `createdAt`

## Reminder Rules

- Reminders are scheduled only when enabled and authorized.
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
- An item is overdue only if it is scheduled today, its reminder time has passed, and today is neither positive nor skipped.

## Backup Rules

- Backup is JSON encoded and gzip compressed.
- Main backup file is `LoonyBear.json.gz`.
- Previous backup file is `LoonyBear.previous.json.gz`.
- Restore snapshot file is `LoonyBear.restore-snapshot.json.gz`.
- Restore validates schema and payload integrity before replacing the store.
- If snapshot payload creation fails because the local store is corrupted, restore can continue.
- If snapshot writing fails, restore aborts.
