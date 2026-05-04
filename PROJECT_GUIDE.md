# LoonyBear Project Guide

LoonyBear is an iOS SwiftUI app built around two tracking domains:
- habits
- pills

## Core User Capabilities

- create and edit habits
- complete, skip, or clear today for habits
- create and edit pills with dosage and optional description
- take, skip, or clear today for pills
- open Edit or Info quickly from trailing card swipe actions
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

- Habit create start date range is the last 30 days through the end of the second next calendar month.
- Pill create start date range is the last 5 years through the end of the second next calendar month.
- Future Habits stay in Build/Quit without today actions, overdue, notifications, or history review until their start date; future Pills appear in Pending with the same inactive behavior.
- Editable history window is 30 days for both domains.
- Habit current streak is reset only by missed scheduled days in the past.
- Pills do not use streak logic.
- Notifications are scheduled only for the next 2 days.
- Pill `Remind me in 10 mins` survives global regular pill reschedules.
- Schedule popovers use weekday selection plus an Intervals row for `Every N days`, limited to 2 through 5 days. Weekday summaries are canonicalized as Daily, Weekdays, Weekends, Weekly for one selected weekday, or Custom for other combinations.
- Settings supports System/Light/Dark appearance and Blue/Indigo/Green/Amber app color selection; Blue is the default and first palette option.
- App tint colors supported accent surfaces, while page backgrounds stay on the system grouped background.
- Backup includes the selected appearance mode and app tint, while legacy backups without those settings keep the current appearance.
- Custom calendars use arrow-only month navigation, without horizontal swipe paging.
- Custom calendar blocks keep a stable six-week footprint when changing months.
- Habit and Pill Details/Edit calendars show a small tertiary system-gray dot under days that match the active schedule history.
- Missing past-day review warnings use a dismissible floating red material banner on Edit and Details screens; they do not list dates and do not take space inside the calendar layout.
- Schedule selection opens as a popover with full weekday names and no row dividers on Create/Edit and Details surfaces.
- Edit Habit and Edit Pill delete confirmations use system alerts with `Cancel` and destructive `Delete` actions.
- Backup actions are full-width capsule buttons; `Last backup` follows the cloud status icon color; backup action confirmations use system alerts with short action labels.
- Backup action notices are floating banners derived from folder contents and remembered backup fingerprints, so already created/restored backups do not show restore-needed notices after reopening the screen. Backup success feedback uses green floating banners.
- Settings child screens keep the custom tinted back button and preserve the native left-edge swipe-back gesture.
- Reminder permission denial is handled with an alert that can open iOS Settings; the inline permission error banner is no longer used.
- iPhone supports portrait orientation only. iPad keeps portrait and landscape orientations.

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
