# LoonyBear

LoonyBear is an iOS SwiftUI app for tracking habits and pills with reminders, streak logic, and local backup/restore.

## Developer Docs

- `ARCHITECTURE.md`: high-level module overview
- `PROJECT_GUIDE.md`: practical onboarding guide
- `CORE_DATA_MODEL.md`: entities, relationships, and persistence rules
- `BUSINESS_RULES.md`: key behavioral rules for habits, pills, streaks, reminders, and backup
- `DEVELOPMENT.md`: local workflow and change guidance

## Testing

- Run local `xcodebuild` test commands against `platform=iOS Simulator,name=iPhone 17 Pro`.
- Do not use `iPhone 16` as the default simulator destination in this environment; it is not available here and can produce misleading test-run failures.
- Recommended validation order:
  1. `xcodebuild build-for-testing -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  2. `xcodebuild test-without-building -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoonyBearTests/CoreDataHabitRepositoryTests`
  3. `xcodebuild test-without-building -project LoonyBear.xcodeproj -scheme LoonyBear -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoonyBearTests/CoreDataPillRepositoryTests`
  4. full test run on the same simulator destination
