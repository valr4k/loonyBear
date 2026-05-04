import Foundation
import CoreData
import Testing

@testable import LoonyBear

@MainActor
@Suite
struct CoreDataPillRepositoryTests {
    @Test
    func dashboardIntervalPillShowsNextScheduledWeekdays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = TestSupport.makeDate(2026, 5, 3, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { today.addingTimeInterval(10 * 60 * 60) })
        )

        var draft = PillDraft()
        draft.name = "Interval pill"
        draft.dosage = "1 tablet"
        draft.startDate = today
        draft.scheduleRule = .intervalDays(3)

        let pillID = try repository.createPill(from: draft)
        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })

        #expect(dashboardPill.scheduleSummary == "Next: Sun, Wed, Sat")
    }

    @Test
    func archiveAndRestorePillDisablesDashboardActivity() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 10, minute: 0))!
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var draft = PillDraft()
        draft.name = "Archive pill"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        draft.scheduleRule = .weekly(.daily)
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)

        let pillID = try repository.createPill(from: draft)
        try repository.setPillArchived(id: pillID, isArchived: true)

        let archivedPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })

        #expect(archivedPill.isArchived)
        #expect(!archivedPill.isReminderScheduledToday)
        #expect(!archivedPill.isScheduledToday)
        #expect(archivedPill.activeOverdueDay == nil)
        #expect(!archivedPill.needsHistoryReview)

        try repository.setPillArchived(id: pillID, isArchived: false)

        let restoredPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        #expect(!restoredPill.isArchived)
    }

    @Test
    func oneTimePillAutoArchivesAfterTaken() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar).addingTimeInterval(10 * 60 * 60)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var draft = PillDraft()
        draft.name = "One-time pill"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        draft.scheduleRule = .oneTime

        let pillID = try repository.createPill(from: draft)
        let activePill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })

        #expect(!activePill.isArchived)
        #expect(activePill.isScheduledToday)

        try repository.markPillTaken(id: pillID, on: now)

        let archivedPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        #expect(archivedPill.isArchived)
        #expect(!archivedPill.isScheduledToday)
        #expect(archivedPill.activeOverdueDay == nil)
    }

    @Test
    func pillEndDateAutoArchivesAfterLastScheduledDayBeforeEndDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let finalScheduledDay = TestSupport.makeDate(2026, 5, 18, calendar: calendar)
        let now = finalScheduledDay.addingTimeInterval(10 * 60 * 60)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var draft = PillDraft()
        draft.name = "Ended pill"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        draft.endDate = TestSupport.makeDate(2026, 5, 20, calendar: calendar)
        draft.scheduleRule = .weekly(.monday)

        let pillID = try repository.createPill(from: draft)
        let activePill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })

        #expect(!activePill.isArchived)

        try repository.markPillTaken(id: pillID, on: finalScheduledDay)

        let archivedPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        #expect(archivedPill.isArchived)
        #expect(archivedPill.activeOverdueDay == nil)
    }

    @Test
    func createPillBlocksMoreThanTwentyPills() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Vitamin"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily

        for index in 1 ... 20 {
            draft.name = "Vitamin \(index)"
            _ = try repository.createPill(from: draft)
        }

        draft.name = "Vitamin 21"

        do {
            _ = try repository.createPill(from: draft)
            Issue.record("Expected pill creation to stop at 20 pills.")
        } catch let error as PillRepositoryError {
            #expect(error.localizedDescription == "Limit reached. You can add up to 20 pills.")
        }

        #expect(try repository.fetchDashboardPills().count == 20)
    }

    @Test
    func futurePillHasNoTodayStateButShowsScheduledDotsFromStartDateMonth() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 3, calendar: calendar)
        let futureStartDate = TestSupport.makeDate(2026, 7, 14, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var draft = PillDraft()
        draft.name = "Future pill"
        draft.dosage = "1 tablet"
        draft.startDate = futureStartDate
        draft.scheduleRule = .weekly(.daily)
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)

        let pillID = try repository.createPill(from: draft)
        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        let details = try #require(try repository.fetchPillDetails(id: pillID))

        #expect(!dashboardPill.isReminderScheduledToday)
        #expect(!dashboardPill.isScheduledToday)
        #expect(!dashboardPill.isTakenToday)
        #expect(!dashboardPill.isSkippedToday)
        #expect(!dashboardPill.needsHistoryReview)
        #expect(dashboardPill.activeOverdueDay == nil)
        #expect(dashboardPill.startsInFuture)
        #expect(dashboardPill.futureStartDate == futureStartDate)
        #expect(details.requiredPastScheduledDays.isEmpty)
        #expect(details.scheduledDates.contains(futureStartDate))
        #expect(details.scheduledDates.contains(TestSupport.makeDate(2026, 7, 31, calendar: calendar)))
    }

    @Test
    func updatePillUsesSelectedEffectiveFromWhenSelectedDayHasState() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 3, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = PillDraft()
        createDraft.name = "Move pill"
        createDraft.dosage = "1 tablet"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        createDraft.scheduleRule = .weekly(.daily)

        let pillID = try repository.createPill(from: createDraft)
        try repository.markPillTaken(id: pillID, on: now)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        var editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleRule: .intervalDays(3),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )
        editDraft.scheduleEffectiveFrom = now

        try repository.updatePill(from: editDraft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillScheduleVersion")
        request.predicate = NSPredicate(format: "pillID == %@", pillID as CVarArg)
        let schedules = try context.fetch(request)
        let latest = try #require(schedules.max {
            ($0.value(forKey: "version") as? Int32 ?? 0) < ($1.value(forKey: "version") as? Int32 ?? 0)
        })

        #expect(latest.value(forKey: "effectiveFrom") as? Date == now)
        #expect(CoreDataScheduleSupport.rule(from: latest) == .intervalDays(3))
    }

    @Test
    func updatePillAutomaticallyUsesTodayAsEffectiveFrom() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = PillDraft()
        createDraft.name = "Auto effective"
        createDraft.dosage = "1 tablet"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        createDraft.scheduleRule = .weekly(.daily)

        let pillID = try repository.createPill(from: createDraft)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleRule: .weekly(.wednesday),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )

        try repository.updatePill(from: editDraft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillScheduleVersion")
        request.predicate = NSPredicate(format: "pillID == %@", pillID as CVarArg)
        let schedules = try context.fetch(request)
        let latest = try #require(schedules.max {
            ($0.value(forKey: "version") as? Int32 ?? 0) < ($1.value(forKey: "version") as? Int32 ?? 0)
        })

        #expect(latest.value(forKey: "effectiveFrom") as? Date == now)
        #expect(CoreDataScheduleSupport.rule(from: latest) == .weekly(.wednesday))
    }

    @Test
    func updatePillAutomaticallyKeepsTodayWhenTodayHasExplicitState() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = PillDraft()
        createDraft.name = "Explicit today"
        createDraft.dosage = "1 tablet"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        createDraft.scheduleRule = .weekly(.daily)

        let pillID = try repository.createPill(from: createDraft)
        try repository.markPillTaken(id: pillID, on: now)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleRule: .intervalDays(3),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )

        try repository.updatePill(from: editDraft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillScheduleVersion")
        request.predicate = NSPredicate(format: "pillID == %@", pillID as CVarArg)
        let schedules = try context.fetch(request)
        let latest = try #require(schedules.max {
            ($0.value(forKey: "version") as? Int32 ?? 0) < ($1.value(forKey: "version") as? Int32 ?? 0)
        })

        #expect(latest.value(forKey: "effectiveFrom") as? Date == now)
        #expect(CoreDataScheduleSupport.rule(from: latest) == .intervalDays(3))
    }

    @Test
    func updateFuturePillAutomaticallyUsesStartDateAsEffectiveFrom() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = PillDraft()
        createDraft.name = "Future auto effective"
        createDraft.dosage = "1 tablet"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 11, calendar: calendar)
        createDraft.scheduleRule = .weekly(.daily)

        let pillID = try repository.createPill(from: createDraft)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleRule: .weekly(.friday),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )

        try repository.updatePill(from: editDraft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillScheduleVersion")
        request.predicate = NSPredicate(format: "pillID == %@", pillID as CVarArg)
        let schedules = try context.fetch(request)
        let latest = try #require(schedules.max {
            ($0.value(forKey: "version") as? Int32 ?? 0) < ($1.value(forKey: "version") as? Int32 ?? 0)
        })

        #expect(latest.value(forKey: "effectiveFrom") as? Date == TestSupport.makeDate(2026, 5, 11, calendar: calendar))
        #expect(CoreDataScheduleSupport.rule(from: latest) == .weekly(.friday))
    }

    @Test
    func updateFuturePillDashboardUsesSavedLatestScheduleVersion() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = PillDraft()
        createDraft.name = "Future pill"
        createDraft.dosage = "1 tablet"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 11, calendar: calendar)
        createDraft.scheduleRule = .weekly([.tuesday, .wednesday])

        let pillID = try repository.createPill(from: createDraft)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        var editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleRule: .weekly(.friday),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )
        editDraft.scheduleEffectiveFrom = TestSupport.makeDate(2026, 5, 15, calendar: calendar)

        try repository.updatePill(from: editDraft)

        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        let updatedDetails = try #require(try repository.fetchPillDetails(id: pillID))

        #expect(dashboardPill.scheduleSummary == "Weekly on Fri")
        #expect(updatedDetails.scheduleRule == .weekly(.friday))
    }

    @Test
    func updatePillRemovesFutureScheduleVersionsReplacedByEarlierEffectiveFrom() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = TestSupport.makeDate(2026, 5, 4, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now })
        )

        var createDraft = PillDraft()
        createDraft.name = "Replace future"
        createDraft.dosage = "1 tablet"
        createDraft.startDate = TestSupport.makeDate(2026, 5, 1, calendar: calendar)
        createDraft.scheduleRule = .weekly(.daily)

        let pillID = try repository.createPill(from: createDraft)
        let details = try #require(try repository.fetchPillDetails(id: pillID))

        var futureDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleRule: .weekly(.weekends),
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )
        futureDraft.scheduleEffectiveFrom = TestSupport.makeDate(2026, 5, 9, calendar: calendar)
        try repository.updatePill(from: futureDraft)

        var replacementDraft = futureDraft
        replacementDraft.scheduleRule = .weekly(.daily)
        replacementDraft.scheduleEffectiveFrom = TestSupport.makeDate(2026, 5, 5, calendar: calendar)
        try repository.updatePill(from: replacementDraft)

        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        let updatedDetails = try #require(try repository.fetchPillDetails(id: pillID))

        #expect(dashboardPill.scheduleSummary == "Daily")
        #expect(updatedDetails.scheduleRule == .weekly(.daily))
        #expect(updatedDetails.scheduleHistory.contains { $0.rule == .weekly(.daily) && $0.effectiveFrom == TestSupport.makeDate(2026, 5, 5, calendar: calendar) })
        #expect(!updatedDetails.scheduleHistory.contains { $0.rule == .weekly(.weekends) && $0.effectiveFrom == TestSupport.makeDate(2026, 5, 9, calendar: calendar) })
    }

    @Test
    func dashboardPillsSortByReminderTimeThenSortOrder() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var laterReminder = PillDraft()
        laterReminder.name = "Later"
        laterReminder.dosage = "1 tablet"
        laterReminder.startDate = TestSupport.makeDate(2026, 4, 1)
        laterReminder.scheduleDays = .daily
        laterReminder.reminderEnabled = true
        laterReminder.reminderTime = ReminderTime(hour: 18, minute: 0)
        _ = try repository.createPill(from: laterReminder)

        var earlierReminder = PillDraft()
        earlierReminder.name = "Earlier"
        earlierReminder.dosage = "1 tablet"
        earlierReminder.startDate = TestSupport.makeDate(2026, 4, 1)
        earlierReminder.scheduleDays = .daily
        earlierReminder.reminderEnabled = true
        earlierReminder.reminderTime = ReminderTime(hour: 9, minute: 0)
        _ = try repository.createPill(from: earlierReminder)

        var sameTimeFirst = PillDraft()
        sameTimeFirst.name = "Same Time First"
        sameTimeFirst.dosage = "1 tablet"
        sameTimeFirst.startDate = TestSupport.makeDate(2026, 4, 1)
        sameTimeFirst.scheduleDays = .daily
        sameTimeFirst.reminderEnabled = true
        sameTimeFirst.reminderTime = ReminderTime(hour: 12, minute: 0)
        _ = try repository.createPill(from: sameTimeFirst)

        var sameTimeSecond = PillDraft()
        sameTimeSecond.name = "Same Time Second"
        sameTimeSecond.dosage = "1 tablet"
        sameTimeSecond.startDate = TestSupport.makeDate(2026, 4, 1)
        sameTimeSecond.scheduleDays = .daily
        sameTimeSecond.reminderEnabled = true
        sameTimeSecond.reminderTime = ReminderTime(hour: 12, minute: 0)
        _ = try repository.createPill(from: sameTimeSecond)

        var noReminder = PillDraft()
        noReminder.name = "No Reminder"
        noReminder.dosage = "1 tablet"
        noReminder.startDate = TestSupport.makeDate(2026, 4, 1)
        noReminder.scheduleDays = .daily
        noReminder.reminderEnabled = false
        _ = try repository.createPill(from: noReminder)

        let pills = try repository.fetchDashboardPills().map(\.name)

        #expect(pills == [
            "Earlier",
            "Same Time First",
            "Same Time Second",
            "Later",
            "No Reminder",
        ])
    }

    @Test
    func skipDoesNotCountAsIntakeAndTakeOverwritesSkip() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily

        let pillID = try repository.createPill(from: draft)

        try repository.skipPillToday(id: pillID)

        let skippedDashboardPill = try #require(
            try repository.fetchDashboardPills().first { $0.id == pillID }
        )
        let skippedDetails = try #require(try repository.fetchPillDetails(id: pillID))

        #expect(skippedDashboardPill.isSkippedToday)
        #expect(!skippedDashboardPill.isTakenToday)
        #expect(skippedDetails.totalTakenDays == 0)
        #expect(skippedDetails.takenDays.isEmpty)
        #expect(skippedDetails.skippedDays.count == 1)

        try repository.markTakenToday(id: pillID)

        let takenDashboardPill = try #require(
            try repository.fetchDashboardPills().first { $0.id == pillID }
        )
        let takenDetails = try #require(try repository.fetchPillDetails(id: pillID))

        #expect(!takenDashboardPill.isSkippedToday)
        #expect(takenDashboardPill.isTakenToday)
        #expect(takenDetails.totalTakenDays == 1)
        #expect(takenDetails.takenDays.count == 1)
        #expect(takenDetails.skippedDays.isEmpty)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSPredicate(format: "pillID == %@", pillID as CVarArg)
        let intakes = try context.fetch(request)

        #expect(intakes.count == 1)
        #expect(intakes.first?.value(forKey: "sourceRaw") as? String == PillCompletionSource.swipe.rawValue)
    }

    @Test
    func markTakenTodayDeduplicatesExistingRowsForToday() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily

        let pillID = try repository.createPill(from: draft)
        let pillRequest = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        pillRequest.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        let pill = try #require(context.fetch(pillRequest).first)
        let today = Calendar.current.startOfDay(for: Date())

        for dayOffset in 0..<2 {
            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(pillID, forKey: "pillID")
            intake.setValue(today, forKey: "localDate")
            intake.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
            intake.setValue(Date().addingTimeInterval(TimeInterval(dayOffset)), forKey: "createdAt")
            intake.setValue(pill, forKey: "pill")
        }
        try context.save()

        try repository.markTakenToday(id: pillID)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", today as CVarArg),
        ])
        let intakes = try context.fetch(request)

        #expect(intakes.count == 1)
        #expect(intakes.first?.value(forKey: "sourceRaw") as? String == PillCompletionSource.swipe.rawValue)
    }

    @Test
    func clearPillTodayImmediatelyRestoresOverdueWhenReminderAlreadyPassed() throws {
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
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        draft.scheduleDays = calendar.weekdaySet(for: today)
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)

        let pillID = try repository.createPill(from: draft)
        try repository.markTakenToday(id: pillID)
        try repository.clearPillDayStateToday(id: pillID)

        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        #expect(!dashboardPill.isTakenToday)
        #expect(!dashboardPill.isSkippedToday)
        #expect(dashboardPill.activeOverdueDay == today)
        #expect(overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar) == today)
    }

    @Test
    func updatePillCanClearEditableSkippedDay() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily

        let pillID = try repository.createPill(from: draft)
        try repository.skipPillToday(id: pillID)

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            takenDays: [],
            skippedDays: []
        )

        try repository.updatePill(from: editDraft)

        let updatedDetails = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(updatedDetails.takenDays.isEmpty)
        #expect(updatedDetails.skippedDays.isEmpty)
    }

    @Test
    func updatePillImmediatelyAnchorsTodayOverdueWhenReminderAlreadyPassed() throws {
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
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        draft.scheduleDays = calendar.weekdaySet(for: today)
        draft.reminderEnabled = false

        let pillID = try repository.createPill(from: draft)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleDays: details.scheduleDays,
            reminderEnabled: true,
            reminderTime: ReminderTime(hour: 9, minute: 0),
            takenDays: [],
            skippedDays: []
        )

        try repository.updatePill(from: editDraft)

        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })
        #expect(dashboardPill.activeOverdueDay == today)
        #expect(overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar) == today)
    }

    @Test
    func reconcilePastDaysAnchorsMissedPastPillReminderWithoutStoredAnchor() throws {
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
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = yesterday
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let pillID = try repository.createPill(from: draft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", yesterday as CVarArg),
        ])
        for intake in try context.fetch(request) {
            context.delete(intake)
        }
        try context.save()

        let finalized = try repository.reconcilePastDays(today: now)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })

        #expect(finalized == 0)
        #expect(!details.needsHistoryReview)
        #expect(details.requiredPastScheduledDays.contains(yesterday))
        #expect(details.activeOverdueDay == yesterday)
        #expect(dashboardPill.activeOverdueDay == yesterday)
        #expect(!dashboardPill.needsHistoryReview)
        #expect(overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar) == nil)
    }

    @Test
    func reconcilePastDaysKeepsOlderDuePillDaysAsHistoryGaps() throws {
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
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext,
            calendar: calendar,
            clock: AppClock(calendar: calendar, now: { now }),
            overdueAnchorStore: overdueAnchorStore
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = monday
        draft.scheduleDays = [.monday, .wednesday, .friday]
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 0)
        let pillID = try repository.createPill(from: draft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSPredicate(format: "pillID == %@", pillID as CVarArg)
        for intake in try context.fetch(request) {
            context.delete(intake)
        }
        try context.save()

        let finalized = try repository.reconcilePastDays(today: now)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let dashboardPill = try #require(try repository.fetchDashboardPills().first { $0.id == pillID })

        #expect(finalized == 0)
        #expect(!details.skippedDays.contains(monday))
        #expect(!details.skippedDays.contains(wednesday))
        #expect(!details.skippedDays.contains(friday))
        #expect(details.needsHistoryReview)
        #expect(dashboardPill.activeOverdueDay == friday)
        #expect(dashboardPill.needsHistoryReview)
        #expect(overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar) == nil)
    }

    @Test
    func updatePillSaveBlocksPastEditableGap() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = yesterday
        draft.scheduleDays = .daily
        draft.useScheduleForHistory = false

        let pillID = try repository.createPill(from: draft)
        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", yesterday as CVarArg),
        ])
        let intake = try #require(context.fetch(request).first)
        context.delete(intake)
        try context.save()

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(!details.skippedDays.contains(yesterday))

        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            takenDays: [],
            skippedDays: []
        )

        do {
            try repository.updatePill(from: editDraft)
            Issue.record("Expected missing past history validation error.")
        } catch let error as EditableHistoryValidationError {
            guard case .missingPillPastDays(let days) = error else {
                Issue.record("Expected missing pill days error.")
                return
            }
            #expect(days == [yesterday])
        }

        let updatedDetails = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(!updatedDetails.skippedDays.contains(yesterday))
        #expect(!updatedDetails.takenDays.contains(yesterday))
    }

    @Test
    func scheduleBasedPillDoesNotCreateSkippedForPastUnscheduledDays() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
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

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = unscheduledPastDay
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)
        draft.useScheduleForHistory = true

        let pillID = try repository.createPill(from: draft)
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(details.historyMode == .scheduleBased)
        #expect(details.takenDays.contains(yesterday))
        #expect(!details.skippedDays.contains(yesterday))
        #expect(!details.skippedDays.contains(unscheduledPastDay))

        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            takenDays: [yesterday],
            skippedDays: []
        )

        try repository.updatePill(from: editDraft)

        let updatedDetails = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(updatedDetails.takenDays.contains(yesterday))
        #expect(!updatedDetails.skippedDays.contains(yesterday))
        #expect(!updatedDetails.skippedDays.contains(unscheduledPastDay))

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", unscheduledPastDay as CVarArg),
        ])
        #expect(try context.count(for: request) == 0)
    }

    @Test
    func updatePillUsesPersistedHistoryModeWhenKeepingExplicitPastSelection() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = twoDaysAgo
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)
        draft.useScheduleForHistory = true

        let pillID = try repository.createPill(from: draft)
        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", yesterday as CVarArg),
        ])
        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(details.takenDays.contains(yesterday))

        let editDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime(hour: 9, minute: 0),
            takenDays: [yesterday],
            skippedDays: []
        )

        try repository.updatePill(from: editDraft)

        let updatedDetails = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(updatedDetails.historyMode == .scheduleBased)
        #expect(updatedDetails.takenDays.contains(yesterday))
        #expect(!updatedDetails.skippedDays.contains(yesterday))
        #expect(!updatedDetails.skippedDays.contains(twoDaysAgo))
    }

    @Test
    func everyDayHistoryPillPrefillsPastDaysOnCreation() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))

        var draft = PillDraft()
        draft.name = "Magnesium"
        draft.dosage = "1 capsule"
        draft.startDate = twoDaysAgo
        draft.scheduleDays = calendar.weekdaySet(for: yesterday)
        draft.useScheduleForHistory = false

        let pillID = try repository.createPill(from: draft)
        let details = try #require(try repository.fetchPillDetails(id: pillID))

        #expect(details.historyMode == .everyDay)
        #expect(details.takenDays.contains(yesterday))
        #expect(details.takenDays.contains(twoDaysAgo))
        #expect(details.skippedDays.isEmpty)
    }

    @Test
    func reconcilePastDaysLeavesPastPillHistoryEmpty() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        let pillID = UUID()
        let pill = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
        pill.setValue(pillID, forKey: "id")
        pill.setValue("Vitamin D", forKey: "name")
        pill.setValue("1 tablet", forKey: "dosage")
        pill.setValue(Int32(0), forKey: "sortOrder")
        pill.setValue(yesterday, forKey: "startDate")
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

        let inserted = try repository.reconcilePastDays(today: today)
        #expect(inserted == 0)

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(!details.skippedDays.contains(yesterday))
        #expect(!details.takenDays.contains(yesterday))
        #expect(details.needsHistoryReview)

        let secondInserted = try repository.reconcilePastDays(today: today)
        #expect(secondInserted == 0)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSPredicate(format: "pillID == %@", pillID as CVarArg)
        let intakes = try context.fetch(request)
        #expect(intakes.isEmpty)
    }

    @Test
    func clearRemovesSkippedStateAndReturnsPillToNormalDayState() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Magnesium"
        draft.dosage = "1 capsule"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily

        let pillID = try repository.createPill(from: draft)

        try repository.skipPillToday(id: pillID)
        try repository.clearPillDayStateToday(id: pillID)

        let dashboardPill = try #require(
            try repository.fetchDashboardPills().first { $0.id == pillID }
        )
        let details = try #require(try repository.fetchPillDetails(id: pillID))

        #expect(!dashboardPill.isSkippedToday)
        #expect(!dashboardPill.isTakenToday)
        #expect(details.takenDays.isEmpty)
        #expect(details.skippedDays.isEmpty)
        #expect(details.totalTakenDays == 0)
    }

    @Test
    func fetchDashboardPillsFailsOnCorruptedRow() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let pillID = UUID()
        let object = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
        object.setValue(pillID, forKey: "id")
        object.setValue("Vitamin D", forKey: "name")
        object.setValue("1 tablet", forKey: "dosage")
        object.setValue(Date(), forKey: "startDate")
        object.setValue(PillHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        object.setValue(false, forKey: "reminderEnabled")
        object.setValue(Date(), forKey: "createdAt")
        object.setValue(Date(), forKey: "updatedAt")

        let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
        intake.setValue(UUID(), forKey: "id")
        intake.setValue(pillID, forKey: "pillID")
        intake.setValue(Calendar.current.startOfDay(for: Date()), forKey: "localDate")
        intake.setValue("broken_source", forKey: "sourceRaw")
        intake.setValue(Date(), forKey: "createdAt")
        intake.setValue(object, forKey: "pill")
        try context.save()

        do {
            _ = try repository.fetchDashboardPills()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchDashboardPills")
            #expect(error.report.issues.count > 0)
        }
    }

    @Test
    func fetchPillDetailsFailsWhenReminderMinuteIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Corrupted Details"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 9, minute: 15)
        let pillID = try repository.createPill(from: draft)

        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        do {
            _ = try repository.fetchPillDetails(id: pillID)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "fetchPillDetails")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func createEditDeletePillSmoke() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        let pillID = try repository.createPill(from: draft)

        let created = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(created.name == "Vitamin D")

        let editDraft = EditPillDraft(
            id: pillID,
            name: "Vitamin D3",
            dosage: "2 tablets",
            details: "After breakfast",
            startDate: created.startDate,
            scheduleDays: .weekends,
            reminderEnabled: true,
            reminderTime: ReminderTime(hour: 8, minute: 15),
            takenDays: created.takenDays,
            skippedDays: created.skippedDays
        )
        try repository.updatePill(from: editDraft)

        let updated = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(updated.name == "Vitamin D3")
        #expect(updated.dosage == "2 tablets")
        #expect(updated.scheduleDays == .weekends)
        #expect(updated.reminderEnabled)

        try repository.deletePill(id: pillID)
        #expect(try repository.fetchDashboardPills().isEmpty)
    }
}
