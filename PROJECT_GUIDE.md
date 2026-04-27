# LoonyBear Project Guide

LoonyBear is an iOS SwiftUI app built around two tracking domains:
- habits
- pills

## Core User Capabilities

- create and edit habits
- complete, skip, or clear today for habits
- create and edit pills with dosage and optional description
- take, skip, or clear today for pills
- configure reminder notifications
- use pill remind-later notifications
- create and restore local backups
- read Rules & Logic and technical reference content

## Project Structure

- `LoonyBear/App`
  - app bootstrap
  - dependency wiring
  - root tab navigation
- `LoonyBear/Core/Domain`
  - pure models and rule engines
  - streak logic
  - backup and widget models
- `LoonyBear/Core/Application`
  - app state
  - use cases
  - side-effect coordinators
- `LoonyBear/Core/Data`
  - Core Data repositories
  - shared persistence helpers
  - demo data seeding
- `LoonyBear/Core/Services`
  - notifications
  - badge
  - backup and compression
  - reliability support
  - widget snapshot sync
- `LoonyBear/Features`
  - feature screens
- `LoonyBearTests`
  - repository, service, and rule tests

## Runtime Flow

1. `LoonyBearApp` builds `AppEnvironment.live()`.
2. `AppEnvironment` creates persistence, repositories, services, use cases, and app state.
3. `ContentView` configures notifications, loads dashboards, and refreshes the badge.
4. `RootTabView` exposes `My Pills`, `My Habits`, and `Settings`.
5. Create, Details, and Edit screens are opened as sheets.
6. App-active lifecycle refreshes derived overdue/history state and reschedules notifications.

## Habit Flow Summary

- Habits are grouped by type in the dashboard.
- Habit create supports:
  - type
  - name
  - start date
  - reminder settings
  - weekday schedule
  - `Use schedule for history?`
- Habit details show:
  - name
  - start date
  - schedule
  - reminder
  - current streak
  - best streak
  - completed total
  - read-only calendar
- Habit edit supports:
  - name
  - reminder
  - weekday schedule
  - recent editable history
  - delete

## Pill Flow Summary

- Pills are shown in `Today` and `Pending` sections.
- Pill create supports:
  - name
  - dosage
  - optional description
  - start date
  - reminder settings
  - weekday schedule
  - `Use schedule for history?`
- Pill details show:
  - name
  - dosage
  - start date
  - schedule
  - reminder
  - total taken days
  - read-only calendar
  - optional description
- Pill edit supports:
  - name
  - dosage
  - description
  - reminder
  - weekday schedule
  - recent editable history
  - delete

## Important Current Rules

- Habit create start date range is the last 30 days including today.
- Pill create start date range is the last 5 years including today.
- Editable history window is 30 days for both domains.
- Habit current streak is reset only by missed scheduled days in the past.
- Pills do not use streak logic.
- Notifications are scheduled only for the next 2 days.
- Pill `Remind me in 10 mins` survives global regular pill reschedules.

## Recommended Entry Files

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
- `TECHNICAL_DOCUMENTATION.md`
