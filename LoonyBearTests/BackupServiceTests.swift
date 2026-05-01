import CoreData
import Foundation
import Testing

@testable import LoonyBear

@MainActor
@Suite
struct BackupServiceTests {
    @Test
    func loadStatusReportsNoLatestBackupForSelectedFolderWithoutArchive() throws {
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

        let status = try service.loadStatus()

        #expect(status.hasSelectedFolder)
        #expect(status.hasUsableFolder)
        #expect(!status.requiresFolderReselection)
        #expect(!status.hasLatestBackup)
        #expect(status.fileState == .none)
    }

    @Test
    func loadStatusReportsLatestBackupWhenArchiveExists() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
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
        try writeArchive(makeValidArchive(), to: folderURL, compressionService: compressionService)

        let status = try service.loadStatus()

        #expect(status.hasSelectedFolder)
        #expect(status.hasUsableFolder)
        #expect(status.hasLatestBackup)
        #expect(status.fileState == .available)
    }

    @Test
    func loadStatusUsesPreviousArchiveMetadataWhenPrimaryIsCorrupted() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
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

        try Data("not-a-gzip-archive".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.json.gz"),
            options: .atomic
        )
        try writeArchive(
            makeValidArchive(),
            named: "LoonyBear.previous.json.gz",
            to: folderURL,
            compressionService: compressionService
        )

        let status = try service.loadStatus()

        #expect(status.hasSelectedFolder)
        #expect(status.hasUsableFolder)
        #expect(status.hasLatestBackup)
        #expect(status.fileSizeText != "—")
        #expect(!status.requiresFolderReselection)
        #expect(status.fileState == .available)
    }

    @Test
    func loadStatusRequiresFolderReselectionForBrokenBookmark() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        defaults.set(Data("broken-bookmark".utf8), forKey: "backup_folder_bookmark")
        defaults.set("Backups", forKey: "backup_folder_name")

        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )

        let status = try service.loadStatus()

        #expect(status.hasSelectedFolder)
        #expect(!status.hasUsableFolder)
        #expect(status.requiresFolderReselection)
        #expect(!status.hasLatestBackup)
        #expect(status.folderName == "Backups")
        #expect(status.fileState == .none)
    }

    @Test
    func loadStatusKeepsFolderUsableWhenStoredArchivesAreUnreadable() throws {
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

        try Data("broken-primary".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.json.gz"),
            options: .atomic
        )
        try Data("broken-previous".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.previous.json.gz"),
            options: .atomic
        )

        let status = try service.loadStatus()

        #expect(status.hasSelectedFolder)
        #expect(status.hasUsableFolder)
        #expect(!status.requiresFolderReselection)
        #expect(!status.hasLatestBackup)
        #expect(status.latestBackupText == "Backup unreadable")
        #expect(status.fileState == .unreadable)
    }

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
        #expect(archive.settings == nil)
    }

    @Test
    func createBackupIncludesAppearanceModeAndTint() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        defaults.set(AppearanceMode.dark.rawValue, forKey: AppearanceMode.storageKey)
        defaults.set(AppTint.green.rawValue, forKey: AppTint.storageKey)
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

        try service.createBackup()

        let archive = try readArchive(from: folderURL, compressionService: compressionService)
        #expect(archive.settings == BackupAppSettings(
            appearanceMode: AppearanceMode.dark.rawValue,
            appTint: AppTint.green.rawValue
        ))
    }

    @Test
    func createBackupMarksCurrentArchiveAsCreated() throws {
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

        try service.createBackup()

        let status = try service.loadStatus()
        #expect(status.hasLatestBackup)
        #expect(status.fileState == .created)
    }

    @Test
    func restoreArchiveAppliesAppearanceModeAndTint() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        defaults.set(AppearanceMode.light.rawValue, forKey: AppearanceMode.storageKey)
        defaults.set(AppTint.indigo.rawValue, forKey: AppTint.storageKey)
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )

        try service.restoreArchive(
            makeValidArchive(
                settings: BackupAppSettings(
                    appearanceMode: AppearanceMode.dark.rawValue,
                    appTint: AppTint.green.rawValue
                )
            )
        )

        #expect(defaults.string(forKey: AppearanceMode.storageKey) == AppearanceMode.dark.rawValue)
        #expect(defaults.string(forKey: AppTint.storageKey) == AppTint.green.rawValue)
    }

    @Test
    func restoreArchiveMigratesRemovedTintToBlue() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        defaults.set(AppTint.amber.rawValue, forKey: AppTint.storageKey)
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )

        try service.restoreArchive(
            makeValidArchive(
                settings: BackupAppSettings(
                    appearanceMode: AppearanceMode.system.rawValue,
                    appTint: "white"
                )
            )
        )

        #expect(defaults.string(forKey: AppTint.storageKey) == AppTint.blue.rawValue)
    }

    @Test
    func restoreLegacyArchiveWithoutSettingsLeavesAppearanceModeAndTintUnchanged() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        defaults.set(AppearanceMode.dark.rawValue, forKey: AppearanceMode.storageKey)
        defaults.set(AppTint.amber.rawValue, forKey: AppTint.storageKey)
        let service = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )

        try service.restoreArchive(makeValidArchive())

        #expect(defaults.string(forKey: AppearanceMode.storageKey) == AppearanceMode.dark.rawValue)
        #expect(defaults.string(forKey: AppTint.storageKey) == AppTint.amber.rawValue)
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
        #expect(try service.loadStatus().fileState == .restored)
    }

    @Test
    func restoreBackupFallsBackToPreviousArchiveWhenPrimaryIsCorrupted() throws {
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

        try Data("not-a-gzip-archive".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.json.gz"),
            options: .atomic
        )

        let archive = BackupArchive(
            schemaVersion: 1,
            exportedAt: Date(),
            habits: [
                BackupHabit(
                    id: UUID(),
                    type: HabitType.build.rawValue,
                    name: "Recovered From Previous",
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
        try writeArchive(
            archive,
            named: "LoonyBear.previous.json.gz",
            to: folderURL,
            compressionService: compressionService
        )

        try service.restoreBackup()

        let habits = try repository.fetchDashboardHabits()
        #expect(habits.count == 1)
        #expect(habits.first?.name == "Recovered From Previous")
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
    func restoreBackupThrowsCorruptedBackupWhenPrimaryAndPreviousArchivesAreUnreadable() throws {
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

        try Data("broken-primary".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.json.gz"),
            options: .atomic
        )
        try Data("broken-previous".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.previous.json.gz"),
            options: .atomic
        )

        do {
            try service.restoreBackup()
            Issue.record("Expected corrupted backup error.")
        } catch let error as BackupServiceError {
            #expect(error == .corruptedBackup)
        }
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
    func createBackupPreservesPreviousArchiveWhenWritingNewPrimaryFails() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let defaults = try #require(UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)"))
        let compressionService = CompressionService()
        let initialService = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: compressionService
        )

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try initialService.saveFolderBookmark(for: folderURL)

        var firstDraft = CreateHabitDraft()
        firstDraft.name = "First"
        firstDraft.startDate = TestSupport.makeDate(2026, 4, 1)
        firstDraft.scheduleDays = .daily
        _ = try repository.createHabit(from: firstDraft)
        try initialService.createBackup()

        var secondDraft = CreateHabitDraft()
        secondDraft.name = "Second"
        secondDraft.startDate = TestSupport.makeDate(2026, 4, 2)
        secondDraft.scheduleDays = .daily
        _ = try repository.createHabit(from: secondDraft)

        let failingService = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: compressionService,
            archiveWriter: { _, _ in
                throw CocoaError(.fileWriteOutOfSpace)
            }
        )

        do {
            try failingService.createBackup()
            Issue.record("Expected primary archive write failure.")
        } catch let error as CocoaError {
            #expect(error.code == .fileWriteOutOfSpace)
        }

        let previousArchive = try readArchive(
            named: "LoonyBear.previous.json.gz",
            from: folderURL,
            compressionService: compressionService
        )
        #expect(previousArchive.habits.count == 1)
        #expect(previousArchive.habits.first?.name == "First")
        #expect(!FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("LoonyBear.json.gz").path))
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
    func restoreArchiveAcceptsAutoFillHabitCompletionSource() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

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
                    source: CompletionSource.autoFill.rawValue,
                    createdAt: archive.completionRecords[0].createdAt
                ),
            ],
            ordering: archive.ordering,
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        try service.restoreArchive(archive)

        let restoredHabit = try #require(try repository.fetchHabitDetails(id: archive.habits[0].id))
        #expect(restoredHabit.completedDays.contains(archive.completionRecords[0].localDate))
    }

    @Test
    func restoreArchiveAcceptsSkippedHabitCompletionSource() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)

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
                    source: CompletionSource.skipped.rawValue,
                    createdAt: archive.completionRecords[0].createdAt
                ),
            ],
            ordering: archive.ordering,
            pills: archive.pills,
            pillScheduleVersions: archive.pillScheduleVersions,
            pillIntakeRecords: archive.pillIntakeRecords
        )

        try service.restoreArchive(archive)

        let restoredHabit = try #require(try repository.fetchHabitDetails(id: archive.habits[0].id))
        #expect(restoredHabit.skippedDays.contains(archive.completionRecords[0].localDate))
        #expect(!restoredHabit.completedDays.contains(archive.completionRecords[0].localDate))
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
                    historyMode: archive.pills[0].historyMode,
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
    func restoreArchivePreservesHabitHistoryMode() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = makeBackupService(context: context, persistence: persistence)
        let archive = makeValidArchive()
        let migratedArchive = BackupArchive(
            schemaVersion: archive.schemaVersion,
            exportedAt: archive.exportedAt,
            habits: [
                BackupHabit(
                    id: archive.habits[0].id,
                    type: archive.habits[0].type,
                    name: archive.habits[0].name,
                    sortOrder: archive.habits[0].sortOrder,
                    startDate: archive.habits[0].startDate,
                    historyMode: HabitHistoryMode.everyDay.rawValue,
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

        try service.restoreArchive(migratedArchive)

        let details = try #require(try repository.fetchHabitDetails(id: archive.habits[0].id))
        #expect(details.historyMode == .everyDay)
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
    func writeArchive(_ archive: BackupArchive, to folderURL: URL, compressionService: CompressionService) throws {
        try writeArchive(archive, named: "LoonyBear.json.gz", to: folderURL, compressionService: compressionService)
    }

    func writeArchive(_ archive: BackupArchive, named fileName: String, to folderURL: URL, compressionService: CompressionService) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let archiveData = try compressionService.gzipCompress(encoder.encode(archive))
        try archiveData.write(to: folderURL.appendingPathComponent(fileName), options: .atomic)
    }

    func readArchive(named fileName: String, from folderURL: URL, compressionService: CompressionService) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archiveData = try Data(contentsOf: folderURL.appendingPathComponent(fileName))
        return try decoder.decode(
            BackupArchive.self,
            from: try compressionService.gzipDecompress(archiveData)
        )
    }

    func readArchive(from folderURL: URL, compressionService: CompressionService) throws -> BackupArchive {
        try readArchive(named: "LoonyBear.json.gz", from: folderURL, compressionService: compressionService)
    }

    func makeBackupService(context: NSManagedObjectContext, persistence: PersistenceController) -> BackupService {
        BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)") ?? .standard,
            compressionService: CompressionService()
        )
    }

    func makeValidArchive(settings: BackupAppSettings? = nil) -> BackupArchive {
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
            settings: settings,
            pills: [
                BackupPill(
                    id: pillID,
                    name: "Archive Pill",
                    dosage: "1 tablet",
                    details: nil,
                    sortOrder: 0,
                    startDate: now,
                    historyMode: PillHistoryMode.scheduleBased.rawValue,
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
