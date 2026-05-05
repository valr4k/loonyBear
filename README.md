# LoonyBear

LoonyBear is an iOS SwiftUI app for tracking habits and pills with reminders, history modes, streak logic for habits, pill snooze reminders, and local backup/restore.

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
- local reminder notifications
- pill remind-later notifications
- badge count derived from overdue items
- local backup and restore
- appearance mode and adaptive app tint settings, included in new backups
- Blue/Indigo/Green/Amber app color palette with Blue as the default
- pushed Repeat editor with Days and Interval selection
- End Date and separate Archive pages for completed or manually archived items
- scheduled-day dots in Habit and Pill history calendars
- native compact date/time pickers with shared Schedule presentation safety for simultaneous picker/popover/navigation taps, including a window-level touch-down guard that avoids stealing scroll gestures
- portrait-only orientation on iPhone
- Rules & Logic in-app reference content
- widget snapshot generation for Habit dashboard data
