import CoreData
import Foundation
import Testing

@testable import LoonyBear

@Suite
struct BackupServiceTests {
    @Test
    func restoreArchiveRejectsUnsupportedSchemaAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )

        var draft = CreateHabitDraft()
        draft.name = "Existing"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        draft.reminderEnabled = false
        _ = try repository.createHabit(from: draft)

        let archive = BackupArchive(
            schemaVersion: 999,
            exportedAt: Date(),
            habits: [],
            scheduleVersions: [],
            completionRecords: [],
            ordering: []
        )

        do {
            try service.restoreArchive(archive)
            Issue.record("Expected unsupported schema version error.")
        } catch let error as BackupServiceError {
            #expect(error == .unsupportedSchemaVersion(999))
        }

        #expect(repository.fetchDashboardHabits().count == 1)
    }

    @Test
    func backupArchiveDecodesLegacyHabitOnlyPayloads() throws {
        let json = """
        {
          "schemaVersion": 1,
          "exportedAt": "2026-04-06T17:41:21Z",
          "habits": [],
          "scheduleVersions": [],
          "completionRecords": [],
          "ordering": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archive = try decoder.decode(BackupArchive.self, from: Data(json.utf8))

        #expect(archive.schemaVersion == 1)
        #expect(archive.habits.isEmpty)
        #expect(archive.pills.isEmpty)
        #expect(archive.pillScheduleVersions.isEmpty)
        #expect(archive.pillIntakeRecords.isEmpty)
    }
}
