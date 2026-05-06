# LoonyBear Core Data Model

## Source of Truth

Core Data stores facts, not UI-specific projections.

Stored facts include:
- habits
- pills
- schedule versions
- completion / intake rows
- reminder values
- history mode values

Derived values such as dashboard sections, streaks, overdue counts, totals, and schedule summaries are computed at read time.

## Entities

### `Habit`
Purpose:
- root record for a tracked habit

Important fields:
- `id`
- `typeRaw`
- `name`
- `sortOrder`
- `startDate`
- `endDate`
- `isArchived`
- `historyModeRaw`
- `reminderEnabled`
- `reminderHour`
- `reminderMinute`
- `createdAt`
- `updatedAt`
- `version`

Relationships:
- `completions -> HabitCompletion`
- `scheduleVersions -> HabitScheduleVersion`

### `HabitCompletion`
Purpose:
- one day-level Habit history row

Important fields:
- `id`
- `habitID`
- `localDate`
- `sourceRaw`
- `createdAt`

Meaning:
- positive `sourceRaw` means completed
- `skipped` means skipped
- no row means unset day

### `HabitScheduleVersion`
Purpose:
- immutable history of Habit schedule changes

Important fields:
- `id`
- `habitID`
- `weekdayMask`
- `scheduleKindRaw`
- `intervalDays`
- `effectiveFrom`
- `createdAt`
- `version`

### `Pill`
Purpose:
- root record for a tracked pill

Important fields:
- `id`
- `name`
- `dosage`
- `detailsText`
- `sortOrder`
- `startDate`
- `endDate`
- `isArchived`
- `historyModeRaw`
- `reminderEnabled`
- `reminderHour`
- `reminderMinute`
- `createdAt`
- `updatedAt`
- `version`

Relationships:
- `intakes -> PillIntake`
- `scheduleVersions -> PillScheduleVersion`

### `PillIntake`
Purpose:
- one day-level Pill history row

Important fields:
- `id`
- `pillID`
- `localDate`
- `sourceRaw`
- `createdAt`

Meaning:
- positive `sourceRaw` means taken
- `skipped` means skipped
- no row means unset day

### `PillScheduleVersion`
Purpose:
- immutable history of Pill schedule changes

Important fields:
- `id`
- `pillID`
- `weekdayMask`
- `scheduleKindRaw`
- `intervalDays`
- `effectiveFrom`
- `createdAt`
- `version`

## Stored Model Rules

- `startDate` is stored as a normalized start-of-day date.
- `endDate` is optional and stored as a normalized start-of-day date when present. The UI labels the option row as `End Repeat`; the stored fact is still the optional `endDate`.
- `isArchived` marks items that have moved to the separate Archive pages and should not produce active today actions, overdue state, reminders, badge count, or history review.
- Archiving does not delete or rewrite reminder settings, repeat settings, end date, or history rows. Those stored values remain historical facts for archived Details and backups.
- Reminder times are stored as hour and minute integer components.
- Habit and Pill history mode are stored in `historyModeRaw`.
- Schedule changes are append-only through new version rows.
- Create inserts the initial schedule version with `effectiveFrom = startDate`.
- Edit inserts a replacement schedule version only when Repeat changed. The hidden replacement `effectiveFrom` is based on `max(today, startDate)` and is bounded by the technical schedule-change window; current UI normally saves the lower bound, and out-of-range internal values fall back to the lower bound. It is not user-editable and is not moved to the next matching scheduled day.
- Schedule versions store `scheduleKindRaw`, `weekdayMask`, and `intervalDays` so both weekday rules and `Every N days` interval rules can round-trip through persistence and backup.
- Daily state is stored explicitly through completion / intake rows.
- Skipped days are stored explicitly, not inferred.

## Read-Time Derivation Rules

The app derives these values from stored facts:
- dashboard cards
- section grouping
- schedule summaries
- reminder eligibility
- overdue state
- streaks
- taken totals
- completed totals

## Validation Rules Applied While Reading

The code validates:
- `typeRaw`
- `historyModeRaw`
- `sourceRaw`
- `weekdayMask`
- reminder hour/minute ranges
- required fields on root and child rows

If validation fails in protected read paths, the app can raise a `DataIntegrityError` instead of silently producing an invalid projection.

## Backup Mapping

Backup serializes and restores:
- Habit
- HabitScheduleVersion
- HabitCompletion
- BackupAppSettings
- Pill
- PillScheduleVersion
- PillIntake

Both Habit and Pill backup payloads include stored `historyMode`.
Both Habit and Pill backup payloads include `endDate` and `isArchived`.
Schedule backup payloads include `scheduleKind` and `intervalDays` for interval and one-time repeat support.
`BackupAppSettings` stores the selected appearance mode and app tint. Legacy backups without this optional settings payload remain valid and do not overwrite the current appearance settings during restore.
