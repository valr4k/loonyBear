# LoonyBear Architecture

## Modules

- `LoonyBear/App`
  - App entry point
  - dependency wiring
  - root tab navigation
- `LoonyBear/Core/Domain`
  - pure business models
  - streak and schedule logic
- `LoonyBear/Core/Application`
  - screen-facing state
  - use cases
- `LoonyBear/Core/Data`
  - Core Data repositories
  - demo seeding for previews
- `LoonyBear/Core/Services`
  - notifications
  - future backup, widget sync, reminder cleanup
- `LoonyBear/Features`
  - user-facing screens grouped by feature

## Data Flow

1. SwiftUI view triggers a screen model action.
2. Screen model calls a use case from `Core/Application`.
3. Use case reads or writes through repository contracts in `Core/Data`.
4. Repositories map Core Data rows into domain projections.
5. Derived values such as streaks are recalculated from raw records in `Core/Domain`.
6. Services handle side effects such as notifications and future widget refreshes.
7. Screen model publishes the new projection back to SwiftUI.

## Source of Truth

- Core Data stores raw facts only:
  - habits
  - schedule versions
  - completion records
  - app preferences
- UI projections and streak values are derived at read time.

## Extension Direction

- Apple Watch notifications
  - use local iPhone notifications with actionable categories
  - rely on system forwarding to Apple Watch in V1
- iPhone widgets
  - next step is an App Group snapshot store plus a WidgetKit extension
  - widget data should be read from shared snapshots, not directly from the Core Data store
