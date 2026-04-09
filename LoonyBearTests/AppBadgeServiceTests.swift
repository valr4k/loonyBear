import Foundation
import Testing

@testable import LoonyBear

@MainActor
@Suite
struct AppBadgeServiceTests {
    @Test
    func overdueCountIncludesOverdueItemsAndExcludesCompletedTakenAndFutureOnes() {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12, minute: 0))!

        let habits = [
            HabitCardProjection(
                id: UUID(),
                type: .build,
                name: "Overdue Habit",
                scheduleSummary: "Daily",
                currentStreak: 0,
                reminderText: "9:00 AM",
                reminderHour: 9,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isCompletedToday: false,
                isSkippedToday: false,
                sortOrder: 0
            ),
            HabitCardProjection(
                id: UUID(),
                type: .build,
                name: "Completed Habit",
                scheduleSummary: "Daily",
                currentStreak: 0,
                reminderText: "8:00 AM",
                reminderHour: 8,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isCompletedToday: true,
                isSkippedToday: false,
                sortOrder: 1
            ),
            HabitCardProjection(
                id: UUID(),
                type: .quit,
                name: "Future Habit",
                scheduleSummary: "Daily",
                currentStreak: 0,
                reminderText: "6:00 PM",
                reminderHour: 18,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isCompletedToday: false,
                isSkippedToday: false,
                sortOrder: 2
            ),
        ]

        let pills = [
            PillCardProjection(
                id: UUID(),
                name: "Overdue Pill",
                dosage: "1 capsule",
                scheduleSummary: "Daily",
                totalTakenDays: 0,
                reminderText: "10:00 AM",
                reminderHour: 10,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isScheduledToday: true,
                isTakenToday: false,
                isSkippedToday: false,
                sortOrder: 0
            ),
            PillCardProjection(
                id: UUID(),
                name: "Taken Pill",
                dosage: "1 tablet",
                scheduleSummary: "Daily",
                totalTakenDays: 0,
                reminderText: "7:00 AM",
                reminderHour: 7,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isScheduledToday: true,
                isTakenToday: true,
                isSkippedToday: false,
                sortOrder: 1
            ),
            PillCardProjection(
                id: UUID(),
                name: "Future Pill",
                dosage: "2 tablets",
                scheduleSummary: "Daily",
                totalTakenDays: 0,
                reminderText: "8:00 PM",
                reminderHour: 20,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isScheduledToday: true,
                isTakenToday: false,
                isSkippedToday: false,
                sortOrder: 2
            ),
        ]

        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: FakeHabitRepository(habits: habits)),
            pillRepository: FakePillRepository(pills: pills)
        )

        #expect(service.overdueCount(now: now) == 2)
    }

    @Test
    func projectedOverdueCountIncludesHabitsAndPillsAtScheduledTimestamp() {
        let calendar = Calendar(identifier: .gregorian)
        let timestamp = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 10, minute: 0))!

        let habits = [
            HabitReminderConfiguration(
                id: UUID(),
                name: "Projected Habit",
                startDate: timestamp,
                scheduleDays: .wednesday,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 9, minute: 0),
                completedDays: [],
                skippedDays: []
            ),
            HabitReminderConfiguration(
                id: UUID(),
                name: "Completed Habit",
                startDate: timestamp,
                scheduleDays: .wednesday,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 8, minute: 0),
                completedDays: [calendar.startOfDay(for: timestamp)],
                skippedDays: []
            ),
            HabitReminderConfiguration(
                id: UUID(),
                name: "Future Habit",
                startDate: timestamp,
                scheduleDays: .wednesday,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 11, minute: 0),
                completedDays: [],
                skippedDays: []
            ),
        ]

        let pills = [
            PillReminderConfiguration(
                id: UUID(),
                name: "Projected Pill",
                dosage: "1 pill",
                startDate: timestamp,
                scheduleDays: .wednesday,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 10, minute: 0),
                takenDays: [],
                skippedDays: []
            ),
            PillReminderConfiguration(
                id: UUID(),
                name: "Taken Pill",
                dosage: "1 pill",
                startDate: timestamp,
                scheduleDays: .wednesday,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 7, minute: 0),
                takenDays: [calendar.startOfDay(for: timestamp)],
                skippedDays: []
            ),
            PillReminderConfiguration(
                id: UUID(),
                name: "Disabled Pill",
                dosage: "1 pill",
                startDate: timestamp,
                scheduleDays: .wednesday,
                reminderEnabled: false,
                reminderTime: nil,
                takenDays: [],
                skippedDays: []
            ),
        ]

        let count = ProjectedBadgeCountCalculator.projectedOverdueCount(
            at: timestamp,
            habits: habits,
            pills: pills,
            calendar: calendar
        )

        #expect(count == 2)
    }

    @Test
    func overdueCountExcludesSkippedItems() {
        let now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12, minute: 0))!

        let habits = [
            HabitCardProjection(
                id: UUID(),
                type: .build,
                name: "Skipped Habit",
                scheduleSummary: "Daily",
                currentStreak: 0,
                reminderText: "9:00 AM",
                reminderHour: 9,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isCompletedToday: false,
                isSkippedToday: true,
                sortOrder: 0
            ),
        ]

        let pills = [
            PillCardProjection(
                id: UUID(),
                name: "Skipped Pill",
                dosage: "1 capsule",
                scheduleSummary: "Daily",
                totalTakenDays: 0,
                reminderText: "10:00 AM",
                reminderHour: 10,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isScheduledToday: true,
                isTakenToday: false,
                isSkippedToday: true,
                sortOrder: 0
            ),
        ]

        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: FakeHabitRepository(habits: habits)),
            pillRepository: FakePillRepository(pills: pills)
        )

        #expect(service.overdueCount(now: now) == 0)
    }
}

private struct FakeHabitRepository: HabitRepository {
    let habits: [HabitCardProjection]

    func fetchDashboardHabits() -> [HabitCardProjection] { habits }
    func fetchHabitDetails(id: UUID) -> HabitDetailsProjection? { nil }
    func createHabit(from draft: CreateHabitDraft) throws -> UUID { fatalError("Unused in tests") }
    func completeHabitToday(id: UUID) throws { fatalError("Unused in tests") }
    func skipHabitToday(id: UUID) throws { fatalError("Unused in tests") }
    func clearHabitDayStateToday(id: UUID) throws { fatalError("Unused in tests") }
    func deleteHabit(id: UUID) throws { fatalError("Unused in tests") }
    func updateHabit(from draft: EditHabitDraft) throws { fatalError("Unused in tests") }
}

private struct FakePillRepository: PillRepository {
    let pills: [PillCardProjection]

    func fetchDashboardPills() -> [PillCardProjection] { pills }
    func fetchPillDetails(id: UUID) -> PillDetailsProjection? { nil }
    func createPill(from draft: PillDraft) throws -> UUID { fatalError("Unused in tests") }
    func updatePill(from draft: EditPillDraft) throws { fatalError("Unused in tests") }
    func deletePill(id: UUID) throws { fatalError("Unused in tests") }
    func markTakenToday(id: UUID) throws { fatalError("Unused in tests") }
    func skipPillToday(id: UUID) throws { fatalError("Unused in tests") }
    func clearPillDayStateToday(id: UUID) throws { fatalError("Unused in tests") }
    func movePills(from offsets: IndexSet, to destination: Int) throws { fatalError("Unused in tests") }
}
