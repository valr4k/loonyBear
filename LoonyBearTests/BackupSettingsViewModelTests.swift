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
        #expect(viewModel.banner?.message == "Your backup is ready in the selected folder.")
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
            notificationService: notificationService,
            pillNotificationService: pillNotificationService
        )

        return BackupSettingsViewModelFixture(viewModel: viewModel, backupService: backupService)
    }
}

private struct BackupSettingsViewModelFixture {
    let viewModel: BackupSettingsViewModel
    let backupService: BackupService
}
