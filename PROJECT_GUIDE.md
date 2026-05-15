# LoonyBear Project Guide

LoonyBear is an iOS SwiftUI app built around two tracking domains:
- habits
- pills
- events

## Core User Capabilities

- create and edit habits
- complete, skip, or clear today for habits
- create and edit pills with dosage and optional description
- take, skip, or clear today for pills
- tap active cards to open Pill Details / Habit Details
- open archived cards from Archive as read-only item screens
- archive active items, restore archived items, and permanently delete active or archived items
- create, edit, and permanently delete Countdown / Count Up events
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
4. `RootTabView` exposes `My Pills`, `My Habits`, `Events`, and `Settings`.
5. Create screens and item Details screens are opened as sheets. Create sheet titles are `Add new Pill`, `Add new Habit`, and `Add new Event`. Active cards open editable `Pill Details` / `Habit Details` sheets; Archive cards open the same layout read-only and can hand off to a separate Restore Draft sheet. Event cards open editable `Event Details`.
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
  - Archive
  - permanent Delete
- Habit Details for an archived Habit shows the same layout read-only:
  - name
  - streak metrics
  - Schedule facts as historical data
  - start date and End Date
  - read-only calendar
  - Restore and permanent Delete at the bottom

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
  - Archive
  - permanent Delete
- Pill Details for an archived Pill shows the same layout read-only:
  - name
  - dosage
  - taken total
  - Schedule facts as historical data
  - start date and End Date
  - read-only calendar
  - description
  - Restore and permanent Delete at the bottom

## Event Flow Summary

- Events are shown on their own `Events` tab between Habits and Settings.
- If there are no Events, the screen shows a single empty state: `No Events Yet` / `Create your first event to get started.`
- The dashboard shows a `Countdown` section only when at least one Countdown event exists.
- The dashboard shows a `Count Up` section only when at least one Count Up event exists.
- Event create supports:
  - name
  - mode
  - date
- Mode values:
  - `Countdown`: counts days from today to today or a future event date
  - `Count Up`: counts days from a past or current event date to today
- Default dates:
  - Countdown defaults to today, so a same-day event displays `0d`
  - Count Up defaults to today, because selected day is day 1
- Switching mode keeps the form valid:
  - Countdown to Count Up moves a future date to today
  - Count Up to Countdown moves past dates to today
- Event validation:
  - Countdown date can be today or in the future
  - Countdown dates in the past disable Save and show `Countdown date must be in the future.`
  - Count Up date can be today or in the past
  - invalid dates disable Save and show a dismissible floating warning banner
- Event cards show the name on the left and duration on the right in the same compact style as streak text, for example `2yr 2mo 7d`.
- Event duration uses the app tint, except completed Countdown cards show `0d` in red forever.
- Event Details supports editing name, mode, and date.
- Event Delete is permanent. There is no Archive, Restore, reminder, overdue, badge, history review, or auto-delete behavior for Events.

## Important Current Rules

- Habit and Pill Create Start Date uses the native compact system date picker with no app-level selectable range.
- Habit, Pill, and Event name fields use the shared `Name` placeholder and word capitalization. Pill description fields use the optional `Add notes…` placeholder.
- Future Habits stay in Build/Quit without today actions, overdue, notifications, or history review until their start date; future Pills appear in Pending with the same inactive behavior. Future cards show `Starts 03 May 2026` style dates.
- Editable history window is 30 days for both domains.
- Habit current streak is reset only by missed scheduled days in the past.
- Pills do not use streak logic.
- Notifications are scheduled only for the next 2 days.
- Pill `Remind me in 10 mins` survives global regular pill reschedules.
- Repeat uses a pushed editor with Days and Interval blocks. Days supports weekday combinations. Interval is `Every N days`, limited to 2 through 5 days, and for Pills only also includes `Never`. Weekday summaries are canonicalized as Daily, Weekdays, Weekends, `Weekly on Mon` for one selected weekday, or abbreviated day lists such as `Mon, Wed, Fri` for other combinations.
- Pill Repeat can be `Never`; this means one scheduled day on Start Date. Habits do not expose `Never`.
- Pills and Habits both use `End Repeat`; `On Date` reveals an `End Date` picker row. Empty end dates display `Never`.
- Active items can be archived from their Details screen. Archive keeps stored reminder/repeat/end-date/history facts, moves the item to the separate Archive page, and stops active today actions, overdue state, notifications, badge contribution, and history review.
- Active items can also be permanently deleted from their Details screen.
- Archive items open read-only item screens and expose Restore plus permanent Delete at the bottom.
- Restore closes the read-only Archive sheet and opens a separate Restore Draft sheet. The item remains archived until the Restore Draft sheet is saved.
- Restore Draft defaults End Repeat to `Never`, clears End Date in the draft, and shows editable `Active From` under the read-only Start Date.
- Restore removes archived history states on and after Active From before the new active cycle starts. It then writes archived history states only into empty days between `archivedAt` and the day before Active From. Existing Completed/Taken/Skipped states in that gap are preserved.
- Archived history states render in custom calendars as quiet system-gray circles, independent of app tint, and they are never editable.
- If the user changes tabs after requesting Restore but before the Restore Draft sheet opens, the pending Restore Draft is cancelled.
- My Pills and My Habits show the Archive toolbar button only when that tracker has at least one archived item.
- Settings supports System/Light/Dark appearance and Blue/Indigo/Green/Amber app color selection; Blue is the default and first palette option.
- App tint colors supported accent surfaces, while page backgrounds stay on the system grouped background.
- Backup includes the selected appearance mode and app tint, while legacy backups without those settings keep the current appearance.
- Backup includes Events. Legacy backups without Events restore normally with an empty Events list.
- Custom calendars use arrow-only month navigation, without horizontal swipe paging.
- Custom calendar blocks keep a stable six-week footprint when changing months.
- Habit and Pill Details calendars show all stored history. Active Details calendars preserve edit restrictions: only days in the editable 30-day window, not earlier than Start Date, and not stored as archived can be changed. Archive Details calendars are fully read-only.
- Habit and Pill Details calendars show a small tertiary system-gray dot under days that match the active schedule history. Marked completed/taken/skipped days use circular markers; editable marked days also draw a subtle border, while non-editable marked days keep a softer historical marker.
- Missing past-day review warnings use a dismissible floating red material banner on active Details screens; they do not list dates and do not take space inside the calendar layout.
- Create and active Details Repeat selection opens as a pushed screen inside the sheet. Archive Details show Repeat as read-only text and do not open a schedule picker until Restore Draft.
- Create and active Details Schedule blocks keep the native compact Start Date, Time, and End Date pickers where applicable. Active Details show Start Date as read-only. When Create first switches End Repeat to `On Date`, End Date defaults to today rather than Start Date. End Date uses `max(today, startDate)` as its lower bound and is validated by shared schedule-aware logic: a selected End Date is valid only when it is not in the past and at least one scheduled day exists between the lower bound and the selected date. Save does not silently raise an invalid End Date inside `normalizedDraft()`. Invalid End Date warnings are dismissible and reappear when the invalid state changes through form input. If Repeat changes on active Details, the hidden schedule version `effectiveFrom` is based on `max(today, startDate)`, bounded by the schedule-change technical window, normally saved at the lower bound, and not shown as Apply From. It is not adjusted to the next matching scheduled day. A shared presentation guard prevents simultaneous picker/popover/navigation presentation races without changing the visible UI.
- My Pills and My Habits use native `List` sections with system sticky headers. Headers keep only light styling on top of the system behavior: `title3` semibold text, secondary color, and no forced uppercasing.
- End Repeat uses the native options popover. While it is open, neighboring compact pickers do not accept hit-testing; Time and End Repeat use a window-level touch-down observer to briefly block the opposite presentation path without stealing scroll gestures; Repeat navigation dismisses/briefly blocks End Repeat so the popover cannot remain over the pushed Repeat screen.
- Active Archive confirmations use system alerts with `Cancel` and `Archive` actions: `Archive this Pill?` / `This Pill will be moved to Archive.` and `Archive this Habit?` / `This Habit will be moved to Archive.`
- Permanent Delete confirmations use system alerts with `Cancel` and destructive `Delete` actions: `Permanently delete this Pill?` / `This Pill will be permanently deleted.` and `Permanently delete this Habit?` / `This Habit will be permanently deleted.`
- Backup and Delete actions use the shared material capsule button style; light mode uses a `systemGray4` base under `.ultraThinMaterial`, dark mode uses clear material-only base. `Last backup` follows the cloud status icon color and uses `03 May at 22:35` style dates; backup action confirmations use system alerts with short action labels. The Settings `Backup` row uses the subtitle `Manual and automatic backups`. The Backup status card also contains an `Auto Backup` toggle with the `clock.arrow.trianglehead.clockwise.rotate.90.path.dotted` icon.
- Backup action notices are floating banners derived from folder contents and remembered backup fingerprints, so already created/restored backups do not show restore-needed notices after reopening the screen. Backup success feedback uses green floating banners.
- Auto Backup is user-controlled from the Backup screen only. It reuses the normal backup writer, file names, schema, rotation, and folder bookmark. Dirty app data is marked after write operations, notification action mutations, Event changes, Pill reorder, and backed-up Settings changes, then automatic backup runs after a 20-second debounce when the selected folder is usable.
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
