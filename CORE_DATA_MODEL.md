# LoonyBear Core Data Model

## Source of Truth

Core Data stores facts, not UI-specific projections.

Stored facts include:
- habits
- pills
- events
- schedule versions
- monthly history buckets
- legacy completion / intake rows for migration and backup compatibility
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
- `activeFrom`
- `endDate`
- `isArchived`
- `archivedAt`
- `historyModeRaw`
- `reminderEnabled`
- `reminderHour`
- `reminderMinute`
- `createdAt`
- `updatedAt`
- `version`

Relationships:
- `historyBuckets -> HabitHistoryBucket`
- `historyRanges -> HabitHistoryRange`
- `completions -> HabitCompletion` legacy compatibility rows
- `scheduleVersions -> HabitScheduleVersion`

### `HabitHistoryBucket`
Purpose:
- editable-window Habit history storage
- one row per Habit and local calendar month

Important fields:
- `id`
- `habitID`
- `yearMonthKey`
- `positiveMask`
- `skippedMask`
- `archivedMask`
- `positiveCount`
- `skippedCount`
- `archivedCount`
- `createdAt`
- `updatedAt`

Meaning:
- bit 0 represents day 1 of the month, bit 1 represents day 2, and so on
- `yearMonthKey` is stored as `yyyyMM`, for example `202605`
- a bit in `positiveMask` means completed
- a bit in `skippedMask` means skipped
- a bit in `archivedMask` means the item was inactive in Archive on that day
- no bit in any mask means unset day
- masks for the same day must not overlap
- count fields are denormalized mirrors of the corresponding mask bit counts
- count fields are validated against masks during protected read and backup restore paths

### `HabitHistoryRange`
Purpose:
- cold historical Habit history storage for long, uniform generated ranges
- one row can represent many scheduled completed days before the editable window

Important fields:
- `id`
- `habitID`
- `startDate`
- `endDate`
- `stateRaw`
- `useScheduleForHistory`
- `scheduleKindRaw`
- `weekdayMask`
- `intervalDays`
- `anchorDate`
- `count`
- `createdAt`
- `updatedAt`

Meaning:
- `startDate` and `endDate` are inclusive normalized local days
- `stateRaw` uses the same semantic states as bucket masks: positive, skipped, archived
- generated create-time cold history currently writes positive ranges only
- `useScheduleForHistory`, schedule fields, and `anchorDate` describe which days inside the date range actually carry the state
- for Daily/every-day history, every day in the range carries the state
- for Weekly/interval history, only dates matching the stored schedule rule and anchor carry the state
- `count` stores the number of matching state days in the range and is validated against the schedule payload on protected reads and backup restore
- range rows must not overlap same-day bucket state for normal writes; bucket state wins if old or corrupted local data overlaps

### `HabitCompletion`
Purpose:
- legacy one day-level Habit history row

Important fields:
- `id`
- `habitID`
- `localDate`
- `sourceRaw`
- `createdAt`

Meaning:
- used only for old local data, old backups, corruption tests, and migration fallback
- valid rows are migrated into `HabitHistoryBucket`
- new repository writes must not create normal Habit history in this table
- if a bucket and a legacy row both exist for the same Habit/day, the bucket wins
- new day writes delete any same-day legacy rows after writing the bucket state

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
- `activeFrom`
- `endDate`
- `isArchived`
- `archivedAt`
- `historyModeRaw`
- `reminderEnabled`
- `reminderHour`
- `reminderMinute`
- `createdAt`
- `updatedAt`
- `version`

Relationships:
- `historyBuckets -> PillHistoryBucket`
- `historyRanges -> PillHistoryRange`
- `intakes -> PillIntake` legacy compatibility rows
- `scheduleVersions -> PillScheduleVersion`

### `PillHistoryBucket`
Purpose:
- editable-window Pill history storage
- one row per Pill and local calendar month

Important fields:
- `id`
- `pillID`
- `yearMonthKey`
- `positiveMask`
- `skippedMask`
- `archivedMask`
- `positiveCount`
- `skippedCount`
- `archivedCount`
- `createdAt`
- `updatedAt`

Meaning:
- bit 0 represents day 1 of the month, bit 1 represents day 2, and so on
- `yearMonthKey` is stored as `yyyyMM`, for example `202605`
- a bit in `positiveMask` means taken
- a bit in `skippedMask` means skipped
- a bit in `archivedMask` means the item was inactive in Archive on that day
- no bit in any mask means unset day
- masks for the same day must not overlap
- count fields are denormalized mirrors of the corresponding mask bit counts
- count fields are validated against masks during protected read and backup restore paths

### `PillHistoryRange`
Purpose:
- cold historical Pill history storage for long, uniform generated ranges
- one row can represent many scheduled taken days before the editable window

Important fields:
- `id`
- `pillID`
- `startDate`
- `endDate`
- `stateRaw`
- `useScheduleForHistory`
- `scheduleKindRaw`
- `weekdayMask`
- `intervalDays`
- `anchorDate`
- `count`
- `createdAt`
- `updatedAt`

Meaning:
- `startDate` and `endDate` are inclusive normalized local days
- `stateRaw` uses the same semantic states as bucket masks: positive, skipped, archived
- generated create-time cold history currently writes positive ranges only
- `useScheduleForHistory`, schedule fields, and `anchorDate` describe which days inside the date range actually carry the state
- for Daily/every-day history, every day in the range carries the state
- for Weekly/interval history, only dates matching the stored schedule rule and anchor carry the state
- `count` stores the number of matching state days in the range and is validated against the schedule payload on protected reads and backup restore
- range rows must not overlap same-day bucket state for normal writes; bucket state wins if old or corrupted local data overlaps

### `PillIntake`
Purpose:
- legacy one day-level Pill history row

Important fields:
- `id`
- `pillID`
- `localDate`
- `sourceRaw`
- `createdAt`

Meaning:
- used only for old local data, old backups, corruption tests, and migration fallback
- valid rows are migrated into `PillHistoryBucket`
- new repository writes must not create normal Pill history in this table
- if a bucket and a legacy row both exist for the same Pill/day, the bucket wins
- new day writes delete any same-day legacy rows after writing the bucket state

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

### `Event`
Purpose:
- root record for a lightweight Countdown or Count Up event

Important fields:
- `id`
- `name`
- `modeRaw`
- `eventDate`
- `sortOrder`
- `createdAt`
- `updatedAt`
- `version`

Meaning:
- `modeRaw = countdown` means the dashboard counts down from today to `eventDate`
- `modeRaw = elapsed` is the persisted compatibility value for the user-facing Count Up mode; it means the dashboard counts from `eventDate` through today
- Events have no relationships, no history buckets, no reminder rows, no archive flag, and no schedule versions

## Stored Model Rules

- `startDate` is stored as a normalized start-of-day date.
- `activeFrom` is optional and stored as a normalized start-of-day date. When present, read-time projections use `max(startDate, activeFrom)` as the active cycle start. Restore writes this field to mark the date from which an archived item becomes active again.
- `endDate` is optional and stored as a normalized start-of-day date when present. The UI labels the option row as `End Repeat`; the stored fact is still the optional `endDate`.
- `isArchived` is the stored flag for the user-facing Archive state. When true, the item has moved to the separate Archive page and should not produce active today actions, overdue state, reminders, badge count, or history review.
- `archivedAt` stores the normalized local day on which the item entered Archive. Manual and automatic Archive both use the actual archive operation day; automatic Archive does not backdate this value to the logical End Date. Restore uses `archivedAt` to bound `Active From` and to write archived gap rows.
- Archiving does not delete or rewrite reminder settings, repeat settings, end date, or stored history. Those stored values remain historical facts for read-only archived Details and backups.
- Reminder times are stored as hour and minute integer components.
- Habit and Pill history mode are stored in `historyModeRaw`.
- Schedule changes are append-only through new version rows.
- Create inserts the initial schedule version with `effectiveFrom = startDate`.
- Edit inserts a replacement schedule version only when Repeat changed. The hidden replacement `effectiveFrom` is based on `max(today, startDate)` and is bounded by the technical schedule-change window; current UI normally saves the lower bound, and out-of-range internal values fall back to the lower bound. It is not user-editable and is not moved to the next matching scheduled day.
- Schedule versions store `scheduleKindRaw`, `weekdayMask`, and `intervalDays` so both weekday rules and `Every N days` interval rules can round-trip through persistence and backup.
- Daily state is stored through two optimized storage shapes: monthly history buckets for editable/recent days and history ranges for cold generated history.
- Create-time generated initial Habit/Pill history does not create legacy day-level `HabitCompletion` or `PillIntake` rows.
- The initial history planner splits generated history at the editable-window boundary:
  - cold history from `startDate` through the day before the editable window is stored as at most one schedule-aware `HabitHistoryRange` or `PillHistoryRange`
  - editable-window history from `max(startDate, today - 29 days)` through yesterday is stored in monthly bucket masks
- This keeps old generated history compact while keeping recent days individually editable.
- Restore removes archived history states on and after Active From before writing the new active cycle. Restore archived-gap writes then use upsert semantics that preserve existing completed/taken/skipped/archived states inside the archive gap. Only empty days become archived.
- Skipped days are stored explicitly, not inferred.
- Legacy `HabitCompletion` and `PillIntake` rows are read only as compatibility fallback. Bucket state has priority over legacy rows for the same owner/day; range state is used only when there is no bucket or legacy day state.
- Positive bucket history stores the fact that a day was completed/taken, not the old day-level provenance source. When positive bucket days are projected back into domain models they use the manual-edit compatibility source.
- Event `eventDate` is stored as a normalized start-of-day date.
- Event mode is stored in `modeRaw`.
- Events are permanently deleted; there is no Archive or Restore state for Events.

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
- event countdown / count-up duration text

## Validation Rules Applied While Reading

The code validates:
- `typeRaw`
- `historyModeRaw`
- legacy `sourceRaw`
- bucket masks and bucket counts
- `modeRaw` for Events
- `weekdayMask`
- reminder hour/minute ranges
- required fields on root and child rows

If validation fails in protected read paths, the app can raise a `DataIntegrityError` instead of silently producing an invalid projection.

## Backup Mapping

Backup serializes and restores:
- Habit
- HabitScheduleVersion
- HabitHistoryBucket
- HabitHistoryRange
- HabitCompletion legacy payloads for old backup compatibility
- BackupAppSettings
- Pill
- PillScheduleVersion
- PillHistoryBucket
- PillHistoryRange
- PillIntake legacy payloads for old backup compatibility
- Event

Both Habit and Pill backup payloads include stored `historyMode`.
Both Habit and Pill backup payloads include `endDate`, `isArchived`, `archivedAt`, and stored `historyMode`.
Current backups use `schemaVersion = 3` and store Habit/Pill history as monthly bucket payloads plus schedule-aware range payloads. Legacy v1 backups with day-level HabitCompletion/PillIntake payloads are accepted and restored into buckets. Legacy v2 backups without range payloads remain valid; missing range arrays default to empty.
Habit and Pill history bucket payloads can contain archived bits. Archived bucket days are restored as stored inactive-history facts and do not count as completed/taken or skipped.
Habit and Pill history range payloads can contain positive, skipped, or archived states, but current create-time generation writes positive ranges only. Restore validates range owner IDs, date order, count, and schedule payload before applying the archive.
The range-count and range-payload validation helpers are pure value helpers and are intentionally available from nonisolated service code so Backup restore validation can run without crossing into the main actor.
Schedule backup payloads include `scheduleKind` and `intervalDays` for interval and one-time repeat support.
Event backup payloads include `id`, `name`, `mode`, `date`, `sortOrder`, timestamps, and `version`.
`BackupAppSettings` stores the selected appearance mode and app tint. Legacy backups without this optional settings payload remain valid and do not overwrite the current appearance settings during restore.
