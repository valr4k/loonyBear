import CoreData
import Foundation
import Testing

@testable import LoonyBear

@MainActor
@Suite
struct AppBadgeServiceTests {
    @Test
    func overdueCountIncludesOverdueItemsAndExcludesCompletedTakenAndFutureOnes() throws {
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
                activeOverdueDay: Calendar.current.startOfDay(for: now),
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
                activeOverdueDay: Calendar.current.startOfDay(for: now),
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

        #expect(try service.overdueCount(now: now) == 2)
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
                name: "No Reminder Pill",
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

        #expect(count == 3)
    }

    @Test
    func projectedOverdueCountIncludesPreviousScheduledOverdueDay() {
        let calendar = Calendar(identifier: .gregorian)
        let sunday = calendar.date(from: DateComponents(year: 2025, month: 1, day: 19, hour: 18, minute: 0))!
        let mondayNotification = calendar.date(from: DateComponents(year: 2025, month: 1, day: 20, hour: 10, minute: 0))!

        let habits = [
            HabitReminderConfiguration(
                id: UUID(),
                name: "Weekly Habit",
                startDate: sunday,
                scheduleDays: .sunday,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 18, minute: 0),
                completedDays: [],
                skippedDays: []
            ),
        ]

        let count = ProjectedBadgeCountCalculator.projectedOverdueCount(
            at: mondayNotification,
            habits: habits,
            pills: [],
            calendar: calendar
        )

        #expect(count == 1)
    }

    @Test
    func overdueCountExcludesSkippedItems() throws {
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

        #expect(try service.overdueCount(now: now) == 0)
    }

    @Test
    func badgeRecomputationTracksRepositoryMutations() throws {
        let persistence = PersistenceController(inMemory: true)
        let calendar = Calendar.current
        let now = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 0,
            of: Date()
        ) ?? Date()
        let overdueAnchorStore = TestOverdueAnchorStore()
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: pillRepository,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var habitDraft = CreateHabitDraft()
        habitDraft.name = "Walk"
        habitDraft.startDate = Calendar.current.startOfDay(for: Date())
        habitDraft.scheduleDays = .daily
        habitDraft.reminderEnabled = true
        habitDraft.reminderTime = ReminderTime(hour: 0, minute: 1)
        let habitID = try habitRepository.createHabit(from: habitDraft)
        overdueAnchorStore.setAnchorDay(calendar.startOfDay(for: now), for: .habit, id: habitID, calendar: calendar)

        var pillDraft = PillDraft()
        pillDraft.name = "Magnesium"
        pillDraft.dosage = "1 capsule"
        pillDraft.startDate = Calendar.current.startOfDay(for: Date())
        pillDraft.scheduleDays = .daily
        pillDraft.reminderEnabled = true
        pillDraft.reminderTime = ReminderTime(hour: 0, minute: 1)
        let pillID = try pillRepository.createPill(from: pillDraft)
        overdueAnchorStore.setAnchorDay(calendar.startOfDay(for: now), for: .pill, id: pillID, calendar: calendar)

        #expect(try service.overdueCount(now: now) == 2)

        try habitRepository.completeHabitToday(id: habitID)
        try pillRepository.markTakenToday(id: pillID)

        #expect(try service.overdueCount(now: now) == 0)
    }

    @Test
    func forcedRefreshReappliesSameBadgeCountWhenSystemBadgeMayBeStale() {
        let badgeApplier = FakeBadgeApplier()
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: FakeHabitRepository(habits: [])),
            pillRepository: FakePillRepository(pills: []),
            badgeApplier: badgeApplier
        )

        service.refreshBadge(
            habitDashboard: .empty,
            pillDashboard: .empty,
            forceApply: true
        )
        service.refreshBadge(
            habitDashboard: .empty,
            pillDashboard: .empty,
            forceApply: true
        )

        #expect(badgeApplier.appliedCounts == [0, 0])
    }

    @Test
    func unforcedRefreshStillSkipsDuplicateBadgeWrites() {
        let badgeApplier = FakeBadgeApplier()
        let now = Calendar.current.startOfDay(for: Date())
        let habit = HabitCardProjection(
            id: UUID(),
            type: .build,
            name: "Overdue",
            scheduleSummary: "Daily",
            currentStreak: 0,
            reminderText: "9:00 AM",
            reminderHour: 9,
            reminderMinute: 0,
            isReminderScheduledToday: true,
            isCompletedToday: false,
            isSkippedToday: false,
            activeOverdueDay: now,
            sortOrder: 0
        )
        let dashboard = DashboardProjection(
            sections: [
                HabitSectionProjection(id: .build, title: "Build Habit", habits: [habit]),
            ]
        )
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: FakeHabitRepository(habits: [habit])),
            pillRepository: FakePillRepository(pills: []),
            badgeApplier: badgeApplier
        )

        service.refreshBadge(habitDashboard: dashboard, pillDashboard: .empty)
        service.refreshBadge(habitDashboard: dashboard, pillDashboard: .empty)

        #expect(badgeApplier.appliedCounts == [1])
    }

    @Test
    func badgeComputationFailsWhenHabitReminderHourIsMissingInsteadOfUsingMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: pillRepository
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try habitRepository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderHour")
        try context.save()

        do {
            _ = try service.overdueCount(now: Date())
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
        }
    }

    @Test
    func badgeComputationFailsWhenHabitReminderMinuteIsMissingInsteadOfUsingMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: pillRepository
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try habitRepository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        do {
            _ = try service.overdueCount(now: Date())
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
        }
    }

    @Test
    func badgeComputationFailsWhenHabitReminderHourIsOutOfRangeInsteadOfUsingMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: pillRepository
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try habitRepository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(Int16(24), forKey: "reminderHour")
        try context.save()

        do {
            _ = try service.overdueCount(now: Date())
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
        }
    }

    @Test
    func badgeComputationFailsWhenHabitReminderMinuteIsOutOfRangeInsteadOfUsingMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: pillRepository
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try habitRepository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(Int16(60), forKey: "reminderMinute")
        try context.save()

        do {
            _ = try service.overdueCount(now: Date())
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
        }
    }

    @Test
    func badgeComputationFailsWhenPillReminderMinuteIsMissingInsteadOfUsingMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: pillRepository
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 15)
        let pillID = try pillRepository.createPill(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        do {
            _ = try service.overdueCount(now: Date())
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardPills")
        }
    }
}

@MainActor
private struct FakeHabitRepository: HabitRepository {
    let habits: [HabitCardProjection]

    func fetchDashboardHabits() throws -> [HabitCardProjection] { habits }
    func fetchHabitDetails(id: UUID) throws -> HabitDetailsProjection? { nil }
    func reconcilePastDays(today: Date) throws -> Int { 0 }
    func createHabit(from draft: CreateHabitDraft) throws -> UUID { fatalError("Unused in tests") }
    func completeHabitToday(id: UUID) throws { fatalError("Unused in tests") }
    func completeHabitDay(id: UUID, on day: Date) throws { fatalError("Unused in tests") }
    func skipHabitToday(id: UUID) throws { fatalError("Unused in tests") }
    func skipHabitDay(id: UUID, on day: Date) throws { fatalError("Unused in tests") }
    func clearHabitDayStateToday(id: UUID) throws { fatalError("Unused in tests") }
    func clearHabitDayState(id: UUID, on day: Date) throws { fatalError("Unused in tests") }
    func deleteHabit(id: UUID) throws { fatalError("Unused in tests") }
    func setHabitArchived(id: UUID, isArchived: Bool) throws { fatalError("Unused in tests") }
    func updateHabit(from draft: EditHabitDraft) throws { fatalError("Unused in tests") }
}

@MainActor
private struct FakePillRepository: PillRepository {
    let pills: [PillCardProjection]

    func fetchDashboardPills() throws -> [PillCardProjection] { pills }
    func fetchPillDetails(id: UUID) throws -> PillDetailsProjection? { nil }
    func reconcilePastDays(today: Date) throws -> Int { 0 }
    func createPill(from draft: PillDraft) throws -> UUID { fatalError("Unused in tests") }
    func updatePill(from draft: EditPillDraft) throws { fatalError("Unused in tests") }
    func deletePill(id: UUID) throws { fatalError("Unused in tests") }
    func setPillArchived(id: UUID, isArchived: Bool) throws { fatalError("Unused in tests") }
    func markTakenToday(id: UUID) throws { fatalError("Unused in tests") }
    func markPillTaken(id: UUID, on day: Date) throws { fatalError("Unused in tests") }
    func skipPillToday(id: UUID) throws { fatalError("Unused in tests") }
    func skipPillDay(id: UUID, on day: Date) throws { fatalError("Unused in tests") }
    func clearPillDayStateToday(id: UUID) throws { fatalError("Unused in tests") }
    func clearPillDayState(id: UUID, on day: Date) throws { fatalError("Unused in tests") }
    func movePills(from offsets: IndexSet, to destination: Int) throws { fatalError("Unused in tests") }
}

private final class FakeBadgeApplier: AppBadgeApplying {
    private(set) var appliedCounts: [Int] = []

    func setBadgeCount(_ badgeCount: Int) {
        appliedCounts.append(badgeCount)
    }
}
