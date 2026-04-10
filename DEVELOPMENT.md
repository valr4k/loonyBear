# LoonyBear Development Workflow

## Open the Project

Use:

- `LoonyBear.xcodeproj`

Shared scheme:

- `LoonyBear`

Test target:

- `LoonyBearTests`

## Recommended Workflow

1. Open the project in full Xcode.
2. Run the app on an iPhone simulator.
3. Run `LoonyBearTests` before and after non-trivial logic changes.
4. Prefer adding tests when changing:
   - repositories
   - streak logic
   - reminder scheduling
   - backup and restore

## Where to Make Changes

- UI layout or interaction:
  - `LoonyBear/Features`
- screen state and action wiring:
  - `LoonyBear/Core/Application`
- persistence and projections:
  - `LoonyBear/Core/Data`
- business rules:
  - `LoonyBear/Core/Domain`
- reminders, backups, badge, widget sync:
  - `LoonyBear/Core/Services`

## Implementation Guidance

- Prefer typed helpers over repeating `value(forKey:)` parsing.
- Keep Core Data as a fact store rather than adding denormalized UI fields.
- Preserve schedule history through appended versions.
- Keep screen state small; move reusable side-effect sequences into coordinators or services.
- Do not change backup schema casually without updating restore handling and tests.

## Testing Priorities

High priority tests:

- repository state transitions
- schedule versioning
- streak edge cases
- reminder aggregation and routing
- backup rotation and restore fallback behavior

## Environment Notes

- Command line builds may require full Xcode, not only Command Line Tools.
- If `xcodebuild` cannot access simulator services in the current environment, validate through Xcode.app directly.
