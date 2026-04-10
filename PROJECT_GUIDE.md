# LoonyBear Project Guide

This project is an iOS SwiftUI app built around two tracking domains:

- habits
- pills

Core user capabilities:

- create and edit habits
- mark habits as completed or skipped for today
- create and edit pills with dosage and details
- mark pills as taken or skipped for today
- configure reminder notifications
- create and restore local backups
- sync a lightweight snapshot for future widgets

## Structure

- `LoonyBear/App`
  - bootstrap and dependency wiring
  - root tab navigation
- `LoonyBear/Core/Domain`
  - pure models and rules
  - streak and schedule logic
- `LoonyBear/Core/Application`
  - app state and use cases
  - side-effect coordinators
- `LoonyBear/Core/Data`
  - Core Data repositories
  - shared persistence helpers
- `LoonyBear/Core/Services`
  - notifications
  - app badge
  - backup and compression
  - widget snapshot sync
- `LoonyBear/Features`
  - SwiftUI feature screens
- `LoonyBearTests`
  - repository, service, and rules tests

## App Startup

1. `LoonyBearApp` calls `AppEnvironment.live()`.
2. `AppEnvironment` creates persistence, repositories, services, and app state.
3. `ContentView` loads the initial dashboards and notification setup.
4. `RootTabView` exposes three tabs:
   - `My Pills`
   - `My Habits`
   - `Settings`

## Data Flow

1. A SwiftUI view triggers an action on `HabitAppState` or `PillAppState`.
2. The application layer calls a use case or repository.
3. The repository reads or writes Core Data.
4. Domain logic derives projections such as streaks and schedule summaries.
5. Side-effect coordinators trigger notifications, widget sync, and badge refresh.
6. SwiftUI re-renders from published state.

## Key Files

- `LoonyBear/LoonyBearApp.swift`
- `LoonyBear/App/AppEnvironment.swift`
- `LoonyBear/ContentView.swift`
- `LoonyBear/App/RootTabView.swift`
- `LoonyBear/Core/Application/HabitAppState.swift`
- `LoonyBear/Core/Application/PillAppState.swift`
- `LoonyBear/Core/Data/CoreDataHabitRepository.swift`
- `LoonyBear/Core/Data/CoreDataPillRepository.swift`
- `LoonyBear/Core/Services/NotificationService.swift`
- `LoonyBear/Core/Services/PillNotificationService.swift`
- `LoonyBear/Core/Services/BackupService.swift`

## Current Refactoring Direction

Recent cleanup in this workspace focused on:

- shared Core Data helper utilities
- reducing repository duplication
- moving side-effect orchestration out of screen state
- expanding tests for edge cases

When making new changes, prefer extending these patterns instead of reintroducing ad-hoc persistence or side-effect logic.
