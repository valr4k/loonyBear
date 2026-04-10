import Foundation
import Testing

@testable import LoonyBear

@Suite
struct CoreDataPillRepositoryTests {
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
}
