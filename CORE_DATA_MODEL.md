# LoonyBear Core Data Model

## Source of Truth

Core Data stores raw facts, not UI projections.

Stored facts include:

- habits
- pills
- schedule versions
- completion / intake records
- app preferences

Derived values such as dashboard sections, streaks, overdue counts, and schedule summaries are recalculated at read time.

## Entities

### `AppPreference`

Purpose:

- generic key-value storage for app-level settings

Important fields:

- `key`
- `boolValue`
- `dataValue`
- `dateValue`
- `intValue`
- `stringValue`

Constraint:

- unique by `key`

### `Habit`

Purpose:

- root record for a tracked habit

Important fields:

- `id`
- `typeRaw`
- `name`
- `sortOrder`
- `startDate`
- `reminderEnabled`
- `reminderHour`
- `reminderMinute`
- `createdAt`
- `updatedAt`
- `version`

Relationships:

- `completions` -> `HabitCompletion`
- `scheduleVersions` -> `HabitScheduleVersion`

Deletion behavior:

- deleting a habit cascades to its completions and schedule versions

### `HabitCompletion`

Purpose:

- one day-level habit state record

Important fields:

- `id`
- `habitID`
- `localDate`
- `sourceRaw`
- `createdAt`

Meaning:

- one record per habit per local day
- `sourceRaw` distinguishes completion vs skipped

Constraints:

- unique by `id`
- unique by (`habitID`, `localDate`)

### `HabitScheduleVersion`

Purpose:

- immutable history of schedule changes

Important fields:

- `id`
- `habitID`
- `weekdayMask`
- `effectiveFrom`
- `createdAt`
- `version`

Meaning:

- changing a habit schedule appends a new version instead of rewriting history

### `Pill`

Purpose:

- root record for a tracked pill or medicine

Important fields:

- `id`
- `name`
- `dosage`
- `detailsText`
- `sortOrder`
- `startDate`
- `reminderEnabled`
- `reminderHour`
- `reminderMinute`
- `createdAt`
- `updatedAt`
- `version`

Relationships:

- `intakes` -> `PillIntake`
- `scheduleVersions` -> `PillScheduleVersion`

Deletion behavior:

- deleting a pill cascades to its intakes and schedule versions

### `PillIntake`

Purpose:

- one day-level pill state record

Important fields:

- `id`
- `pillID`
- `localDate`
- `sourceRaw`
- `createdAt`

Meaning:

- one record per pill per local day
- `sourceRaw` distinguishes taken vs skipped

Constraints:

- unique by `id`
- unique by (`pillID`, `localDate`)

### `PillScheduleVersion`

Purpose:

- immutable history of pill schedule changes

Important fields:

- `id`
- `pillID`
- `weekdayMask`
- `effectiveFrom`
- `createdAt`
- `version`

## Modeling Rules

- `startDate` is normalized to the local start of day.
- Daily state records are unique per item per day.
- Skipped days are stored explicitly, not inferred.
- Reminder times are stored as hour/minute components.
- Schedule history is append-only through new version rows.
- Read models choose the latest schedule version by:
  - newest `effectiveFrom`
  - then highest `version`
  - then newest `createdAt`

## Why This Model Works

- history is preserved when schedules change
- streaks can be recalculated correctly from facts
- backup and restore can serialize stable domain facts
- UI projections stay simple and disposable
