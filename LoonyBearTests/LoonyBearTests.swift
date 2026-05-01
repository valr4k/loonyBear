import CoreData
import Foundation
import Testing

@testable import LoonyBear

@MainActor
struct LoonyBearTests {
    @Test
    func weekdaySetSummaryReturnsExactListForCustomSets() {
        let custom: WeekdaySet = [.monday, .wednesday, .friday]

        #expect(WeekdaySet.daily.summary == "Daily")
        #expect(WeekdaySet.weekdays.summary == "Weekdays")
        #expect(WeekdaySet.weekends.summary == "Weekends")
        #expect(custom.summary == "Mon, Wed, Fri")
    }

    @Test
    func weekdaySetCompactSummaryReturnsCustomForCustomSets() {
        let custom: WeekdaySet = [.monday, .wednesday, .friday]

        #expect(WeekdaySet.daily.compactSummary == "Daily")
        #expect(WeekdaySet.weekdays.compactSummary == "Weekdays")
        #expect(WeekdaySet.weekends.compactSummary == "Weekends")
        #expect(custom.compactSummary == "Custom")
        #expect(custom.compactSummaryOrPlaceholder == "Custom")
    }

    @Test
    func customIntervalScheduleRuleUsesProvidedAnchor() {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = TestSupport.makeDate(2026, 5, 1)
        let rule = ScheduleRule.intervalDays(3)

        #expect(rule.summary == "Every 3 days")
        #expect(rule.compactSummary == "Every 3 days")
        #expect(rule.isValidSelection)
        #expect(rule.isScheduled(on: TestSupport.makeDate(2026, 5, 1), anchorDate: startDate, calendar: calendar))
        #expect(!rule.isScheduled(on: TestSupport.makeDate(2026, 5, 2), anchorDate: startDate, calendar: calendar))
        #expect(rule.isScheduled(on: TestSupport.makeDate(2026, 5, 4), anchorDate: startDate, calendar: calendar))
    }

    @Test
    func intervalPresetsUseActiveAnchorAndCustomRange() {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = TestSupport.makeDate(2026, 5, 20)

        #expect(ScheduleRule.intervalPreset(.daily).summary == "Daily")
        #expect(ScheduleRule.intervalPreset(.weekdays).isScheduled(
            on: TestSupport.makeDate(2026, 5, 22),
            anchorDate: anchor,
            calendar: calendar
        ))
        #expect(!ScheduleRule.intervalPreset(.weekends).isScheduled(
            on: TestSupport.makeDate(2026, 5, 22),
            anchorDate: anchor,
            calendar: calendar
        ))
        #expect(ScheduleRule.intervalPreset(.weekly).isScheduled(
            on: TestSupport.makeDate(2026, 5, 27),
            anchorDate: anchor,
            calendar: calendar
        ))
        #expect(!ScheduleRule.intervalPreset(.weekly).isScheduled(
            on: TestSupport.makeDate(2026, 5, 28),
            anchorDate: anchor,
            calendar: calendar
        ))
        #expect(ScheduleRule.intervalPreset(.biweekly).isScheduled(
            on: TestSupport.makeDate(2026, 6, 3),
            anchorDate: anchor,
            calendar: calendar
        ))
        #expect(!ScheduleRule.intervalDays(1).isValidSelection)
        #expect(ScheduleRule.intervalDays(14).isValidSelection)
        #expect(ScheduleRule.intervalDays(20).isValidSelection)
        #expect(!ScheduleRule.intervalDays(21).isValidSelection)
        #expect(ScheduleRule.intervalDays(14).summary == "Biweekly")
        #expect(ScheduleRule.intervalDays(14).compactSummary == "Biweekly")
    }

    @Test
    func scheduleHistoryUsesEffectiveFromAsIntervalAnchorAfterEdit() {
        let calendar = Calendar(identifier: .gregorian)
        let habitID = UUID()
        let startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        let editEffectiveFrom = TestSupport.makeDate(2026, 5, 20, calendar: calendar)
        let schedules = [
            TestSupport.makeSchedule(
                habitID: habitID,
                rule: .weekly(.daily),
                effectiveFrom: startDate,
                version: 1
            ),
            TestSupport.makeSchedule(
                habitID: habitID,
                rule: .intervalDays(2),
                effectiveFrom: editEffectiveFrom,
                version: 2
            ),
        ]

        #expect(HistoryScheduleApplicability.isScheduled(
            on: TestSupport.makeDate(2026, 5, 19, calendar: calendar),
            startDate: startDate,
            from: schedules,
            calendar: calendar
        ))
        #expect(HistoryScheduleApplicability.isScheduled(
            on: TestSupport.makeDate(2026, 5, 20, calendar: calendar),
            startDate: startDate,
            from: schedules,
            calendar: calendar
        ))
        #expect(!HistoryScheduleApplicability.isScheduled(
            on: TestSupport.makeDate(2026, 5, 21, calendar: calendar),
            startDate: startDate,
            from: schedules,
            calendar: calendar
        ))
        #expect(HistoryScheduleApplicability.isScheduled(
            on: TestSupport.makeDate(2026, 5, 22, calendar: calendar),
            startDate: startDate,
            from: schedules,
            calendar: calendar
        ))
    }

    @Test
    func scheduledCalendarDaysFollowScheduleHistory() {
        let calendar = Calendar(identifier: .gregorian)
        let habitID = UUID()
        let startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        let editEffectiveFrom = TestSupport.makeDate(2026, 5, 6, calendar: calendar)
        let schedules = [
            TestSupport.makeSchedule(
                habitID: habitID,
                weekdays: [.monday, .wednesday, .friday],
                effectiveFrom: startDate,
                version: 1
            ),
            TestSupport.makeSchedule(
                habitID: habitID,
                rule: .intervalDays(3),
                effectiveFrom: editEffectiveFrom,
                version: 2
            ),
        ]

        let scheduledDays = HistoryScheduleApplicability.scheduledDays(
            startDate: startDate,
            through: TestSupport.makeDate(2026, 5, 12, calendar: calendar),
            schedules: schedules,
            calendar: calendar
        )

        #expect(scheduledDays == [
            TestSupport.makeDate(2026, 5, 1, calendar: calendar),
            TestSupport.makeDate(2026, 5, 4, calendar: calendar),
            TestSupport.makeDate(2026, 5, 6, calendar: calendar),
            TestSupport.makeDate(2026, 5, 9, calendar: calendar),
            TestSupport.makeDate(2026, 5, 12, calendar: calendar),
        ])
    }

    @Test
    func overdueAndStreakUseEditedIntervalAnchor() {
        let calendar = Calendar(identifier: .gregorian)
        let habitID = UUID()
        let startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        let editEffectiveFrom = TestSupport.makeDate(2026, 5, 20, calendar: calendar)
        let may20 = editEffectiveFrom
        let may22 = TestSupport.makeDate(2026, 5, 22, calendar: calendar)
        let schedules = [
            TestSupport.makeSchedule(
                habitID: habitID,
                rule: .weekly(.daily),
                effectiveFrom: startDate,
                version: 1
            ),
            TestSupport.makeSchedule(
                habitID: habitID,
                rule: .intervalDays(2),
                effectiveFrom: editEffectiveFrom,
                version: 2
            ),
        ]

        let activeOverdueDay = ScheduledOverdueState.activeOverdueDay(
            startDate: startDate,
            schedules: schedules,
            reminderTime: nil,
            positiveDays: [],
            skippedDays: [],
            now: TestSupport.makeDate(2026, 5, 22, calendar: calendar).addingTimeInterval(12 * 60 * 60),
            calendar: calendar
        )
        let currentStreak = StreakEngine.currentStreak(
            completions: [
                TestSupport.makeCompletion(habitID: habitID, localDate: may20),
                TestSupport.makeCompletion(habitID: habitID, localDate: may22),
            ],
            schedules: schedules,
            startDate: startDate,
            today: may22,
            calendar: calendar
        )

        #expect(activeOverdueDay == may22)
        #expect(currentStreak == 2)
    }

    @Test
    func missingPastHistoryValidationMessagesDoNotListDates() {
        let missingDays = [
            TestSupport.makeDate(2026, 4, 27),
            TestSupport.makeDate(2026, 4, 28),
            TestSupport.makeDate(2026, 4, 29),
        ]

        let habitError = EditableHistoryValidationError.missingHabitPastDays(missingDays)
        let pillError = EditableHistoryValidationError.missingPillPastDays(missingDays)

        #expect(habitError.localizedDescription == "Choose Completed or Skipped for every past scheduled day before saving.")
        #expect(pillError.localizedDescription == "Choose Taken or Skipped for every past scheduled day before saving.")
        #expect(!habitError.localizedDescription.contains("Missing:"))
        #expect(!pillError.localizedDescription.contains("Missing:"))
        #expect(!habitError.localizedDescription.contains("Apr"))
        #expect(!pillError.localizedDescription.contains("Apr"))
    }

    @Test
    func habitDetailInspectionDoesNotMutateErrorState() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            pillRepository: pillRepository
        )
        let appState = HabitAppState(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: WidgetSyncService(),
            badgeService: badgeService
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

        switch appState.inspectHabitDetailsState(id: habitID) {
        case .integrityError(let message):
            #expect(message.contains("fetchHabitDetails"))
            #expect(appState.detailErrorMessage == nil)
        case .found, .notFound:
            Issue.record("Expected integrity error state.")
        }
    }

    @Test
    func habitDetailLoadPersistsIntegrityErrorMessage() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            pillRepository: pillRepository
        )
        let appState = HabitAppState(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: WidgetSyncService(),
            badgeService: badgeService
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

        switch appState.loadHabitDetailsState(id: habitID) {
        case .integrityError(let message):
            #expect(message.contains("fetchHabitDetails"))
            #expect(appState.detailErrorMessage == message)
        case .found, .notFound:
            Issue.record("Expected integrity error state.")
        }
    }

    @Test
    func pillDetailInspectionDoesNotMutateErrorState() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: repository
        )
        let appState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            badgeService: badgeService
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let pillID = try repository.createPill(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        switch appState.inspectPillDetailsState(id: pillID) {
        case .integrityError(let message):
            #expect(message.contains("fetchPillDetails"))
            #expect(appState.detailErrorMessage == nil)
        case .found, .notFound:
            Issue.record("Expected integrity error state.")
        }
    }

    @Test
    func pillDetailLoadPersistsIntegrityErrorMessage() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: repository
        )
        let appState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            badgeService: badgeService
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let pillID = try repository.createPill(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        switch appState.loadPillDetailsState(id: pillID) {
        case .integrityError(let message):
            #expect(message.contains("fetchPillDetails"))
            #expect(appState.detailErrorMessage == message)
        case .found, .notFound:
            Issue.record("Expected integrity error state.")
        }
    }

    @Test
    func habitUpdateViaAppStateBlocksMissingPastHistoryAndLeavesDashboardUnchanged() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            pillRepository: pillRepository
        )
        let appState = HabitAppState(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: WidgetSyncService(),
            badgeService: badgeService
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))

        var createDraft = CreateHabitDraft()
        createDraft.name = "Read"
        createDraft.startDate = twoDaysAgo
        createDraft.scheduleDays = .daily
        let habitID = try await appState.createHabit(from: createDraft)

        let createdDetails = try #require(try appState.habitDetails(id: habitID))
        #expect(createdDetails.completedDays.contains(yesterday))
        #expect(createdDetails.completedDays.contains(twoDaysAgo))

        var completedDays = createdDetails.completedDays
        completedDays.remove(yesterday)
        let editDraft = EditHabitDraft(
            id: habitID,
            type: createdDetails.type,
            startDate: createdDetails.startDate,
            name: "Read Updated",
            scheduleDays: .daily,
            reminderEnabled: false,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            completedDays: completedDays,
            skippedDays: createdDetails.skippedDays
        )

        do {
            try await appState.updateHabit(from: editDraft)
            Issue.record("Expected missing past history validation error.")
        } catch let error as EditableHistoryValidationError {
            guard case .missingHabitPastDays(let days) = error else {
                Issue.record("Expected missing habit days error.")
                return
            }
            #expect(days == [yesterday])
        }

        let updatedDetails = try #require(try appState.habitDetails(id: habitID))
        #expect(updatedDetails.name == "Read")
        #expect(updatedDetails.completedDays.contains(yesterday))
        #expect(updatedDetails.completedDays.contains(twoDaysAgo))
        #expect(updatedDetails.skippedDays.isEmpty)
        #expect(appState.actionErrorMessage == "Choose Completed or Skipped for every past scheduled day before saving.")

        let dashboardHabit = try #require(
            appState.dashboard.sections
                .flatMap { $0.habits }
                .first { $0.id == habitID }
        )
        #expect(dashboardHabit.name == "Read")
    }

    @Test
    func pillUpdateViaAppStateBlocksMissingPastHistoryAndLeavesDashboardUnchanged() async throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: repository
        )
        let appState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            badgeService: badgeService
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))

        var createDraft = PillDraft()
        createDraft.name = "Vitamin D"
        createDraft.dosage = "1 tablet"
        createDraft.startDate = twoDaysAgo
        createDraft.scheduleDays = .daily
        createDraft.takenDays = [twoDaysAgo, yesterday]
        let pillID = try await appState.createPill(from: createDraft)

        let createdDetails = try #require(try appState.pillDetails(id: pillID))
        #expect(createdDetails.takenDays.contains(yesterday))
        #expect(createdDetails.takenDays.contains(twoDaysAgo))

        var takenDays = createdDetails.takenDays
        takenDays.remove(yesterday)
        let editDraft = EditPillDraft(
            id: pillID,
            name: "Vitamin D Updated",
            dosage: "2 tablets",
            details: createdDetails.details ?? "",
            startDate: createdDetails.startDate,
            scheduleDays: .daily,
            reminderEnabled: false,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            takenDays: takenDays,
            skippedDays: createdDetails.skippedDays
        )

        do {
            try await appState.updatePill(from: editDraft)
            Issue.record("Expected missing past history validation error.")
        } catch let error as EditableHistoryValidationError {
            guard case .missingPillPastDays(let days) = error else {
                Issue.record("Expected missing pill days error.")
                return
            }
            #expect(days == [yesterday])
        }

        let updatedDetails = try #require(try appState.pillDetails(id: pillID))
        #expect(updatedDetails.name == "Vitamin D")
        #expect(updatedDetails.dosage == "1 tablet")
        #expect(updatedDetails.takenDays.contains(yesterday))
        #expect(updatedDetails.takenDays.contains(twoDaysAgo))
        #expect(updatedDetails.skippedDays.isEmpty)
        #expect(appState.actionErrorMessage == "Choose Taken or Skipped for every past scheduled day before saving.")

        let dashboardPill = try #require(appState.dashboard.pills.first { $0.id == pillID })
        #expect(dashboardPill.name == "Vitamin D")
        #expect(dashboardPill.dosage == "1 tablet")
        #expect(dashboardPill.totalTakenDays == 2)
    }

    @Test
    func habitAppDidBecomeActiveLeavesManualHistoryGapForReview() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            pillRepository: pillRepository
        )
        let appState = HabitAppState(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: WidgetSyncService(),
            badgeService: badgeService
        )

        let context = persistence.container.viewContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let habitID = UUID()
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Read", forKey: "name")
        habit.setValue(yesterday, forKey: "startDate")
        habit.setValue(Int32(0), forKey: "sortOrder")
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

        await appState.handleAppDidBecomeActive()

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(!details.completedDays.contains(yesterday))
        #expect(!details.skippedDays.contains(yesterday))
        #expect(details.needsHistoryReview)

        let dashboardHabit = try #require(
            appState.dashboard.sections
                .flatMap { $0.habits }
                .first { $0.id == habitID }
        )
        #expect(dashboardHabit.needsHistoryReview)
    }

    @Test
    func pillAppDidBecomeActiveLeavesManualHistoryGapForReview() async throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: habitRepository),
            pillRepository: repository
        )
        let appState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            badgeService: badgeService
        )

        let context = persistence.container.viewContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let pillID = UUID()
        let pill = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
        pill.setValue(pillID, forKey: "id")
        pill.setValue("Vitamin D", forKey: "name")
        pill.setValue("1 tablet", forKey: "dosage")
        pill.setValue(yesterday, forKey: "startDate")
        pill.setValue(Int32(0), forKey: "sortOrder")
        pill.setValue(PillHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        pill.setValue(false, forKey: "reminderEnabled")
        pill.setValue(Date(), forKey: "createdAt")
        pill.setValue(Date(), forKey: "updatedAt")
        pill.setValue(Int32(1), forKey: "version")

        let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
        schedule.setValue(UUID(), forKey: "id")
        schedule.setValue(pillID, forKey: "pillID")
        schedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        schedule.setValue(yesterday, forKey: "effectiveFrom")
        schedule.setValue(Date(), forKey: "createdAt")
        schedule.setValue(Int32(1), forKey: "version")
        schedule.setValue(pill, forKey: "pill")
        try context.save()

        await appState.handleAppDidBecomeActive()

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(!details.skippedDays.contains(yesterday))
        #expect(!details.takenDays.contains(yesterday))
        #expect(details.needsHistoryReview)

        let dashboardPill = try #require(appState.dashboard.pills.first { $0.id == pillID })
        #expect(dashboardPill.needsHistoryReview)
    }
}
