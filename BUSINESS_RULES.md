# LoonyBear Business Rules

## Habits

- A habit belongs to one type: `build` or `quit`.
- Habits are shown in dashboard sections grouped by type.
- A habit may be completed, skipped, or unset for a given local day.
- A skipped day does not count toward streaks.
- Completing a habit on a day that was previously skipped overwrites the skipped state.
- Clearing today's state removes the stored daily record for that day.
- Habit names must not be empty.
- At least one schedule day must be selected.
- The app currently allows up to 20 habits.

## Pills

- Pills are shown in a single ordered dashboard list.
- A pill may be taken, skipped, or unset for a given local day.
- A skipped day does not count toward total taken days.
- Taking a pill on a day that was previously skipped overwrites the skipped state.
- Clearing today's state removes the stored daily record for that day.
- Pill order is persisted with `sortOrder`.

## Schedule Rules

- Schedules are represented by `WeekdaySet`.
- Editing schedule days appends a new schedule version.
- The latest effective schedule is used for current projections and reminders.
- Historical schedule versions matter for streak calculation.

## Editable History Rules

- Editing details can modify recent history only.
- The editable window is the last 30 days, capped by the item's `startDate`.
- Outside that window, history is preserved as-is.

## Streak Rules

- Streaks are derived from completion records plus schedule history.
- A missed scheduled day resets the running streak on the next local day.
- An uncompleted scheduled "today" does not reset the current streak yet.
- Longest streak is calculated across the full recorded timeline.

## Reminder Rules

- Reminders are scheduled only when enabled and authorized.
- Scheduling uses a short forward-looking window.
- Delivered notifications for an acted-on item/day are removed after completion or skip.
- When several items share the same reminder time, notifications may aggregate into a summary.

## Backup Rules

- Backup output is JSON encoded and gzip compressed.
- The latest backup is written as `LoonyBear.json.gz`.
- The previous primary backup is rotated to `LoonyBear.previous.json.gz`.
- Restore validates schema compatibility before replacing stored data.
- A restore snapshot is created before applying backup data.

## Projection Rules

- Core Data stores facts, not screen-specific state.
- Dashboard cards, streak values, overdue status, and schedule summaries are projections.
- Badge count is derived from projected overdue habits and pills.
