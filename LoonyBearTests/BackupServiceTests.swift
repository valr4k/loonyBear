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

        #expect(try repository.fetchDashboardHabits().count == 1)
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

        #expect(try repository.fetchDashboardHabits().count == 1)
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

        #expect(try repository.fetchDashboardHabits().isEmpty)
    }

    @Test
    func restoreBackupSucceedsWithValidArchiveEvenWhenCurrentStoreIsCorrupted() throws {
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

        let archive = makeValidArchive()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let archiveData = try compressionService.gzipCompress(encoder.encode(archive))
        try archiveData.write(to: folderURL.appendingPathComponent("LoonyBear.json.gz"), options: .atomic)

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
            Issue.record("Expected corrupted local store.")
        } catch is DataIntegrityError {
        }

        try service.restoreBackup()

        let restoredHabits = try repository.fetchDashboardHabits()
        #expect(restoredHabits.count == 1)
        #expect(restoredHabits.first?.name == "Archive Habit")
    }

    @Test
    func restoreBackupAbortsWhenSnapshotWriteFailsAndPreservesExistingData() throws {
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
            compressionService: compressionService,
            snapshotWriter: { _, _ in
                throw CocoaError(.fileWriteOutOfSpace)
            }
        )

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try service.saveFolderBookmark(for: folderURL)

        var existingDraft = CreateHabitDraft()
        existingDraft.name = "Existing"
        existingDraft.startDate = TestSupport.makeDate(2026, 4, 1)
        existingDraft.scheduleDays = .daily
        _ = try repository.createHabit(from: existingDraft)

        let archive = makeValidArchive()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let archiveData = try compressionService.gzipCompress(encoder.encode(archive))
        try archiveData.write(to: folderURL.appendingPathComponent("LoonyBear.json.gz"), options: .atomic)

        do {
            try service.restoreBackup()
            Issue.record("Expected snapshot write failure.")
        } catch let error as CocoaError {
            #expect(error.code == .fileWriteOutOfSpace)
        }

        let habits = try repository.fetchDashboardHabits()
        #expect(habits.count == 1)
        #expect(habits.first?.name == "Existing")
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

    @Test
    func createBackupFailsOnCorruptedHabitRow() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try service.saveFolderBookmark(for: folderURL)

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
            try service.createBackup()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "createBackup")
            #expect(error.report.issues.count == 1)
        }
    }

    @Test
    func restoreArchiveRejectsInvalidHabitTypeAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = CreateHabitDraft()
        draft.name = "Existing"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createHabit(from: draft)

        var archive = makeValidArchive()
        archive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: [
                BackupHabit(
                    id: archive.habits[0].id,
                    type: "broken_type",
                    name: archive.habits[0].name,
                    sortOrder: archive.habits[0].sortOrder,
                    startDate: archive.habits[0].startDate,
                    reminderEnabled: archive.habits[0].reminderEnabled,
                    reminderTime: archive.habits[0].reminderTime,
                    createdAt: archive.habits[0].createdAt,
                    updatedAt: archive.habits[0].updatedAt,
                    version: archive.habits[0].version
                ),
            ],
            scheduleVersions: archive.scheduleVersions,
            completionRecords: archive.completionRecords,
            ordering: archive.ordering,
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        do {
            try service.restoreArchive(archive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
        }

        #expect(try repository.fetchDashboardHabits().count == 1)
    }

    @Test
    func restoreArchiveRejectsInvalidHabitCompletionSourceAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = CreateHabitDraft()
        draft.name = "Existing"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createHabit(from: draft)

        var archive = makeValidArchive()
        archive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: archive.habits,
            scheduleVersions: archive.scheduleVersions,
            completionRecords: [
                BackupCompletion(
                    id: archive.completionRecords[0].id,
                    habitId: archive.completionRecords[0].habitId,
                    localDate: archive.completionRecords[0].localDate,
                    source: "broken_source",
                    createdAt: archive.completionRecords[0].createdAt
                ),
            ],
            ordering: archive.ordering,
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        do {
            try service.restoreArchive(archive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
        }

        #expect(try repository.fetchDashboardHabits().count == 1)
    }

    @Test
    func restoreArchiveRejectsInvalidPillIntakeSourceAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = PillDraft()
        draft.name = "Existing Pill"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createPill(from: draft)

        var archive = makeValidArchive()
        archive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: archive.habits,
            scheduleVersions: archive.scheduleVersions,
            completionRecords: archive.completionRecords,
            ordering: archive.ordering,
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: [
                BackupPillIntake(
                    id: archive.pillIntakeRecords[0].id,
                    pillId: archive.pillIntakeRecords[0].pillId,
                    localDate: archive.pillIntakeRecords[0].localDate,
                    source: "broken_source",
                    createdAt: archive.pillIntakeRecords[0].createdAt
                ),
            ]
        )

        do {
            try service.restoreArchive(archive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
        }

        #expect(try repository.fetchDashboardPills().count == 1)
    }

    @Test
    func restoreArchiveRejectsMissingReminderTimeAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = CreateHabitDraft()
        draft.name = "Existing"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createHabit(from: draft)

        var archive = makeValidArchive()
        archive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: [
                BackupHabit(
                    id: archive.habits[0].id,
                    type: archive.habits[0].type,
                    name: archive.habits[0].name,
                    sortOrder: archive.habits[0].sortOrder,
                    startDate: archive.habits[0].startDate,
                    reminderEnabled: true,
                    reminderTime: nil,
                    createdAt: archive.habits[0].createdAt,
                    updatedAt: archive.habits[0].updatedAt,
                    version: archive.habits[0].version
                ),
            ],
            scheduleVersions: archive.scheduleVersions,
            completionRecords: archive.completionRecords,
            ordering: archive.ordering,
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        do {
            try service.restoreArchive(archive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
        }

        #expect(try repository.fetchDashboardHabits().count == 1)
    }

    @Test
    func restoreArchiveRejectsOutOfRangeReminderTimeAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = PillDraft()
        draft.name = "Existing Pill"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createPill(from: draft)

        var archive = makeValidArchive()
        archive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: archive.habits,
            scheduleVersions: archive.scheduleVersions,
            completionRecords: archive.completionRecords,
            ordering: archive.ordering,
            pills: [
                BackupPill(
                    id: archive.pills[0].id,
                    name: archive.pills[0].name,
                    dosage: archive.pills[0].dosage,
                    details: archive.pills[0].details,
                    sortOrder: archive.pills[0].sortOrder,
                    startDate: archive.pills[0].startDate,
                    reminderEnabled: true,
                    reminderTime: BackupReminderTime(hour: 25, minute: 0),
                    createdAt: archive.pills[0].createdAt,
                    updatedAt: archive.pills[0].updatedAt,
                    version: archive.pills[0].version
                ),
            ],
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        do {
            try service.restoreArchive(archive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
        }

        #expect(try repository.fetchDashboardPills().count == 1)
    }

    @Test
    func restoreArchiveRejectsDuplicateHabitIDsAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = CreateHabitDraft()
        draft.name = "Existing"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createHabit(from: draft)

        let archive = makeValidArchive()
        let duplicateHabit = archive.habits[0]
        let duplicateSchedule = archive.scheduleVersions[0]
        let duplicateOrdering = archive.ordering[0]
        let duplicatedArchive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: [archive.habits[0], duplicateHabit],
            scheduleVersions: [duplicateSchedule],
            completionRecords: archive.completionRecords,
            ordering: [duplicateOrdering],
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        do {
            try service.restoreArchive(duplicatedArchive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
            #expect(error.report.issues.contains { $0.entityName == "BackupHabit" })
        }

        #expect(try repository.fetchDashboardHabits().count == 1)
    }

    @Test
    func restoreArchiveRejectsDuplicatePillIDsAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = PillDraft()
        draft.name = "Existing"
        draft.dosage = "1 tablet"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createPill(from: draft)

        let archive = makeValidArchive()
        let duplicatePill = archive.pills[0]
        let duplicateSchedule = archive.pillScheduleVersions[0]
        let duplicateIntake = archive.pillIntakeRecords[0]
        let duplicatedArchive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: archive.habits,
            scheduleVersions: archive.scheduleVersions,
            completionRecords: archive.completionRecords,
            ordering: archive.ordering,
            pills: [archive.pills[0], duplicatePill],
            pillScheduleVersions: [duplicateSchedule],
            pillIntakeRecords: [duplicateIntake]
        )

        do {
            try service.restoreArchive(duplicatedArchive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
            #expect(error.report.issues.contains { $0.entityName == "BackupPill" })
        }

        #expect(try repository.fetchDashboardPills().count == 1)
    }

    @Test
    func restoreArchiveRejectsDuplicateCompletionIDsAndPreservesExistingData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

        var draft = CreateHabitDraft()
        draft.name = "Existing"
        draft.startDate = TestSupport.makeDate(2026, 4, 1)
        draft.scheduleDays = .daily
        _ = try repository.createHabit(from: draft)

        let archive = makeValidArchive()
        let duplicateCompletion = archive.completionRecords[0]
        let duplicatedArchive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: archive.habits,
            scheduleVersions: archive.scheduleVersions,
            completionRecords: [archive.completionRecords[0], duplicateCompletion],
            ordering: archive.ordering,
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        do {
            try service.restoreArchive(duplicatedArchive)
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "restoreArchive")
            #expect(error.report.issues.contains { $0.entityName == "BackupCompletion" })
        }

        #expect(try repository.fetchDashboardHabits().count == 1)
    }
}

private extension BackupServiceTests {
    func makeBackupService(context: NSManagedObjectContext, persistence: PersistenceController) -> BackupService {
        BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)") ?? .standard,
            compressionService: CompressionService()
        )
    }

    func makeValidArchive() -> BackupArchive {
        let habitID = UUID()
        let habitScheduleID = UUID()
        let completionID = UUID()
        let pillID = UUID()
        let pillScheduleID = UUID()
        let intakeID = UUID()
        let now = TestSupport.makeDate(2026, 4, 1)

        return BackupArchive(
            schemaVersion: 1,
            exportedAt: now,
            habits: [
                BackupHabit(
                    id: habitID,
                    type: HabitType.build.rawValue,
                    name: "Archive Habit",
                    sortOrder: 0,
                    startDate: now,
                    reminderEnabled: true,
                    reminderTime: BackupReminderTime(hour: 9, minute: 0),
                    createdAt: now,
                    updatedAt: now,
                    version: 1
                ),
            ],
            scheduleVersions: [
                BackupScheduleVersion(
                    id: habitScheduleID,
                    habitId: habitID,
                    weekdayMask: WeekdaySet.daily.rawValue,
                    effectiveFrom: now,
                    createdAt: now,
                    version: 1
                ),
            ],
            completionRecords: [
                BackupCompletion(
                    id: completionID,
                    habitId: habitID,
                    localDate: now,
                    source: CompletionSource.restore.rawValue,
                    createdAt: now
                ),
            ],
            ordering: [
                BackupOrdering(
                    habitId: habitID,
                    type: HabitType.build.rawValue,
                    sortOrder: 0
                ),
            ],
            pills: [
                BackupPill(
                    id: pillID,
                    name: "Archive Pill",
                    dosage: "1 tablet",
                    details: nil,
                    sortOrder: 0,
                    startDate: now,
                    reminderEnabled: true,
                    reminderTime: BackupReminderTime(hour: 8, minute: 30),
                    createdAt: now,
                    updatedAt: now,
                    version: 1
                ),
            ],
            pillScheduleVersions: [
                BackupPillScheduleVersion(
                    id: pillScheduleID,
                    pillId: pillID,
                    weekdayMask: WeekdaySet.daily.rawValue,
                    effectiveFrom: now,
                    createdAt: now,
                    version: 1
                ),
            ],
            pillIntakeRecords: [
                BackupPillIntake(
                    id: intakeID,
                    pillId: pillID,
                    localDate: now,
                    source: PillCompletionSource.restore.rawValue,
                    createdAt: now
                ),
            ]
        )
    }
}
