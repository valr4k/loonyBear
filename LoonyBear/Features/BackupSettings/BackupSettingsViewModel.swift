import Combine
import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BackupSettingsViewModel: ObservableObject {
    @Published private(set) var status = BackupStatus.empty
    @Published var isShowingFolderPicker = false
    @Published var alert: BackupAlert?
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
                alert = BackupAlert(
                    title: "Backup folder unavailable",
                    message: "The selected backup folder is no longer accessible. Please choose the folder again."
                )
            }
        } catch {
            alert = BackupAlert(title: "Backup failed", message: error.localizedDescription)
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
            alert = BackupAlert(title: "Backup failed", message: error.localizedDescription)
        }
    }

    func createBackup() -> Bool {
        guard !isPerformingOperation else { return false }
        guard !status.requiresFolderReselection else {
            promptFolderReselection()
            return false
        }
        return true
    }

    func restoreBackup() -> Bool {
        guard !isPerformingOperation else { return false }
        guard !status.requiresFolderReselection else {
            promptFolderReselection()
            return false
        }
        return true
    }

    var isPerformingOperation: Bool {
        isCreatingBackup || isRestoringBackup
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
            alert = BackupAlert(title: "Backup created", message: "The backup was created successfully.")
        case .failure:
            await finishLoading(startedAt: start, kind: .create)
            alert = BackupAlert(title: "Backup failed", message: "The backup could not be created. Please try again.")
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
            alert = BackupAlert(title: "Restore completed", message: "Backup data was restored successfully.")
            return true
        case .failure:
            await finishLoading(startedAt: start, kind: .restore)
            alert = BackupAlert(title: "Restore failed", message: "The backup could not be restored. Existing local data was preserved.")
            return false
        }
    }

    private func promptFolderReselection() {
        alert = BackupAlert(
            title: "Backup folder unavailable",
            message: "The selected backup folder is no longer accessible. Please choose the folder again."
        )
        isShowingFolderPicker = true
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
                    continuation.resume(returning: BackupOperationResult.failure)
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
                    continuation.resume(returning: BackupOperationResult.failure)
                }
            }
        }
    }
}

private enum BackupOperationKind {
    case create
    case restore
}

private enum BackupOperationResult {
    case success(BackupStatus)
    case failure
}

struct BackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
