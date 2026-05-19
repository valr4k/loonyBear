# LoonyBear Architecture

## Overview

LoonyBear is an iOS SwiftUI app with two tracking domains:
- Habits
- Pills
- Events

The runtime is composed from:
- `LoonyBearApp`
- `AppEnvironment`
- `ContentView`
- `RootTabView`
- `HabitAppState`
- `PillAppState`
- `EventAppState`
- `NotificationService`
- `PillNotificationService`
- `AppBadgeService`
- `AppNotificationCoordinator`
- `BackupService`
- `WidgetSyncService`

## Module Layout

### `LoonyBear/App`
Responsibilities:
- app entry point
- dependency wiring
- root tab navigation
- sheet routing for create, details, and edit flows

Key files:
- `LoonyBear/LoonyBearApp.swift`
- `LoonyBear/App/AppEnvironment.swift`
- `LoonyBear/App/RootTabView.swift`

### `LoonyBear/Core/Domain`
Responsibilities:
- domain model types
- history mode enums
- streak calculation
- backup archive models
- widget snapshot models
- event models and event duration formatting

Key files:
- `LoonyBear/Core/Domain/HabitModels.swift`
- `LoonyBear/Core/Domain/PillModels.swift`
- `LoonyBear/Core/Domain/EventModels.swift`
- `LoonyBear/Core/Domain/StreakEngine.swift`
- `LoonyBear/Core/Domain/BackupModels.swift`
- `LoonyBear/Core/Domain/WidgetSnapshotModels.swift`

### `LoonyBear/Core/Application`
Responsibilities:
- screen-facing app state
- use cases
- side-effect coordination after domain mutations

Key files:
- `LoonyBear/Core/Application/HabitAppState.swift`
- `LoonyBear/Core/Application/PillAppState.swift`
- `LoonyBear/Core/Application/EventAppState.swift`
- `LoonyBear/Core/Application/CreateHabitUseCase.swift`
- `LoonyBear/Core/Application/UpdateHabitUseCase.swift`
- `LoonyBear/Core/Application/LoadDashboardUseCase.swift`
- `LoonyBear/Core/Application/ReconcilePastHistoryUseCase.swift`
- `LoonyBear/Core/Application/HabitSideEffectCoordinator.swift`
- `LoonyBear/Core/Application/PillSideEffectCoordinator.swift`

### `LoonyBear/Core/Data`
Responsibilities:
- Core Data persistence
- repository implementations
- shared repository helpers
- preview seeding

Key files:
- `LoonyBear/Core/Data/CoreDataHabitRepository.swift`
- `LoonyBear/Core/Data/CoreDataPillRepository.swift`
- `LoonyBear/Core/Data/CoreDataEventRepository.swift`
- `LoonyBear/Core/Data/CoreDataSupport.swift`
- `LoonyBear/Core/Data/HabitRepository.swift`
- `LoonyBear/Core/Data/PillRepository.swift`
- `LoonyBear/Core/Data/EventRepository.swift`
- `LoonyBear/Core/Data/DemoDataWriter.swift`

### `LoonyBear/Core/Services`
Responsibilities:
- local notification scheduling and action handling
- badge refresh
- backup / restore
- compression
- reliability and integrity reporting
- widget snapshot persistence and sync

Key files:
- `LoonyBear/Core/Services/NotificationService.swift`
- `LoonyBear/Core/Services/PillNotificationService.swift`
- `LoonyBear/Core/Services/AppNotificationCoordinator.swift`
- `LoonyBear/Core/Services/AppBadgeService.swift`
- `LoonyBear/Core/Services/BackupService.swift`
- `LoonyBear/Core/Services/CompressionService.swift`
- `LoonyBear/Core/Services/ReliabilitySupport.swift`
- `LoonyBear/Core/Services/WidgetSnapshotStore.swift`
- `LoonyBear/Core/Services/WidgetSyncService.swift`

### `LoonyBear/Features`
Responsibilities:
- SwiftUI screens grouped by feature
- create / details / edit forms and presentation
- dashboard lists and cards
- settings and Rules & Logic surfaces

### `LoonyBearTests`
Responsibilities:
- repository tests
- service tests
- backup tests
- notification tests
- shared rules tests

## Data Flow

1. A SwiftUI screen triggers an action on `HabitAppState`, `PillAppState`, or `EventAppState`.
2. The app state calls a use case or repository.
3. Repositories read or write Core Data facts.
4. Domain logic derives projections such as streaks, totals, reminder eligibility, and schedule summaries.
5. Side-effect coordinators trigger notification refresh, delivered notification cleanup, badge refresh, and widget sync where applicable.
6. App state publishes updated projections back to SwiftUI.

## Source of Truth

Core Data stores facts, not UI-specific projections.

Stored facts include:
- habits
- pills
- schedule versions
- monthly history buckets
- schedule-aware history ranges
- legacy completion / intake rows for migration and backup compatibility
- reminder fields
- history mode fields

Generated initial Habit/Pill history is split by editability. Cold generated history before the editable window is written as a schedule-aware range; recent editable generated history is written into monthly bucket masks. The create path does not materialize one Core Data object per generated historical day.

Derived values include:
- dashboard sections
- card projections
- streaks
- totals
- overdue status
- schedule summary text
- widget snapshots

## Navigation Architecture

- The app has exactly 4 tabs: `My Pills`, `My Habits`, `Events`, `Settings`.
- The default selected tab is `My Pills`.
- Habit, Pill, and Event create/details screens open as sheets.
- Settings uses a route-based `NavigationStack` for Backup and Rules & Logic.
- The selected tab and active Settings route are stored in `@SceneStorage` so app tint or restore-driven root rebuilds preserve the user's place.
- Settings child screens use the shared custom tinted back button while a UIKit bridge keeps the native left-edge interactive pop gesture enabled.
- Notification taps can switch tabs by posting:
  - `openMyHabitsTab`
  - `openMyPillsTab`

## Lifecycle Architecture

On first `ContentView` task:
- notification categories are configured
- Habit dashboard loads
- Pill dashboard loads
- badge refresh runs
- startup health check runs once in the background after initial load

On every `.active` scene phase:
- Habit reconciliation runs
- Pill reconciliation runs
- both dashboards refresh
- both notification services reschedule

## Persistence Strategy

- `PersistenceController` owns the Core Data container.
- `viewContext` merges parent changes automatically.
- background contexts are created per write operation.
- repositories use `CoreDataRepositoryContext` for write coordination.
- read contexts are refreshed after successful writes.

## Side-Effect Architecture

### Habit side effects
- reschedule Habit notifications
- remove delivered Habit notifications for acted-on day
- refresh badge
- sync widget snapshot
- Restore side effects run only after the Habit repository reports that a real archived-to-active restore happened. A stale restore request for a missing or already-active Habit is a no-op and must not reschedule notifications, refresh delivered notification state, or sync restore-specific side effects.

### Pill side effects
- remove pill snoozed reminders for same pill/day when needed
- reschedule Pill notifications
- remove delivered Pill notifications for acted-on day
- refresh badge
- Restore side effects run only after the Pill repository reports that a real archived-to-active restore happened. A stale restore request for a missing or already-active Pill is a no-op and must not reschedule notifications, clear snoozed reminders, or sync restore-specific side effects.

## Current Technical Boundaries

- Habits and Pills use separate repositories and separate app state.
- Events use their own repository and app state. They do not participate in reminders, overdue, badges, history review, Archive, Restore, or widget snapshots.
- Streak logic exists only for Habits.
- Pills support reordering through `sortOrder`.
- Backup covers Habits, Pills, Events, and app appearance settings in one archive schema.
- Backup owns create/restore feedback through floating banners; restore success refreshes app state and shows a green banner on the Backup screen.
- Backup schema version 3 serializes monthly history buckets plus schedule-aware history ranges. Backup validation uses pure `nonisolated` range helpers because the app target uses MainActor default isolation, while restore integrity checks run from nonisolated service code. Monthly bucket masks are validated against the real days in their `yearMonthKey`, so impossible bits such as February 31 fail validation instead of being normalized by `Calendar`.
- `AutoBackupService` coordinates optional automatic backups without changing the archive schema. It stores the user toggle, dirty flag, and dirty generation in `UserDefaults`, observes store mutation notifications, receives dirty marks from `AppStateWriteCoordinator` and Settings changes, debounces writes for 20 seconds, and calls the same `BackupService.createBackup()` path used by manual backup. Auto Backup disables itself when the selected backup destination is not trusted: missing folder, inaccessible bookmark, unreadable backup, or readable backup that has not been created/restored by this app install. Successful manual restore clears dirty state without immediately creating a new automatic backup and establishes the restored backup as the new trusted baseline.
- `BackupService` serializes create and restore operations with an operation lock so manual backup, automatic backup, and restore cannot write backup files in parallel.
- Habit and Pill dashboards expose separate Archive pages backed by stored `isArchived` facts. The Archive toolbar entry is conditional and appears only when the corresponding dashboard has archived items.
- Schedule editing is shared through a pushed Repeat editor with Days and Interval sections.
- End Repeat/End Date and Pill one-time repeat rules are stored facts; active/archive state, overdue, reminders, and calendar dots are derived from those facts at read time. Shared End Date validation lives in `EndDateValidationSupport`: optional End Date is valid, one-time Pills ignore End Date, and selected End Date must be at or after the active lower bound with at least one scheduled day in range. Shared Schedule UI uses native compact date pickers without app-level selectable ranges, and Save normalization only stores date-only values and does not silently raise End Date during `normalizedDraft()`.
- Archived Habit and Pill Details are read-only by default. Restore dismisses the read-only sheet and opens a separate Restore Draft sheet: the item stays archived until the Restore Draft sheet is saved, `Active From` is chosen in a bounded window, and `End Repeat` defaults to Never inside the draft. Saving a valid Restore Draft shows a system choice between `Continue Progress` and `Start From Scratch`. `Continue Progress` starts a new schedule version at Active From, removes stale archived history on/after Active From, writes archived gap rows only into empty days from `archivedAt` through the day before Active From, and auto-fills scheduled past days from Active From through yesterday as restored completed/taken when empty. `Start From Scratch` clears all old history rows, sets Start Date to Active From, starts a new schedule version at Active From, and returns the item with empty calendar history and reset streak/count totals. Repository restore methods return `true` only when this archived-to-active transition actually happened; AppState uses that value to run notification/archive side effects only for real restores. If the item is missing or already active by the time restore is requested, the repository returns `false`, the dashboard refresh still remains safe, and restore side effects are skipped. If the user changes tabs before the Restore Draft handoff opens, the pending handoff is cancelled.
- All create/details/restore sheets share unsaved-change dismissal protection. The visible Close button opens `Discard changes?` when the draft differs from its baseline. Swipe-down sheet dismissal is guarded by `appSheetDismissGuard`, a small UIKit presentation-controller bridge that asks the same `close()` path whether dismissal is allowed. Clean sheets still dismiss normally; dirty sheets stay open and show the same Discard Changes confirmation instead of silently losing edits.
- Active Details schedule changes still use schedule version rows, but Apply From is no longer a customer-facing field. The hidden schedule-change `effectiveFrom` is based on `max(today, startDate)` and bounded by the technical schedule-change window. Current UI normally saves the lower bound; out-of-range internal values fall back to the lower bound. Resolution does not check whether the date matches the new Repeat or has explicit history state.
- Schedule Create/active Details picker safety is centralized in shared UI infrastructure: native compact `DatePicker` controls and Repeat `NavigationLink` stay system-owned, while `AppSchedulePresentationGuard`, the Schedule card exclusive-touch scope, a window-level touch-down observer, and the End Repeat dismiss signal prevent simultaneous picker/popover/navigation presentation races without attaching scroll-stealing SwiftUI gestures to the picker capsules.
- App tint updates are applied through SwiftUI tint helpers and visible UIKit tab/navigation bar updates.
- Widget snapshot currently serializes Habit dashboard data only.
- Event dashboard state is derived from stored `Event` rows. `Countdown` cards show days remaining and clamp to `0d` in red on/after the event date. `Count Up` cards count the selected date as day 1 and continue indefinitely until the user permanently deletes the Event.
