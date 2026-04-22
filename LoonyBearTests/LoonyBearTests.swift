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
    func habitUpdateViaAppStateAutoFinalizesPastHistoryAndRefreshesDashboard() async throws {
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
        createDraft.scheduleDays = [.monday]
        createDraft.useScheduleForHistory = false
        let habitID = try await appState.createHabit(from: createDraft)

        let createdDetails = try #require(try appState.habitDetails(id: habitID))
        #expect(createdDetails.skippedDays.contains(yesterday))

        var completedDays = createdDetails.completedDays
        completedDays.remove(yesterday)
        var skippedDays = createdDetails.skippedDays
        skippedDays.remove(yesterday)
        let editDraft = EditHabitDraft(
            id: habitID,
            type: createdDetails.type,
            startDate: createdDetails.startDate,
            name: "Read Updated",
            scheduleDays: [.monday],
            reminderEnabled: false,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            completedDays: completedDays,
            skippedDays: skippedDays
        )

        try await appState.updateHabit(from: editDraft)

        let updatedDetails = try #require(try appState.habitDetails(id: habitID))
        #expect(updatedDetails.name == "Read Updated")
        #expect(updatedDetails.skippedDays.contains(yesterday))
        #expect(updatedDetails.skippedDays.contains(twoDaysAgo))
        #expect(!updatedDetails.completedDays.contains(yesterday))
        #expect(appState.actionErrorMessage == nil)

        let dashboardHabit = try #require(
            appState.dashboard.sections
                .flatMap { $0.habits }
                .first { $0.id == habitID }
        )
        #expect(dashboardHabit.name == "Read Updated")
    }

    @Test
    func pillUpdateViaAppStateAutoFinalizesPastHistoryAndRefreshesDashboard() async throws {
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
        createDraft.scheduleDays = [.monday]
        createDraft.useScheduleForHistory = false
        createDraft.takenDays = [twoDaysAgo, yesterday]
        let pillID = try await appState.createPill(from: createDraft)

        let createdDetails = try #require(try appState.pillDetails(id: pillID))
        #expect(createdDetails.takenDays.contains(yesterday))

        var takenDays = createdDetails.takenDays
        takenDays.remove(yesterday)
        var skippedDays = createdDetails.skippedDays
        skippedDays.remove(yesterday)
        let editDraft = EditPillDraft(
            id: pillID,
            name: "Vitamin D Updated",
            dosage: "2 tablets",
            details: createdDetails.details ?? "",
            startDate: createdDetails.startDate,
            scheduleDays: [.monday],
            reminderEnabled: false,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            takenDays: takenDays,
            skippedDays: skippedDays
        )

        try await appState.updatePill(from: editDraft)

        let updatedDetails = try #require(try appState.pillDetails(id: pillID))
        #expect(updatedDetails.name == "Vitamin D Updated")
        #expect(updatedDetails.dosage == "2 tablets")
        #expect(updatedDetails.takenDays.contains(twoDaysAgo))
        #expect(!updatedDetails.takenDays.contains(yesterday))
        #expect(updatedDetails.skippedDays.contains(yesterday))
        #expect(appState.actionErrorMessage == nil)

        let dashboardPill = try #require(appState.dashboard.pills.first { $0.id == pillID })
        #expect(dashboardPill.name == "Vitamin D Updated")
        #expect(dashboardPill.dosage == "2 tablets")
        #expect(dashboardPill.totalTakenDays == 1)
    }

    @Test
    func habitAppDidBecomeActiveReconcilesPastHistory() async throws {
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
        #expect(details.skippedDays.contains(yesterday))
    }

    @Test
    func pillAppDidBecomeActiveReconcilesPastHistory() async throws {
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
        #expect(details.skippedDays.contains(yesterday))
    }
}
