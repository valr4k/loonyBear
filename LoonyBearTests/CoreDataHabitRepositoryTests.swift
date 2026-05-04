import CoreData
import Testing

@testable import LoonyBear

@MainActor
@Suite
struct CoreDataHabitRepositoryTests {
    @Test
    func dashboardIntervalHabitShowsNextScheduledWeekdays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = TestSupport.makeDate(2026, 5, 3, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { today.addingTimeInterval(10 * 60 * 60) })
        )

        var draft = CreateHabitDraft()
        draft.type = .build
        draft.name = "Interval habit"
        draft.startDate = today
        draft.scheduleRule = .intervalDays(3)

        let habitID = try repository.createHabit(from: draft)
        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })

        #expect(dashboardHabit.scheduleSummary == "Next: Sun, Wed, Sat")
    }

    @Test
    func archiveAndRestoreHabitMovesBetweenDashboardSections() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 10, minute: 0))!
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )
        let loadDashboard = LoadDashboardUseCase(repository: repository)

        var draft = CreateHabitDraft()
        draft.type = .build
        draft.name = "Archive me"
        draft.startDate = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        draft.scheduleRule = .weekly(.daily)
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)

        let habitID = try repository.createHabit(from: draft)
        try repository.setHabitArchived(id: habitID, isArchived: true)

        let archivedDashboard = try loadDashboard.execute()
        let archivedSection = try #require(archivedDashboard.sections.first)
        let archivedHabit = try #require(archivedSection.habits.first)

        #expect(archivedDashboard.sections.map(\.id) == [.archived])
        #expect(archivedSection.title == "Archived")
        #expect(archivedHabit.id == habitID)
        #expect(archivedHabit.isArchived)
        #expect(!archivedHabit.isReminderScheduledToday)
        #expect(archivedHabit.activeOverdueDay == nil)
        #expect(!archivedHabit.needsHistoryReview)

        try repository.setHabitArchived(id: habitID, isArchived: false)

        let restoredDashboard = try loadDashboard.execute()
        let restoredSection = try #require(restoredDashboard.sections.first)
        let restoredHabit = try #require(restoredSection.habits.first)

        #expect(restoredDashboard.sections.map(\.id) == [.build])
        #expect(!restoredHabit.isArchived)
    }

    @Test
    func habitEndDateAutoArchivesAfterLastScheduledDayBeforeEndDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let finalScheduledDay = TestSupport.makeDate(2026, 5, 18, calendar: calendar)
        let now = finalScheduledDay.addingTimeInterval(10 * 60 * 60)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var draft = CreateHabitDraft()
        draft.type = .build
        draft.name = "Ended habit"
        draft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        draft.endDate = TestSupport.makeDate(2026, 5, 20, calendar: calendar)
        draft.scheduleRule = .weekly(.monday)

        let habitID = try repository.createHabit(from: draft)
        let activeHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })

        #expect(!activeHabit.isArchived)

        try repository.completeHabitDay(id: habitID, on: finalScheduledDay)

        let archivedHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })
        #expect(archivedHabit.isArchived)
        #expect(archivedHabit.activeOverdueDay == nil)
    }

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
            completedDays: details.completedDays,
            skippedDays: details.skippedDays
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
    func futureHabitHasNoTodayStateButShowsScheduledDotsFromStartDateMonth() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 3, calendar: calendar)
        let futureStartDate = TestSupport.makeDate(2026, 7, 14, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var draft = CreateHabitDraft()
        draft.name = "Future habit"
        draft.startDate = futureStartDate
        draft.scheduleRule = .weekly(.daily)
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)

        let habitID = try repository.createHabit(from: draft)
        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })
        let details = try #require(try repository.fetchHabitDetails(id: habitID))

        #expect(!dashboardHabit.isReminderScheduledToday)
        #expect(!dashboardHabit.isCompletedToday)
        #expect(!dashboardHabit.isSkippedToday)
        #expect(!dashboardHabit.needsHistoryReview)
        #expect(dashboardHabit.activeOverdueDay == nil)
        #expect(dashboardHabit.startsInFuture)
        #expect(dashboardHabit.futureStartDate == futureStartDate)
        #expect(details.requiredPastScheduledDays.isEmpty)
        #expect(details.scheduledDates.contains(futureStartDate))
        #expect(details.scheduledDates.contains(TestSupport.makeDate(2026, 7, 31, calendar: calendar)))
    }

    @Test
    func updateHabitResolvesScheduleEffectiveFromToNextScheduledDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 3, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = CreateHabitDraft()
        createDraft.name = "Move schedule"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        createDraft.scheduleRule = .weekly(.daily)

        let habitID = try repository.createHabit(from: createDraft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        var editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleRule: .weekly(.monday),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            completedDays: details.completedDays,
            skippedDays: details.skippedDays
        )
        editDraft.scheduleEffectiveFrom = TestSupport.makeDate(2026, 5, 5, calendar: calendar)

        try repository.updateHabit(from: editDraft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitScheduleVersion")
        request.predicate = NSPredicate(format: "habitID == %@", habitID as CVarArg)
        let schedules = try context.fetch(request)
        let latest = try #require(schedules.max {
            ($0.value(forKey: "version") as? Int32 ?? 0) < ($1.value(forKey: "version") as? Int32 ?? 0)
        })

        #expect(latest.value(forKey: "effectiveFrom") as? Date == TestSupport.makeDate(2026, 5, 11, calendar: calendar))
        #expect(CoreDataScheduleSupport.rule(from: latest) == .weekly(.monday))
    }

    @Test
    func updateFutureHabitDashboardUsesSavedLatestScheduleVersion() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = CreateHabitDraft()
        createDraft.type = .build
        createDraft.name = "Future habit"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 11, calendar: calendar)
        createDraft.scheduleRule = .weekly([.tuesday, .wednesday])

        let habitID = try repository.createHabit(from: createDraft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        var editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleRule: .weekly(.friday),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            completedDays: details.completedDays,
            skippedDays: details.skippedDays
        )
        editDraft.scheduleEffectiveFrom = TestSupport.makeDate(2026, 5, 15, calendar: calendar)

        try repository.updateHabit(from: editDraft)

        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })
        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))

        #expect(dashboardHabit.scheduleSummary == "Weekly on Fri")
        #expect(updatedDetails.scheduleRule == .weekly(.friday))
    }

    @Test
    func updateHabitRemovesFutureScheduleVersionsReplacedByEarlierApplyFrom() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = CreateHabitDraft()
        createDraft.type = .build
        createDraft.name = "Replace future"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        createDraft.scheduleRule = .weekly(.daily)

        let habitID = try repository.createHabit(from: createDraft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))

        var futureDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleRule: .weekly(.weekends),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            completedDays: details.completedDays,
            skippedDays: details.skippedDays
        )
        futureDraft.scheduleEffectiveFrom = TestSupport.makeDate(2026, 5, 9, calendar: calendar)
        try repository.updateHabit(from: futureDraft)

        var replacementDraft = futureDraft
        replacementDraft.scheduleRule = .weekly(.daily)
        replacementDraft.scheduleEffectiveFrom = TestSupport.makeDate(2026, 5, 5, calendar: calendar)
        try repository.updateHabit(from: replacementDraft)

        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })
        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))

        #expect(dashboardHabit.scheduleSummary == "Daily")
        #expect(updatedDetails.scheduleRule == .weekly(.daily))
        #expect(updatedDetails.scheduleHistory.contains { $0.rule == .weekly(.daily) && $0.effectiveFrom == TestSupport.makeDate(2026, 5, 5, calendar: calendar) })
        #expect(!updatedDetails.scheduleHistory.contains { $0.rule == .weekly(.weekends) && $0.effectiveFrom == TestSupport.makeDate(2026, 5, 9, calendar: calendar) })
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
    func completeHabitTodayDeduplicatesExistingRowsForToday() throws {
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
        let habitRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        habitRequest.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        let habit = try #require(context.fetch(habitRequest).first)
        let today = Calendar.current.startOfDay(for: Date())

        for dayOffset in 0..<2 {
            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(habitID, forKey: "habitID")
            completion.setValue(today, forKey: "localDate")
            completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
            completion.setValue(Date().addingTimeInterval(TimeInterval(dayOffset)), forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")
        }
        try context.save()

        try repository.completeHabitToday(id: habitID)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", today as CVarArg),
        ])
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
    func clearHabitTodayImmediatelyRestoresOverdueWhenReminderAlreadyPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 30,
            hour: 18,
            minute: 0
        ))!
        let today = calendar.startOfDay(for: now)
        let overdueAnchorStore = TestOverdueAnchorStore()
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = today
        draft.scheduleDays = calendar.weekdaySet(for: today)
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)

        let habitID = try repository.createHabit(from: draft)
        try repository.completeHabitToday(id: habitID)
        try repository.clearHabitDayStateToday(id: habitID)

        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })
        #expect(!dashboardHabit.isCompletedToday)
        #expect(!dashboardHabit.isSkippedToday)
        #expect(dashboardHabit.activeOverdueDay == today)
        #expect(overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar) == today)
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
    func updateHabitImmediatelyAnchorsTodayOverdueWhenReminderAlreadyPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 30,
            hour: 18,
            minute: 0
        ))!
        let today = calendar.startOfDay(for: now)
        let overdueAnchorStore = TestOverdueAnchorStore()
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = today
        draft.scheduleDays = calendar.weekdaySet(for: today)
        draft.reminderEnabled = false

        let habitID = try repository.createHabit(from: draft)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: true,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            completedDays: [],
            skippedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })
        #expect(dashboardHabit.activeOverdueDay == today)
        #expect(overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar) == today)
    }

    @Test
    func reconcilePastDaysAnchorsMissedPastHabitReminderWithoutStoredAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 22,
            hour: 8,
            minute: 0
        ))!
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let overdueAnchorStore = TestOverdueAnchorStore()
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = yesterday
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try repository.createHabit(from: draft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", yesterday as CVarArg),
        ])
        for completion in try context.fetch(request) {
            context.delete(completion)
        }
        try context.save()

        let finalized = try repository.reconcilePastDays(today: now)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })

        #expect(finalized == 0)
        #expect(!details.needsHistoryReview)
        #expect(details.requiredPastScheduledDays.contains(yesterday))
        #expect(details.activeOverdueDay == yesterday)
        #expect(dashboardHabit.activeOverdueDay == yesterday)
        #expect(!dashboardHabit.needsHistoryReview)
        #expect(overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar) == nil)
    }

    @Test
    func reconcilePastDaysKeepsOlderDueHabitDaysAsHistoryGaps() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 20
        ))!
        let wednesday = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 22
        ))!
        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 24,
            hour: 10,
            minute: 0
        ))!
        let friday = calendar.startOfDay(for: now)
        let overdueAnchorStore = TestOverdueAnchorStore()
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = monday
        draft.scheduleDays = [.monday, .wednesday, .friday]
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let habitID = try repository.createHabit(from: draft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSPredicate(format: "habitID == %@", habitID as CVarArg)
        for completion in try context.fetch(request) {
            context.delete(completion)
        }
        try context.save()

        let finalized = try repository.reconcilePastDays(today: now)
        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        let dashboardHabit = try #require(try repository.fetchDashboardHabits().first { $0.id == habitID })

        #expect(finalized == 0)
        #expect(!details.skippedDays.contains(monday))
        #expect(!details.skippedDays.contains(wednesday))
        #expect(!details.skippedDays.contains(friday))
        #expect(details.needsHistoryReview)
        #expect(dashboardHabit.activeOverdueDay == friday)
        #expect(dashboardHabit.needsHistoryReview)
        #expect(overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar) == nil)
    }

    @Test
    func createHabitPrefillsPastScheduledDaysAsCompletedOnCreation() throws {
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
    func createHabitPrefillsOnlyScheduledPastDaysWhenHistoryFollowsSchedule() throws {
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
    func createHabitPrefillsEveryPastDayWhenHistoryCountsEveryDay() throws {
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
        #expect(details.skippedDays.isEmpty)
    }

    @Test
    func updateHabitSaveBlocksPastEditableGap() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
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
        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", yesterday as CVarArg),
        ])
        let completion = try #require(context.fetch(request).first)
        context.delete(completion)
        try context.save()

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(!details.completedDays.contains(yesterday))

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

        do {
            try repository.updateHabit(from: editDraft)
            Issue.record("Expected missing past history validation error.")
        } catch let error as EditableHistoryValidationError {
            guard case .missingHabitPastDays(let days) = error else {
                Issue.record("Expected missing habit days error.")
                return
            }
            #expect(days == [yesterday])
        }

        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(!updatedDetails.completedDays.contains(yesterday))
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
        #expect(!details.skippedDays.contains(yesterday))
        #expect(!details.completedDays.contains(unscheduledPastDay))

        let editDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            completedDays: [yesterday],
            skippedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(updatedDetails.completedDays.contains(yesterday))
        #expect(!updatedDetails.skippedDays.contains(yesterday))
        #expect(!updatedDetails.completedDays.contains(unscheduledPastDay))

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", unscheduledPastDay as CVarArg),
        ])
        #expect(try context.count(for: request) == 0)
    }

    @Test
    func updateHabitUsesPersistedHistoryModeWhenKeepingExplicitPastSelection() throws {
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

        var draft = CreateHabitDraft()
        draft.name = "Journal"
        draft.startDate = threeDaysAgo
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)

        let habitID = try repository.createHabit(from: draft)
        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", yesterday as CVarArg),
        ])
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
            completedDays: [yesterday],
            skippedDays: []
        )

        try repository.updateHabit(from: editDraft)

        let updatedDetails = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(updatedDetails.historyMode == .scheduleBased)
        #expect(!updatedDetails.completedDays.contains(threeDaysAgo))
        #expect(!updatedDetails.completedDays.contains(twoDaysAgo))
        #expect(updatedDetails.completedDays.contains(yesterday))
        #expect(!updatedDetails.skippedDays.contains(yesterday))
    }

    @Test
    func reconcilePastDaysLeavesPastHabitHistoryEmpty() throws {
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
        #expect(inserted == 0)

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(!details.completedDays.contains(yesterday))
        #expect(!details.skippedDays.contains(yesterday))
        #expect(details.needsHistoryReview)

        let secondInserted = try repository.reconcilePastDays(today: today)
        #expect(secondInserted == 0)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSPredicate(format: "habitID == %@", habitID as CVarArg)
        let completions = try context.fetch(request)
        #expect(completions.isEmpty)
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
    func reconcilePastDaysEveryDayLeavesAllPastHistoryEmpty() throws {
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
        #expect(inserted == 0)

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.historyMode == .everyDay)
        #expect(!details.skippedDays.contains(threeDaysAgo))
        #expect(!details.skippedDays.contains(twoDaysAgo))
        #expect(!details.skippedDays.contains(yesterday))
        #expect(details.completedDays.isEmpty)
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
            completedDays: created.completedDays,
            skippedDays: created.skippedDays
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
