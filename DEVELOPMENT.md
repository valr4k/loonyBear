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
- Keep notification payload contracts stable when changing action behavior.

## Testing Priorities

High-priority tests include:
- repository state transitions
- history normalization
- schedule versioning
- streak edge cases
- notification action routing
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
