# LoonyBear Development Workflow

## Open the Project

Use:
- `LoonyBear.xcodeproj`

Shared scheme:
- `LoonyBear`

Test target:
- `LoonyBearTests`

## Required Simulator Rule

All local test validation must be run only on:
- `platform=iOS Simulator,name=iPhone 17 Pro`

Do not use any other simulator destination for test validation in this repository.

This rule is mandatory for local test runs and documentation examples.

## Recommended Workflow

1. Open the project in full Xcode.
2. Run the app on `iPhone 17 Pro` simulator.
3. Run `LoonyBearTests` before and after non-trivial logic changes.
4. Prefer adding or updating tests when changing:
   - repositories
   - history normalization
   - streak logic
   - reminder scheduling
   - backup and restore

## Where to Make Changes

- UI layout or interaction:
  - `LoonyBear/Features`
- app state, use cases, side-effect coordination:
  - `LoonyBear/Core/Application`
- persistence and projection building:
  - `LoonyBear/Core/Data`
- domain rules and derived logic:
  - `LoonyBear/Core/Domain`
- reminders, backups, badge, widgets, reliability:
  - `LoonyBear/Core/Services`

## Implementation Guidance

- Prefer typed helpers over repeating raw `value(forKey:)` parsing in multiple places.
- Keep Core Data as a fact store rather than adding denormalized UI fields.
- Preserve schedule history through appended version rows.
- Keep screen state small and move reusable side-effect sequences into coordinators or services.
- Do not change backup schema casually without updating restore handling, validation, and tests.
- Backup payloads include app appearance settings; preserve legacy decode behavior for backups without those settings.
- Backup payloads currently use schema version 3. Habit/Pill history is serialized as monthly bucket payloads plus schedule-aware range payloads; legacy daily payloads remain compatibility inputs only.
- Keep `CoreDataHistoryRangeCalculator` and `CoreDataHistoryRangeSupport.isValidPayload(...)` pure and `nonisolated`. The app target uses MainActor default isolation, while `BackupService` validates range payloads from nonisolated code.
- Keep shared schedule UI in `AppDesign.swift`; Create and active Details should use the shared pushed Repeat editor, while Archive read-only Details should use the same visual layout with all editing controls disabled until Restore Draft is opened.
- Restore Draft must clear archived history states on and after Active From before writing the new archive gap, then write archived states only into empty gap days. This prevents stale future Archived days from a previous restore attempt while still preserving real completed/taken/skipped states.
- Keep Apply From out of the customer-facing Details UI. If Repeat changes, the hidden schedule version `effectiveFrom` is resolved in shared persistence logic from `max(today, startDate)` and must remain documented with schedule versioning tests.
- Keep Schedule picker/popover protection shared through `AppSchedulePresentationGuard` and `appExclusiveTouchScope()`. Create and active Details must not grow separate picker-blocking state, and native compact `DatePicker` controls should stay native unless the product explicitly chooses a different visual pattern.
- Do not attach the Time-row touch-down guard to Start Date. Start Date relies on the exclusive-touch scope only; an extra gesture can prevent the native compact date picker from opening.
- Do not replace `appTouchDownAction` with a SwiftUI gesture on picker capsules. The current helper is intentionally implemented as a non-cancelling window-level observer so Time/End Repeat race protection does not steal vertical scrolling.
- App tint should be added through shared helpers (`appAccentTint`, `appAccentForeground`, `AppTint`) so fixed system colors remain intentional.
- Habit/Pill/Event name fields use the shared `Name` placeholder and word-capitalization behavior. Pill description fields use the shared `Add notes…` placeholder.
- Keep notification payload contracts stable when changing action behavior.
- The main app target uses an Xcode run script to increment `CURRENT_PROJECT_VERSION` by 1 for normal builds. Xcode previews skip the increment, and the About screen formats the build as a short six-digit value. Normal local builds intentionally edit `LoonyBear.xcodeproj/project.pbxproj`; seeing only that build-number change after a build is expected and should not be treated as unrelated churn.

## Testing Priorities

High-priority tests include:
- repository state transitions
- history normalization
- schedule versioning
- streak edge cases
- notification action routing
- End Date validation through `EndDateValidationSupport`: empty End Date, dates before lower bound, first scheduled day, later scheduled windows, edited schedule previews, and one-time Pill repeat
- Restore Draft with past, today, and future Active From values, including restore to a future date, archive again, then restore to an earlier date to confirm stale future Archived days are cleared
- schedule version effectiveFrom behavior: Create uses startDate; Edit Repeat changes use hidden `max(today, startDate)` and do not auto-resolve to the next matching weekday
- real-device Schedule interaction QA: two-finger Time + End Repeat, Start Date + End Repeat, Date + Time, Repeat + End Repeat, and vertical scrolling starting on the Time capsule and End Repeat value
- reminder aggregation and snooze behavior
- backup rotation and restore fallback behavior

## Suggested CLI Validation Order

1. `xcodebuild build-for-testing -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
2. `xcodebuild test-without-building -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoonyBearTests/CoreDataHabitRepositoryTests`
3. `xcodebuild test-without-building -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoonyBearTests/CoreDataPillRepositoryTests`
4. full test run on the same simulator destination

## Environment Notes

- Command line builds may require full Xcode, not only Command Line Tools.
- If simulator services are unavailable in the current shell environment, validate through Xcode.app directly, but still use `iPhone 17 Pro`.
