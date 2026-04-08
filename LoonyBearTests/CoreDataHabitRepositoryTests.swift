import CoreData
import Testing

@testable import LoonyBear

@Suite
struct CoreDataHabitRepositoryTests {
    @Test
    func updateHabitAppendsNewScheduleVersion() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var createDraft = CreateHabitDraft()
        createDraft.name = "Read"
        createDraft.startDate = TestSupport.makeDate(2026, 4, 1)
        createDraft.scheduleDays = .daily
        createDraft.reminderEnabled = false

        let habitID = try repository.createHabit(from: createDraft)
        let details = try #require(repository.fetchHabitDetails(id: habitID))

        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: .weekends,
            reminderEnabled: false,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            completedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitScheduleVersion")
        request.predicate = NSPredicate(format: "habitID == %@", habitID as CVarArg)
        let schedules = try context.fetch(request)
        let masks = Set(schedules.map { Int($0.value(forKey: "weekdayMask") as? Int16 ?? 0) })

        #expect(schedules.count == 2)
        #expect(masks == Set([WeekdaySet.daily.rawValue, WeekdaySet.weekends.rawValue]))
    }

    @Test
    func dashboardHabitsSortByReminderTimeThenSortOrder() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var laterReminder = CreateHabitDraft()
        laterReminder.type = .build
        laterReminder.name = "Later"
        laterReminder.startDate = TestSupport.makeDate(2026, 4, 1)
        laterReminder.scheduleDays = .daily
        laterReminder.reminderEnabled = true
        laterReminder.reminderTime = ReminderTime(hour: 18, minute: 0)
        _ = try repository.createHabit(from: laterReminder)

        var earlierReminder = CreateHabitDraft()
        earlierReminder.type = .build
        earlierReminder.name = "Earlier"
        earlierReminder.startDate = TestSupport.makeDate(2026, 4, 1)
        earlierReminder.scheduleDays = .daily
        earlierReminder.reminderEnabled = true
        earlierReminder.reminderTime = ReminderTime(hour: 9, minute: 0)
        _ = try repository.createHabit(from: earlierReminder)

        var sameTimeFirst = CreateHabitDraft()
        sameTimeFirst.type = .build
        sameTimeFirst.name = "Same Time First"
        sameTimeFirst.startDate = TestSupport.makeDate(2026, 4, 1)
        sameTimeFirst.scheduleDays = .daily
        sameTimeFirst.reminderEnabled = true
        sameTimeFirst.reminderTime = ReminderTime(hour: 12, minute: 0)
        _ = try repository.createHabit(from: sameTimeFirst)

        var sameTimeSecond = CreateHabitDraft()
        sameTimeSecond.type = .build
        sameTimeSecond.name = "Same Time Second"
        sameTimeSecond.startDate = TestSupport.makeDate(2026, 4, 1)
        sameTimeSecond.scheduleDays = .daily
        sameTimeSecond.reminderEnabled = true
        sameTimeSecond.reminderTime = ReminderTime(hour: 12, minute: 0)
        _ = try repository.createHabit(from: sameTimeSecond)

        var noReminder = CreateHabitDraft()
        noReminder.type = .build
        noReminder.name = "No Reminder"
        noReminder.startDate = TestSupport.makeDate(2026, 4, 1)
        noReminder.scheduleDays = .daily
        noReminder.reminderEnabled = false
        _ = try repository.createHabit(from: noReminder)

        let habits = repository.fetchDashboardHabits()
            .filter { $0.type == .build }
            .map(\.name)

        #expect(habits == [
            "Earlier",
            "Same Time First",
            "Same Time Second",
            "Later",
            "No Reminder",
        ])
    }
}
