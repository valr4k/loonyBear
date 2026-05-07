# LoonyBear Project Guide

LoonyBear is an iOS SwiftUI app built around two tracking domains:
- habits
- pills

## Core User Capabilities

- create and edit habits
- complete, skip, or clear today for habits
- create and edit pills with dosage and optional description
- take, skip, or clear today for pills
- tap active cards to open Pill Details / Habit Details
- open soft-deleted cards from Recently Deleted as read-only item screens
- soft-delete active items and permanently delete items from Recently Deleted
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
5. Create screens and item Details screens are opened as sheets. Create sheet titles are `Add new Pill` and `Add new Habit`. Active cards open editable `Pill Details` / `Habit Details` sheets; Recently Deleted cards open the same layout read-only.
6. App-active lifecycle refreshes derived overdue/history state and reschedules notifications.

## Habit Flow Summary

- Habits are grouped by type in the dashboard.
- Habit create supports:
  - type
  - name
  - start date
  - reminder settings
  - Repeat through Days or Interval
  - End Repeat / End Date
- Habit Details for an active Habit supports:
  - name
  - streak metrics
  - read-only Start Date
  - reminder
  - Repeat through the pushed Repeat screen
  - End Repeat / End Date
  - recent editable history
  - description-free calendar/history review
  - Delete as soft delete
- Habit Details for a Recently Deleted Habit shows the same layout read-only:
  - name
  - streak metrics
  - Schedule facts as historical data
  - start date and End Date
  - read-only calendar
  - permanent Delete at the bottom

## Pill Flow Summary

- Pills are shown in `Today` and `Pending` sections.
- Pill create supports:
  - name
  - dosage
  - optional description
  - start date
  - reminder settings
  - Repeat through Days or Interval
  - End Repeat / End Date
- Pill Details for an active Pill supports:
  - name
  - dosage
  - taken total
  - read-only Start Date
  - reminder
  - Repeat through the pushed Repeat screen
  - End Repeat / End Date
  - recent editable history
  - optional description
  - Delete as soft delete
- Pill Details for a Recently Deleted Pill shows the same layout read-only:
  - name
  - dosage
  - taken total
  - Schedule facts as historical data
  - start date and End Date
  - read-only calendar
  - description
  - permanent Delete at the bottom

## Important Current Rules

- Habit and Pill Create Start Date uses the native compact system date picker with no app-level selectable range.
- Future Habits stay in Build/Quit without today actions, overdue, notifications, or history review until their start date; future Pills appear in Pending with the same inactive behavior. Future cards show `Starts 03 May 2026` style dates.
- Editable history window is 30 days for both domains.
- Habit current streak is reset only by missed scheduled days in the past.
- Pills do not use streak logic.
- Notifications are scheduled only for the next 2 days.
- Pill `Remind me in 10 mins` survives global regular pill reschedules.
- Repeat uses a pushed editor with Days and Interval blocks. Days supports weekday combinations. Interval is `Every N days`, limited to 2 through 5 days, and for Pills only also includes `Never`. Weekday summaries are canonicalized as Daily, Weekdays, Weekends, `Weekly on Mon` for one selected weekday, or abbreviated day lists such as `Mon, Wed, Fri` for other combinations.
- Pill Repeat can be `Never`; this means one scheduled day on Start Date. Habits do not expose `Never`.
- Pills and Habits both use `End Repeat`; `On Date` reveals an `End Date` picker row. Empty end dates display `Never`.
- Active items can be deleted from their Details screen. This is a soft delete: the item moves to Recently Deleted, keeps its stored reminder/repeat/end-date/history facts, stops producing active state, and cannot be restored.
- Recently Deleted is final inactive storage. Recently Deleted items open read-only item screens and expose only permanent Delete at the bottom.
- My Pills and My Habits show the Recently Deleted toolbar button only when that tracker has at least one soft-deleted item.
- Settings supports System/Light/Dark appearance and Blue/Indigo/Green/Amber app color selection; Blue is the default and first palette option.
- App tint colors supported accent surfaces, while page backgrounds stay on the system grouped background.
- Backup includes the selected appearance mode and app tint, while legacy backups without those settings keep the current appearance.
- Custom calendars use arrow-only month navigation, without horizontal swipe paging.
- Custom calendar blocks keep a stable six-week footprint when changing months.
- Habit and Pill Details calendars show all stored history. Active Details calendars preserve edit restrictions: only days in the editable 30-day window, not earlier than Start Date, can be changed. Recently Deleted Details calendars are fully read-only.
- Habit and Pill Details calendars show a small tertiary system-gray dot under days that match the active schedule history. Marked completed/taken/skipped days use circular markers; editable marked days also draw a subtle border, while non-editable marked days keep a softer historical marker.
- Missing past-day review warnings use a dismissible floating red material banner on active Details screens; they do not list dates and do not take space inside the calendar layout.
- Create and active Details Repeat selection opens as a pushed screen inside the sheet. Recently Deleted Details show Repeat as read-only text and do not open a schedule picker.
- Create and active Details Schedule blocks keep the native compact Start Date, Time, and End Date pickers where applicable. Active Details show Start Date as read-only. When Create first switches End Repeat to `On Date`, End Date defaults to today rather than Start Date. End Date uses `max(today, startDate)` as its lower bound and is validated by shared schedule-aware logic: a selected End Date is valid only when at least one scheduled day exists between the lower bound and the selected date. Save does not silently raise an invalid End Date inside `normalizedDraft()`. Invalid End Date warnings are dismissible and reappear when the invalid state changes through form input. If Repeat changes on active Details, the hidden schedule version `effectiveFrom` is based on `max(today, startDate)`, bounded by the schedule-change technical window, normally saved at the lower bound, and not shown as Apply From. It is not adjusted to the next matching scheduled day. A shared presentation guard prevents simultaneous picker/popover/navigation presentation races without changing the visible UI.
- My Pills and My Habits use native `List` sections with system sticky headers. Headers keep only light styling on top of the system behavior: `title3` semibold text, secondary color, and no forced uppercasing.
- End Repeat uses the native options popover. While it is open, neighboring compact pickers do not accept hit-testing; Time and End Repeat use a window-level touch-down observer to briefly block the opposite presentation path without stealing scroll gestures; Repeat navigation dismisses/briefly blocks End Repeat so the popover cannot remain over the pushed Repeat screen.
- Active Delete confirmations use system alerts with `Cancel` and destructive `Delete` actions: `Delete this Pill?` / `This Pill will be moved to Recently Deleted.` and `Delete this Habit?` / `This Habit will be moved to Recently Deleted.`
- Permanent Delete confirmations use system alerts with `Cancel` and destructive `Delete` actions: `Permanently delete this Pill?` / `This Pill will be permanently deleted.` and `Permanently delete this Habit?` / `This Habit will be permanently deleted.`
- Backup and Delete actions use the shared material capsule button style; light mode uses a `systemGray4` base under `.ultraThinMaterial`, dark mode uses clear material-only base. `Last backup` follows the cloud status icon color and uses `03 May at 22:35` style dates; backup action confirmations use system alerts with short action labels.
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
