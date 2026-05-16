import CoreData
import Foundation
import Testing

@testable import LoonyBear

@MainActor
struct BackupSettingsViewModelTests {
    @Test
    func unreadableArchiveAllowsCreateButBlocksRestore() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupSettingsViewModelTests.\(UUID().uuidString)"))

        let backupService = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )
        let autoBackupService = AutoBackupService(
            backupService: backupService,
            defaults: defaults,
            debounceDuration: .seconds(60)
        )
        let notificationService = NotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillNotificationService = PillNotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let viewModel = BackupSettingsViewModel(
            service: backupService,
            autoBackupService: autoBackupService,
            notificationService: notificationService,
            pillNotificationService: pillNotificationService
        )

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try backupService.saveFolderBookmark(for: folderURL)
        try Data("broken-primary".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.json.gz"),
            options: .atomic
        )
        try Data("broken-previous".utf8).write(
            to: folderURL.appendingPathComponent("LoonyBear.previous.json.gz"),
            options: .atomic
        )

        viewModel.load()

        #expect(viewModel.status.hasUsableFolder)
        #expect(!viewModel.status.requiresFolderReselection)
        #expect(viewModel.status.fileState == .unreadable)
        #expect(viewModel.actionNoticeKind == .unreadable)
        #expect(viewModel.canCreateBackup)
        #expect(!viewModel.canRestoreBackup)
        #expect(viewModel.createBackup())
        #expect(!viewModel.restoreBackup())

        viewModel.setAutoBackupEnabled(true)

        #expect(!autoBackupService.isEnabled)
        #expect(viewModel.banner?.message == "Create or restore a backup before turning on Auto Backup.")
    }

    @Test
    func createBackupSuccessShowsSuccessBanner() async throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folderURL)
        }

        try fixture.backupService.saveFolderBookmark(for: folderURL)
        viewModel.load()

        #expect(viewModel.createBackup())

        await viewModel.confirmCreateBackup()

        #expect(viewModel.status.fileState == .created)
        #expect(viewModel.banner?.title == "Backup Created")
        #expect(viewModel.banner?.message == "Backup saved to the selected folder.")
        #expect(viewModel.banner?.style == .success)
    }

    @Test
    func createBackupWithoutFolderOpensFolderPicker() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel

        viewModel.load()

        #expect(!viewModel.createBackup())
        #expect(viewModel.isShowingFolderPicker)
    }

    @Test
    func enablingAutoBackupWithoutFolderOpensPickerAndCancelKeepsItOff() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let autoBackupService = fixture.autoBackupService

        viewModel.load()

        viewModel.setAutoBackupEnabled(true)

        #expect(viewModel.isShowingFolderPicker)
        #expect(!autoBackupService.isEnabled)

        viewModel.folderPickerDidDismiss()

        #expect(!autoBackupService.isEnabled)
    }

    @Test
    func enablingAutoBackupWithoutFolderTurnsOnAfterFolderSelection() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let autoBackupService = fixture.autoBackupService
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folderURL)
        }

        viewModel.load()
        viewModel.setAutoBackupEnabled(true)
        viewModel.didPickFolder(folderURL)

        #expect(autoBackupService.isEnabled)
        #expect(viewModel.status.hasUsableFolder)
    }

    @Test
    func enablingAutoBackupWithAvailableBackupKeepsItOff() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let autoBackupService = fixture.autoBackupService
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folderURL)
        }

        try fixture.backupService.saveFolderBookmark(for: folderURL)
        try fixture.backupService.createBackup()
        fixture.defaults.removeObject(forKey: "backup_last_created_fingerprint")
        viewModel.load()

        #expect(viewModel.status.fileState == .available)
        #expect(!viewModel.status.allowsAutomaticBackup)
        #expect(!viewModel.canCreateBackup)

        viewModel.setAutoBackupEnabled(true)

        #expect(!autoBackupService.isEnabled)
        #expect(viewModel.banner?.message == "Create or restore a backup before turning on Auto Backup.")
    }

    @Test
    func enablingAutoBackupWithUnavailableStoredFolderRequiresReselectionAndCancelKeepsItOff() throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        let autoBackupService = fixture.autoBackupService
        fixture.defaults.set(Data("broken-bookmark".utf8), forKey: "backup_folder_bookmark")
        fixture.defaults.set("Missing Backups", forKey: "backup_folder_name")

        viewModel.load()

        #expect(viewModel.status.hasSelectedFolder)
        #expect(!viewModel.status.hasUsableFolder)
        #expect(!autoBackupService.isEnabled)

        viewModel.setAutoBackupEnabled(true)

        #expect(viewModel.isShowingFolderPicker)
        #expect(!autoBackupService.isEnabled)

        viewModel.folderPickerDidDismiss()

        #expect(!autoBackupService.isEnabled)
    }

    @Test
    func autoBackupStartupDisablesStoredEnabledStateWhenFolderIsUnavailable() throws {
        let persistence = PersistenceController(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: "BackupSettingsViewModelTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AutoBackupService.enabledKey)
        defaults.set(Data("broken-bookmark".utf8), forKey: "backup_folder_bookmark")
        defaults.set("Missing Backups", forKey: "backup_folder_name")
        let backupService = BackupService(
            context: persistence.container.viewContext,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )
        let autoBackupService = AutoBackupService(
            backupService: backupService,
            defaults: defaults,
            debounceDuration: .seconds(60)
        )

        #expect(autoBackupService.isEnabled)

        autoBackupService.handleStartup()

        #expect(!autoBackupService.isEnabled)
        #expect(!defaults.bool(forKey: AutoBackupService.enabledKey))
    }

    @Test
    func autoBackupStartupDisablesStoredEnabledStateWhenBackupIsAvailableButNotTrusted() throws {
        let persistence = PersistenceController(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: "BackupSettingsViewModelTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: AutoBackupService.enabledKey)
        let backupService = BackupService(
            context: persistence.container.viewContext,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folderURL)
        }

        try backupService.saveFolderBookmark(for: folderURL)
        try backupService.createBackup()
        defaults.removeObject(forKey: "backup_last_created_fingerprint")

        let autoBackupService = AutoBackupService(
            backupService: backupService,
            defaults: defaults,
            debounceDuration: .seconds(60)
        )

        #expect(autoBackupService.isEnabled)

        autoBackupService.handleStartup()

        #expect(!autoBackupService.isEnabled)
        #expect(!defaults.bool(forKey: AutoBackupService.enabledKey))
    }

    @Test
    func completingExternalRestoreClearsDirtyChangesCreatedDuringRestoreWithoutSchedulingBackup() throws {
        let fixture = try makeFixture()
        let autoBackupService = fixture.autoBackupService

        autoBackupService.markDirty(reason: "before-restore")
        let token = autoBackupService.beginExternalBackup()
        autoBackupService.markDirty(reason: "restore-store-change")

        #expect(autoBackupService.isDirty)

        autoBackupService.completeExternalBackup(
            token,
            succeeded: true,
            clearsDirtyRegardless: true,
            schedulesPendingDirty: false
        )

        #expect(!autoBackupService.isDirty)
    }
}

private extension BackupSettingsViewModelTests {
    func makeFixture() throws -> BackupSettingsViewModelFixture {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let defaults = try #require(UserDefaults(suiteName: "BackupSettingsViewModelTests.\(UUID().uuidString)"))
        let backupService = BackupService(
            context: context,
            makeWorkContext: persistence.makeBackgroundContext,
            defaults: defaults,
            compressionService: CompressionService()
        )
        let autoBackupService = AutoBackupService(
            backupService: backupService,
            defaults: defaults,
            debounceDuration: .seconds(60)
        )
        let notificationService = NotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillNotificationService = PillNotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let viewModel = BackupSettingsViewModel(
            service: backupService,
            autoBackupService: autoBackupService,
            notificationService: notificationService,
            pillNotificationService: pillNotificationService
        )

        return BackupSettingsViewModelFixture(
            viewModel: viewModel,
            backupService: backupService,
            autoBackupService: autoBackupService,
            defaults: defaults
        )
    }
}

private struct BackupSettingsViewModelFixture {
    let viewModel: BackupSettingsViewModel
    let backupService: BackupService
    let autoBackupService: AutoBackupService
    let defaults: UserDefaults
}
