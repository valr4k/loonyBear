import Foundation
import CoreData
import Testing

@testable import LoonyBear

@Suite
struct CoreDataPillRepositoryTests {
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

        let pills = repository.fetchDashboardPills().map(\.name)

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
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily

        let pillID = try repository.createPill(from: draft)

        try repository.skipPillToday(id: pillID)

        let skippedDashboardPill = try #require(
            repository.fetchDashboardPills().first { $0.id == pillID }
        )
        let skippedDetails = try #require(repository.fetchPillDetails(id: pillID))

        #expect(skippedDashboardPill.isSkippedToday)
        #expect(!skippedDashboardPill.isTakenToday)
        #expect(skippedDetails.totalTakenDays == 0)
        #expect(skippedDetails.takenDays.isEmpty)
        #expect(skippedDetails.skippedDays.count == 1)

        try repository.markTakenToday(id: pillID)

        let takenDashboardPill = try #require(
            repository.fetchDashboardPills().first { $0.id == pillID }
        )
        let takenDetails = try #require(repository.fetchPillDetails(id: pillID))

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

        let details = try #require(repository.fetchPillDetails(id: pillID))
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

        let updatedDetails = try #require(repository.fetchPillDetails(id: pillID))
        #expect(updatedDetails.takenDays.isEmpty)
        #expect(updatedDetails.skippedDays.isEmpty)
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
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily

        let pillID = try repository.createPill(from: draft)

        try repository.skipPillToday(id: pillID)
        try repository.clearPillDayStateToday(id: pillID)

        let dashboardPill = try #require(
            repository.fetchDashboardPills().first { $0.id == pillID }
        )
        let details = try #require(repository.fetchPillDetails(id: pillID))

        #expect(!dashboardPill.isSkippedToday)
        #expect(!dashboardPill.isTakenToday)
        #expect(details.takenDays.isEmpty)
        #expect(details.skippedDays.isEmpty)
        #expect(details.totalTakenDays == 0)
    }
}
