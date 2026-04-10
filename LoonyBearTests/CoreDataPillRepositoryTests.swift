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
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
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
            takenDays: [],
            skippedDays: []
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
