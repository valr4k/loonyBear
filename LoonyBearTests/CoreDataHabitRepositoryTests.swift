import CoreData
import Testing

@testable import LoonyBear

@MainActor
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
        let details = try #require(try repository.fetchHabitDetails(id: habitID))

        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: .weekends,
            reminderEnabled: false,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            completedDays: [],
            skippedDays: []
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

        let habits = try repository.fetchDashboardHabits()
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

    @Test
    func skipDoesNotCountAsCompletionAndCompletionOverwritesSkip() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = false

        let habitID = try repository.createHabit(from: draft)

        try repository.skipHabitToday(id: habitID)

        let skippedDashboardHabit = try #require(
            try repository.fetchDashboardHabits().first { $0.id == habitID }
        )
        let skippedDetails = try #require(try repository.fetchHabitDetails(id: habitID))

        #expect(skippedDashboardHabit.isSkippedToday)
        #expect(!skippedDashboardHabit.isCompletedToday)
        #expect(skippedDetails.totalCompletedDays == 0)
        #expect(skippedDetails.completedDays.isEmpty)
        #expect(skippedDetails.skippedDays.count == 1)

        try repository.completeHabitToday(id: habitID)

        let completedDashboardHabit = try #require(
            try repository.fetchDashboardHabits().first { $0.id == habitID }
        )
        let completedDetails = try #require(try repository.fetchHabitDetails(id: habitID))

        #expect(!completedDashboardHabit.isSkippedToday)
        #expect(completedDashboardHabit.isCompletedToday)
        #expect(completedDetails.totalCompletedDays == 1)
        #expect(completedDetails.completedDays.count == 1)
        #expect(completedDetails.skippedDays.isEmpty)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSPredicate(format: "habitID == %@", habitID as CVarArg)
        let completions = try context.fetch(request)

        #expect(completions.count == 1)
        #expect(completions.first?.value(forKey: "sourceRaw") as? String == CompletionSource.swipe.rawValue)
    }

    @Test
    func clearRemovesSkippedStateAndReturnsHabitToNormalDayState() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = false

        let habitID = try repository.createHabit(from: draft)

        try repository.skipHabitToday(id: habitID)
        try repository.clearHabitDayStateToday(id: habitID)

        let dashboardHabit = try #require(
            try repository.fetchDashboardHabits().first { $0.id == habitID }
        )
        let details = try #require(try repository.fetchHabitDetails(id: habitID))

        #expect(!dashboardHabit.isSkippedToday)
        #expect(!dashboardHabit.isCompletedToday)
        #expect(details.completedDays.isEmpty)
        #expect(details.skippedDays.isEmpty)
        #expect(details.totalCompletedDays == 0)
    }

    @Test
    func updateHabitCanClearEditableSkippedDay() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily

        let habitID = try repository.createHabit(from: draft)
        try repository.skipHabitToday(id: habitID)

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            completedDays: [],
            skippedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(updatedDetails.completedDays.isEmpty)
        #expect(updatedDetails.skippedDays.isEmpty)
    }

    @Test
    func createHabitAutoFillsPastScheduledDaysAsCompleted() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = yesterday
        draft.scheduleDays = .daily

        let habitID = try repository.createHabit(from: draft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.completedDays.contains(yesterday))
        #expect(!details.skippedDays.contains(yesterday))
    }

    @Test
    func createHabitAutoFillsOnlyScheduledPastDays() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let unscheduledPastDay = try #require(
            (2...7)
                .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
                .map { calendar.startOfDay(for: $0) }
                .first { calendar.weekdaySet(for: $0) != calendar.weekdaySet(for: yesterday) }
        )

        var draft = CreateHabitDraft()
        draft.name = "Gym"
        draft.startDate = unscheduledPastDay
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)

        let habitID = try repository.createHabit(from: draft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.completedDays.contains(yesterday))
        #expect(!details.completedDays.contains(unscheduledPastDay))
        #expect(!details.skippedDays.contains(yesterday))

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", unscheduledPastDay as CVarArg),
        ])
        #expect(try context.count(for: request) == 0)
    }

    @Test
    func createHabitEveryDayHistoryAutoFillsAllPastDays() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        var draft = CreateHabitDraft()
        draft.name = "Stretch"
        draft.startDate = threeDaysAgo
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)
        draft.useScheduleForHistory = false

        let habitID = try repository.createHabit(from: draft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))

        #expect(details.historyMode == .everyDay)
        #expect(details.completedDays.contains(threeDaysAgo))
        #expect(details.completedDays.contains(twoDaysAgo))
        #expect(details.completedDays.contains(yesterday))
    }

    @Test
    func updateHabitNormalizesPastEditableNoneToCompleted() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = yesterday
        draft.scheduleDays = .daily

        let habitID = try repository.createHabit(from: draft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.completedDays.contains(yesterday))

        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            completedDays: [],
            skippedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(updatedDetails.completedDays.contains(yesterday))
        #expect(!updatedDetails.skippedDays.contains(yesterday))
    }

    @Test
    func updateHabitDoesNotCreateSkippedForPastUnscheduledDays() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let unscheduledPastDay = try #require(
            (2...7)
                .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
                .map { calendar.startOfDay(for: $0) }
                .first { calendar.weekdaySet(for: $0) != calendar.weekdaySet(for: yesterday) }
        )

        var draft = CreateHabitDraft()
        draft.name = "Gym"
        draft.startDate = unscheduledPastDay
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)

        let habitID = try repository.createHabit(from: draft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.completedDays.contains(yesterday))
        #expect(!details.completedDays.contains(unscheduledPastDay))

        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            completedDays: [],
            skippedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(updatedDetails.completedDays.contains(yesterday))
        #expect(!updatedDetails.completedDays.contains(unscheduledPastDay))

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", unscheduledPastDay as CVarArg),
        ])
        #expect(try context.count(for: request) == 0)
    }

    @Test
    func updateHabitEveryDayNormalizesAllPastEditableDaysToCompleted() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        var draft = CreateHabitDraft()
        draft.name = "Journal"
        draft.startDate = threeDaysAgo
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)

        let habitID = try repository.createHabit(from: draft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))

        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            historyMode: .everyDay,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            completedDays: [],
            skippedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(updatedDetails.historyMode == .everyDay)
        #expect(updatedDetails.completedDays.contains(threeDaysAgo))
        #expect(updatedDetails.completedDays.contains(twoDaysAgo))
        #expect(updatedDetails.completedDays.contains(yesterday))
    }

    @Test
    func reconcilePastDaysAutoFillsScheduledHabitHistoryAsCompleted() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        let habitID = UUID()
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Walk", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(yesterday, forKey: "startDate")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(Date(), forKey: "createdAt")
        habit.setValue(Date(), forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        schedule.setValue(UUID(), forKey: "id")
        schedule.setValue(habitID, forKey: "habitID")
        schedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        schedule.setValue(yesterday, forKey: "effectiveFrom")
        schedule.setValue(Date(), forKey: "createdAt")
        schedule.setValue(Int32(1), forKey: "version")
        schedule.setValue(habit, forKey: "habit")
        try context.save()

        let inserted = try repository.reconcilePastDays(today: today)
        #expect(inserted == 1)

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.completedDays.contains(yesterday))
        #expect(!details.skippedDays.contains(yesterday))

        let secondInserted = try repository.reconcilePastDays(today: today)
        #expect(secondInserted == 0)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSPredicate(format: "habitID == %@", habitID as CVarArg)
        let completions = try context.fetch(request)
        #expect(completions.count == 1)
        #expect(completions.first?.value(forKey: "sourceRaw") as? String == CompletionSource.autoFill.rawValue)
    }

    @Test
    func reconcilePastDaysDoesNotOverwriteSkippedHistory() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        let habitID = UUID()
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Walk", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(yesterday, forKey: "startDate")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(Date(), forKey: "createdAt")
        habit.setValue(Date(), forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        schedule.setValue(UUID(), forKey: "id")
        schedule.setValue(habitID, forKey: "habitID")
        schedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        schedule.setValue(yesterday, forKey: "effectiveFrom")
        schedule.setValue(Date(), forKey: "createdAt")
        schedule.setValue(Int32(1), forKey: "version")
        schedule.setValue(habit, forKey: "habit")

        let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
        completion.setValue(UUID(), forKey: "id")
        completion.setValue(habitID, forKey: "habitID")
        completion.setValue(yesterday, forKey: "localDate")
        completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
        completion.setValue(Date(), forKey: "createdAt")
        completion.setValue(habit, forKey: "habit")
        try context.save()

        let inserted = try repository.reconcilePastDays(today: today)
        #expect(inserted == 0)

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.skippedDays.contains(yesterday))
        #expect(!details.completedDays.contains(yesterday))
    }

    @Test
    func reconcilePastDaysEveryDayAutoFillsAllPastHistoryAsCompleted() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        let habitID = UUID()
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Meditate", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(threeDaysAgo, forKey: "startDate")
        habit.setValue(HabitHistoryMode.everyDay.rawValue, forKey: "historyModeRaw")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(Date(), forKey: "createdAt")
        habit.setValue(Date(), forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        schedule.setValue(UUID(), forKey: "id")
        schedule.setValue(habitID, forKey: "habitID")
        schedule.setValue(Int16(calendar.weekdaySet(for: yesterday).rawValue), forKey: "weekdayMask")
        schedule.setValue(threeDaysAgo, forKey: "effectiveFrom")
        schedule.setValue(Date(), forKey: "createdAt")
        schedule.setValue(Int32(1), forKey: "version")
        schedule.setValue(habit, forKey: "habit")
        try context.save()

        let inserted = try repository.reconcilePastDays(today: today)
        #expect(inserted == 3)

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.historyMode == .everyDay)
        #expect(details.completedDays.contains(threeDaysAgo))
        #expect(details.completedDays.contains(twoDaysAgo))
        #expect(details.completedDays.contains(yesterday))
    }

    @Test
    func fetchHabitDetailsDefaultsMissingHistoryModeToScheduleBased() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let habitID = UUID()
        let startDate = Calendar.current.startOfDay(for: Date())
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Legacy", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(startDate, forKey: "startDate")
        habit.setValue("", forKey: "historyModeRaw")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(Date(), forKey: "createdAt")
        habit.setValue(Date(), forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        schedule.setValue(UUID(), forKey: "id")
        schedule.setValue(habitID, forKey: "habitID")
        schedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        schedule.setValue(startDate, forKey: "effectiveFrom")
        schedule.setValue(Date(), forKey: "createdAt")
        schedule.setValue(Int32(1), forKey: "version")
        schedule.setValue(habit, forKey: "habit")
        try context.save()

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.historyMode == .scheduleBased)
    }

    @Test
    func fetchDashboardHabitsFailsOnCorruptedRow() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let object = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        object.setValue(UUID(), forKey: "id")
        object.setValue("broken_type", forKey: "typeRaw")
        object.setValue("Corrupted", forKey: "name")
        object.setValue(Date(), forKey: "startDate")
        object.setValue(false, forKey: "reminderEnabled")
        object.setValue(Date(), forKey: "createdAt")
        object.setValue(Date(), forKey: "updatedAt")
        try context.save()

        do {
            _ = try repository.fetchDashboardHabits()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
            #expect(error.report.issues.count == 1)
        }
    }

    @Test
    func fetchHabitDetailsFailsWhenReminderHourIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Corrupted Details"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 15)
        let habitID = try repository.createHabit(from: draft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderHour")
        try context.save()

        do {
            _ = try repository.fetchHabitDetails(id: habitID)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchHabitDetails")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func createEditDeleteHabitSmoke() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        let habitID = try repository.createHabit(from: draft)

        let created = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(created.name == "Read")

        let editDraft = EditHabitDraft(
            id: habitID,
            type: created.type,
            startDate: created.startDate,
            name: "Read More",
            scheduleDays: .weekdays,
            reminderEnabled: true,
            reminderTime: ReminderTime(hour: 9, minute: 30),
            completedDays: [],
            skippedDays: []
        )
        try repository.updateHabit(from: editDraft)

        let updated = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(updated.name == "Read More")
        #expect(updated.scheduleDays == .weekdays)
        #expect(updated.reminderEnabled)

        try repository.deleteHabit(id: habitID)
        #expect(try repository.fetchDashboardHabits().isEmpty)
    }

    @Test
    func fetchDashboardHabitsFailsWhenReminderHourIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderHour")
        try context.save()

        do {
            _ = try repository.fetchDashboardHabits()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func fetchDashboardHabitsFailsWhenReminderMinuteIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        do {
            _ = try repository.fetchDashboardHabits()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func fetchDashboardHabitsFailsWhenReminderHourIsOutOfRange() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(Int16(24), forKey: "reminderHour")
        try context.save()

        do {
            _ = try repository.fetchDashboardHabits()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func fetchDashboardHabitsFailsWhenReminderMinuteIsOutOfRange() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(Int16(60), forKey: "reminderMinute")
        try context.save()

        do {
            _ = try repository.fetchDashboardHabits()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardHabits")
            #expect(!error.report.isEmpty)
        }
    }
}
