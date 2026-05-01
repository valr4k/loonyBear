import Combine
import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BackupSettingsViewModel: ObservableObject {
    @Published private(set) var status = BackupStatus.empty
    @Published var isShowingFolderPicker = false
    @Published var banner: BackupBanner?
    @Published private(set) var isCreatingBackup = false
    @Published private(set) var isRestoringBackup = false

    private let service: BackupService
    private let notificationService: NotificationService
    private let pillNotificationService: PillNotificationService
    private let minimumLoadingDuration: Duration = .seconds(1)

    init(
        service: BackupService,
        notificationService: NotificationService,
        pillNotificationService: PillNotificationService
    ) {
        self.service = service
        self.notificationService = notificationService
        self.pillNotificationService = pillNotificationService
    }

    convenience init(
        notificationService: NotificationService,
        pillNotificationService: PillNotificationService
    ) {
        self.init(
            service: BackupService.shared,
            notificationService: notificationService,
            pillNotificationService: pillNotificationService
        )
    }

    func load() {
        do {
            status = try service.loadStatus()
            if status.requiresFolderReselection {
                showBanner(
                    title: "Backup Folder Unavailable",
                    message: "The selected backup folder is no longer accessible. Choose the folder again to keep using backups.",
                    style: .failure
                )
            }
        } catch {
            showBanner(title: "Backup Failed", message: Self.createFailureMessage(for: error), style: .failure)
        }
    }

    func chooseFolder() {
        isShowingFolderPicker = true
    }

    func didPickFolder(_ url: URL) {
        do {
            try service.saveFolderBookmark(for: url)
            status = try service.loadStatus()
        } catch {
            showBanner(title: "Backup Failed", message: Self.createFailureMessage(for: error), style: .failure)
        }
    }

    func createBackup() -> Bool {
        guard !isPerformingOperation else { return false }
        guard status.fileState != .available else { return false }
        guard !status.requiresFolderReselection else {
            promptFolderReselection()
            return false
        }
        guard status.hasUsableFolder else {
            chooseFolder()
            return false
        }
        return true
    }

    func restoreBackup() -> Bool {
        guard !isPerformingOperation else { return false }
        guard status.hasLatestBackup else { return false }
        guard !status.requiresFolderReselection else {
            promptFolderReselection()
            return false
        }
        return true
    }

    var isPerformingOperation: Bool {
        isCreatingBackup || isRestoringBackup
    }

    var actionNoticeKind: BackupActionNoticeKind? {
        guard status.hasUsableFolder else { return nil }

        switch status.fileState {
        case .none:
            return .noBackup
        case .available:
            return .restoreAvailable
        case .created, .restored:
            return nil
        case .unreadable:
            return .unreadable
        }
    }

    var canCreateBackup: Bool {
        status.hasUsableFolder && !isPerformingOperation && status.fileState != .available
    }

    var canRestoreBackup: Bool {
        status.hasUsableFolder && status.hasLatestBackup && !isPerformingOperation
    }

    func confirmCreateBackup() async {
        guard !isPerformingOperation else { return }

        isCreatingBackup = true
        let start = ContinuousClock.now
        await Task.yield()

        let result = await runCreateBackupInBackground()

        switch result {
        case .success(let updatedStatus):
            status = updatedStatus
            await finishLoading(startedAt: start, kind: .create)
            showBanner(title: "Backup Created", message: "Your backup is ready in the selected folder.", style: .success)
        case .failure(let message):
            await finishLoading(startedAt: start, kind: .create)
            showBanner(title: "Backup Failed", message: message, style: .failure)
        }
    }

    func confirmRestoreBackup() async -> Bool {
        guard !isPerformingOperation else { return false }

        isRestoringBackup = true
        let start = ContinuousClock.now
        await Task.yield()

        let result = await runRestoreBackupInBackground()

        switch result {
        case .success(let updatedStatus):
            notificationService.rescheduleAllNotifications()
            pillNotificationService.rescheduleAllNotifications()
            status = updatedStatus
            await finishLoading(startedAt: start, kind: .restore)
            showBanner(title: "Restore Complete", message: "Your backup was restored successfully.", style: .success)
            return true
        case .failure(let message):
            await finishLoading(startedAt: start, kind: .restore)
            showBanner(title: "Restore Failed", message: message, style: .failure)
            return false
        }
    }

    private func promptFolderReselection() {
        showBanner(
            title: "Backup Folder Unavailable",
            message: "The selected backup folder is no longer accessible. Choose the folder again to keep using backups.",
            style: .failure
        )
        isShowingFolderPicker = true
    }

    private func showBanner(title: String, message: String, style: BackupBannerStyle) {
        banner = BackupBanner(title: title, message: message, style: style)
    }

    private func finishLoading(startedAt start: ContinuousClock.Instant, kind: BackupOperationKind) async {
        let elapsed = start.duration(to: ContinuousClock.now)
        if elapsed < minimumLoadingDuration {
            try? await Task.sleep(for: minimumLoadingDuration - elapsed)
        }

        switch kind {
        case .create:
            isCreatingBackup = false
        case .restore:
            isRestoringBackup = false
        }
    }

    private func runCreateBackupInBackground() async -> BackupOperationResult {
        let service = self.service
        return await withCheckedContinuation { (continuation: CheckedContinuation<BackupOperationResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try service.createBackup()
                    let status = try service.loadStatus()
                    continuation.resume(returning: BackupOperationResult.success(status))
                } catch {
                    continuation.resume(returning: BackupOperationResult.failure(Self.createFailureMessage(for: error)))
                }
            }
        }
    }

    private func runRestoreBackupInBackground() async -> BackupOperationResult {
        let service = self.service
        return await withCheckedContinuation { (continuation: CheckedContinuation<BackupOperationResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try service.restoreBackup()
                    let status = try service.loadStatus()
                    continuation.resume(returning: BackupOperationResult.success(status))
                } catch {
                    continuation.resume(returning: BackupOperationResult.failure(Self.restoreFailureMessage(for: error)))
                }
            }
        }
    }

    private nonisolated static func createFailureMessage(for error: Error) -> String {
        "Couldn’t create a backup. \(error.localizedDescription)"
    }

    private nonisolated static func restoreFailureMessage(for error: Error) -> String {
        let detail = error.localizedDescription
        return "\(detail) Your current data was left unchanged."
    }
}

private enum BackupOperationKind {
    case create
    case restore
}

private enum BackupOperationResult {
    case success(BackupStatus)
    case failure(String)
}

enum BackupActionNoticeKind: Equatable {
    case noBackup
    case restoreAvailable
    case unreadable
}

enum BackupBannerStyle: Equatable {
    case info
    case success
    case failure
}

struct BackupBanner: Identifiable {
    let id = UUID()
    let title: String?
    let message: String
    let icon: String?

    init(title: String? = nil, message: String, style: BackupBannerStyle, icon: String? = nil) {
        self.title = title
        self.message = message
        self.icon = icon
        self.style = style
    }

    let style: BackupBannerStyle
}
