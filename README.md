# LoonyBear

LoonyBear is an iOS SwiftUI app for tracking habits, pills, and lightweight Countdown / Count Up events with reminders, history modes, streak logic for habits, pill snooze reminders, and local backup/restore.

## Developer Docs

- `ARCHITECTURE.md`: module layout and runtime composition
- `PROJECT_GUIDE.md`: practical onboarding and feature map
- `CORE_DATA_MODEL.md`: entities, stored facts, and persistence rules
- `BUSINESS_RULES.md`: implemented behavior rules for habits, pills, reminders, badge, and backup
- `DEVELOPMENT.md`: local workflow and testing expectations
- `TECHNICAL_DOCUMENTATION.md`: full structured technical documentation of the current codebase

## Testing Rule

All tests must be run only on:
- `platform=iOS Simulator,name=iPhone 17 Pro`

No other simulator destination is supported for test validation in this repository.

Do not run or document test validation on `iPhone 16`, `iPhone 17`, or any other simulator target.

## Recommended Validation Order

1. `xcodebuild build-for-testing -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
2. `xcodebuild test-without-building -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoonyBearTests/CoreDataHabitRepositoryTests`
3. `xcodebuild test-without-building -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoonyBearTests/CoreDataPillRepositoryTests`
4. full test run on the same simulator destination

## Current Scope

The current app supports:
- Habit tracking
- Pill tracking
- Events for Countdown and Count Up day counting
- local reminder notifications
- pill remind-later notifications
- badge count derived from overdue items
- local backup, restore, and optional Auto Backup
- appearance mode and adaptive app tint settings, included in new backups
- Blue/Indigo/Green/Amber app color palette with Blue as the default
- pushed Repeat editor with Days and Interval selection
- End Repeat / End Date and separate Archive pages for manually archived or automatically finished items
- active Pill Details and Habit Details sheets that replace the older separate Edit/Details split
- read-only item Details for archived items, Restore Draft flows with Keep History / Start Fresh choices, and permanent delete
- Events tab between Habits and Settings, with permanent delete only and no reminder/history/archive behavior
- optimized Habit/Pill history storage using monthly buckets plus schedule-aware cold history ranges for very old generated history
- optional Auto Backup toggle on the Backup screen; automatic backup keeps the existing backup files/schema and runs only when user-enabled, dirty data exists, and the selected folder is accessible
- scheduled-day dots in Habit and Pill history calendars
- unified `Name` inputs with word capitalization and `Add notes…` optional description placeholders
- native compact date/time pickers with shared Schedule presentation safety for simultaneous picker/popover/navigation taps, including a window-level touch-down guard that avoids stealing scroll gestures
- portrait-only orientation on iPhone
- Rules & Logic in-app reference content
- widget snapshot generation for Habit dashboard data
