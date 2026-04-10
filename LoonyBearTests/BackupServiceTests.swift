import CoreData
import Foundation
import Testing

@testable import LoonyBear

@MainActor
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

    @Test
    func restoreBackupFallsBackToPreviousArchiveWhenPrimaryIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        let compressionService = CompressionService()
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: compressionService
        )

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try service.saveFolderBookmark(for: folderURL)

        let archive = BackupArchive(
            schemaVersion: 1,
            exportedAt: Date(),
            habits: [
                BackupHabit(
                    id: UUID(),
                    type: HabitType.build.rawValue,
                    name: "Recovered",
                    sortOrder: 0,
                    startDate: Date(),
                    reminderEnabled: false,
                    reminderTime: nil,
                    createdAt: Date(),
                    updatedAt: Date(),
                    version: 1
                ),
            ],
            scheduleVersions: [],
            completionRecords: [],
            ordering: [],
            pills: [],
            pillScheduleVersions: [],
            pillIntakeRecords: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try compressionService.gzipCompress(encoder.encode(archive))
        let previousURL = folderURL.appendingPathComponent("LoonyBear.previous.json.gz")
        try data.write(to: previousURL, options: .atomic)

        try service.restoreBackup()

        #expect(repository.fetchDashboardHabits().count == 1)
    }

    @Test
    func restoreBackupDoesNotFallbackWhenPrimaryUsesUnsupportedSchema() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        let compressionService = CompressionService()
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: compressionService
        )

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try service.saveFolderBookmark(for: folderURL)

        let primaryArchive = BackupArchive(
            schemaVersion: 999,
            exportedAt: Date(),
            habits: [],
            scheduleVersions: [],
            completionRecords: [],
            ordering: [],
            pills: [],
            pillScheduleVersions: [],
            pillIntakeRecords: []
        )
        let previousArchive = BackupArchive(
            schemaVersion: 1,
            exportedAt: Date(),
            habits: [
                BackupHabit(
                    id: UUID(),
                    type: HabitType.build.rawValue,
                    name: "Previous",
                    sortOrder: 0,
                    startDate: Date(),
                    reminderEnabled: false,
                    reminderTime: nil,
                    createdAt: Date(),
                    updatedAt: Date(),
                    version: 1
                ),
            ],
            scheduleVersions: [],
            completionRecords: [],
            ordering: [],
            pills: [],
            pillScheduleVersions: [],
            pillIntakeRecords: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let primaryData = try compressionService.gzipCompress(encoder.encode(primaryArchive))
        try primaryData.write(to: folderURL.appendingPathComponent("LoonyBear.json.gz"), options: .atomic)

        let previousData = try compressionService.gzipCompress(encoder.encode(previousArchive))
        try previousData.write(to: folderURL.appendingPathComponent("LoonyBear.previous.json.gz"), options: .atomic)

        do {
            try service.restoreBackup()
            Issue.record("Expected unsupported schema version error.")
        } catch let error as BackupServiceError {
            #expect(error == .unsupportedSchemaVersion(999))
        }

        #expect(repository.fetchDashboardHabits().isEmpty)
    }

    @Test
    func createBackupRotatesExistingPrimaryArchiveToPrevious() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        let compressionService = CompressionService()
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: compressionService
        )

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try service.saveFolderBookmark(for: folderURL)

        var firstDraft = CreateHabitDraft()
        firstDraft.name = "First"
        firstDraft.startDate = TestSupport.makeDate(2026, 4, 1)
        firstDraft.scheduleDays = .daily
        _ = try repository.createHabit(from: firstDraft)

        try service.createBackup()

        var secondDraft = CreateHabitDraft()
        secondDraft.name = "Second"
        secondDraft.startDate = TestSupport.makeDate(2026, 4, 2)
        secondDraft.scheduleDays = .daily
        _ = try repository.createHabit(from: secondDraft)

        try service.createBackup()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let previousURL = folderURL.appendingPathComponent("LoonyBear.previous.json.gz")
        let previousData = try Data(contentsOf: previousURL)
        let previousArchive = try decoder.decode(
            BackupArchive.self,
            from: try compressionService.gzipDecompress(previousData)
        )

        #expect(previousArchive.habits.count == 1)
        #expect(previousArchive.habits.first?.name == "First")
    }
}
