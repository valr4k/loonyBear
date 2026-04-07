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
}
