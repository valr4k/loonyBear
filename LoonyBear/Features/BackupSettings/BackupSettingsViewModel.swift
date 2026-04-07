import Combine
import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class BackupSettingsViewModel: ObservableObject {
    @Published private(set) var status = BackupStatus.empty
    @Published var isShowingFolderPicker = false
    @Published var alert: BackupAlert?
    @Published var confirmationDialog: BackupConfirmationDialog?

    private let service: BackupService
    private let notificationService: NotificationService
    private let pillNotificationService: PillNotificationService

    init(
        service: BackupService = .shared,
        notificationService: NotificationService,
        pillNotificationService: PillNotificationService
    ) {
        self.service = service
        self.notificationService = notificationService
        self.pillNotificationService = pillNotificationService
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

    func createBackup() {
        guard !status.requiresFolderReselection else {
            promptFolderReselection()
            return
        }
        confirmationDialog = .createBackup
    }

    func restoreBackup() {
        guard !status.requiresFolderReselection else {
            promptFolderReselection()
            return
        }
        confirmationDialog = .restoreBackup
    }

    func confirmCreateBackup() {
        do {
            try service.createBackup()
            status = try service.loadStatus()
            alert = BackupAlert(title: "Backup created", message: "The backup was created successfully.")
        } catch {
            alert = BackupAlert(title: "Backup failed", message: "The backup could not be created. Please try again.")
        }
    }

    func confirmRestoreBackup() -> Bool {
        do {
            try service.restoreBackup()
            notificationService.rescheduleAllNotifications()
            pillNotificationService.rescheduleAllNotifications()
            status = try service.loadStatus()
            alert = BackupAlert(title: "Restore completed", message: "Backup data was restored successfully.")
            return true
        } catch {
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
}

struct BackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum BackupConfirmationDialog: Identifiable {
    case createBackup
    case restoreBackup

    var id: String {
        switch self {
        case .createBackup:
            return "create_backup"
        case .restoreBackup:
            return "restore_backup"
        }
    }

    var title: String {
        switch self {
        case .createBackup:
            return "Create backup?"
        case .restoreBackup:
            return "Restore backup?"
        }
    }

    var message: String {
        switch self {
        case .createBackup:
            return "A new backup file will be created in the selected folder."
        case .restoreBackup:
            return "Current local data will be fully replaced by backup data. A safety snapshot will be created first."
        }
    }
}
