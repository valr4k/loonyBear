# LoonyBear Architecture

## Overview

LoonyBear is an iOS SwiftUI app with two tracking domains:
- Habits
- Pills

The runtime is composed from:
- `LoonyBearApp`
- `AppEnvironment`
- `ContentView`
- `RootTabView`
- `HabitAppState`
- `PillAppState`
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

Key files:
- `LoonyBear/Core/Domain/HabitModels.swift`
- `LoonyBear/Core/Domain/PillModels.swift`
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
- `LoonyBear/Core/Data/CoreDataSupport.swift`
- `LoonyBear/Core/Data/HabitRepository.swift`
- `LoonyBear/Core/Data/PillRepository.swift`
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

1. A SwiftUI screen triggers an action on `HabitAppState` or `PillAppState`.
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
- completion / intake rows
- reminder fields
- history mode fields

Derived values include:
- dashboard sections
- card projections
- streaks
- totals
- overdue status
- schedule summary text
- widget snapshots

## Navigation Architecture

- The app has exactly 3 tabs: `My Pills`, `My Habits`, `Settings`.
- The default selected tab is `My Pills`.
- Habit and Pill create/details/edit screens open as sheets.
- Notification taps can switch tabs by posting:
  - `openMyHabitsTab`
  - `openMyPillsTab`

## Lifecycle Architecture

On first `ContentView` task:
- notification categories are configured
- Habit dashboard loads
- Pill dashboard loads
- badge refresh runs

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

### Pill side effects
- remove pill snoozed reminders for same pill/day when needed
- reschedule Pill notifications
- remove delivered Pill notifications for acted-on day
- refresh badge

## Current Technical Boundaries

- Habits and Pills use separate repositories and separate app state.
- Streak logic exists only for Habits.
- Pills support reordering through `sortOrder`.
- Backup covers both trackers in one archive schema.
- Widget snapshot currently serializes Habit dashboard data only.
