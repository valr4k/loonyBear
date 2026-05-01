import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @StateObject private var viewModel: BackupSettingsViewModel
    @State private var isShowingCreateBackupConfirmation = false
    @State private var isShowingRestoreBackupConfirmation = false
    let onRestoreComplete: () -> Void

    init(viewModel: BackupSettingsViewModel, onRestoreComplete: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onRestoreComplete = onRestoreComplete
    }

    var body: some View {
        AppScreen(backgroundStyle: .settings) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Status")
                    infoCard
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Actions")

                    if let noticeKind = viewModel.actionNoticeKind {
                        BackupActionNoticeRow(kind: noticeKind)
                    }

                    actionsCard

                    AppHelperText(text: AppCopy.backupFolderHint)
                }
            }
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $viewModel.isShowingFolderPicker) {
            FolderPickerView { url in
                viewModel.didPickFolder(url)
                viewModel.isShowingFolderPicker = false
            }
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var infoCard: some View {
        AppCard {
            BackupInfoRow(
                icon: latestBackupIcon,
                title: "Last backup",
                value: viewModel.status.latestBackupText,
                iconColor: latestBackupColor,
                titleColor: latestBackupColor,
                isTitleEmphasized: true,
                isTappable: false,
                action: nil
            )

            AppSectionDivider(inset: 52)

            BackupInfoRow(
                icon: viewModel.status.hasLatestBackup ? "externaldrive" : "externaldrive.badge.xmark",
                title: "Total size",
                value: viewModel.status.fileSizeText,
                iconColor: viewModel.status.hasLatestBackup ? nil : .secondary,
                isTappable: false,
                action: nil
            )

            AppSectionDivider(inset: 52)

            BackupInfoRow(
                icon: "folder",
                title: "Folder",
                value: viewModel.status.folderName,
                iconColor: viewModel.status.hasUsableFolder ? nil : .secondary,
                valueColor: viewModel.status.hasUsableFolder ? nil : .red,
                isTappable: true,
                action: viewModel.chooseFolder
            )
        }
    }

    private var latestBackupIcon: String {
        viewModel.status.hasLatestBackup ? "checkmark.icloud" : "exclamationmark.icloud"
    }

    private var latestBackupColor: Color {
        viewModel.status.hasLatestBackup ? .green : .red
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            BackupActionButton(
                icon: "arrow.clockwise",
                title: "Create Backup",
                tint: .primary,
                isEnabled: viewModel.canCreateBackup,
                isLoading: viewModel.isCreatingBackup,
                action: {
                    if viewModel.createBackup() {
                        isShowingCreateBackupConfirmation = true
                    }
                }
            )
            .confirmationDialog(
                "Create backup?",
                isPresented: $isShowingCreateBackupConfirmation,
                titleVisibility: .visible
            ) {
                Button("Create Backup") {
                    Task {
                        await Task.yield()
                        await viewModel.confirmCreateBackup()
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A new backup file will be created in the selected folder.")
            }

            BackupActionButton(
                icon: "arrow.counterclockwise",
                title: "Restore Backup",
                tint: .red,
                isEnabled: viewModel.canRestoreBackup,
                isLoading: viewModel.isRestoringBackup,
                action: {
                    if viewModel.restoreBackup() {
                        isShowingRestoreBackupConfirmation = true
                    }
                }
            )
            .confirmationDialog(
                "Restore backup?",
                isPresented: $isShowingRestoreBackupConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore Backup", role: .destructive) {
                    Task {
                        await Task.yield()
                        if await viewModel.confirmRestoreBackup() {
                            appState.refreshDashboard()
                            pillAppState.refreshDashboard()
                            onRestoreComplete()
                        }
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace current app data with the selected backup.")
            }
        }
    }
}

private struct BackupInfoRow: View {
    let icon: String
    let title: String
    let value: String
    var iconColor: Color?
    var titleColor: Color = .primary
    var valueColor: Color? = .secondary
    var isTitleEmphasized = false
    let isTappable: Bool
    let action: (() -> Void)?
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            AppListIcon(symbol: icon, tint: iconColor)

            Text(title)
                .fontWeight(isTitleEmphasized ? .semibold : .regular)
                .foregroundStyle(titleColor)

            Spacer()

            Text(value)
                .foregroundStyle(valueColor ?? appTint.accentColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
    }
}

private struct BackupActionButton: View {
    let icon: String
    let title: String
    let tint: Color
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(tint)
                            .controlSize(.small)
                    } else {
                        Image(systemName: icon)
                            .imageScale(.medium)
                            .foregroundStyle(isEnabled ? tint : .secondary)
                    }
                }
                .frame(width: AppLayout.listIconWidth, height: AppLayout.listIconWidth)

                Text(title)
                    .foregroundStyle(isEnabled ? tint : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled)
    }
}

private struct BackupActionNoticeRow: View {
    let kind: BackupActionNoticeKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        )
    }

    private var icon: String {
        switch kind {
        case .noBackup:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .restoreAvailable:
            return "checkmark.arrow.trianglehead.counterclockwise"
        case .unreadable:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .noBackup:
            return .blue
        case .restoreAvailable:
            return .blue
        case .unreadable:
            return .red
        }
    }

    private var message: String {
        switch kind {
        case .noBackup:
            return "No backup found. Tap Create Backup to save one."
        case .restoreAvailable:
            return "Backup found. Tap Restore Backup to apply it."
        case .unreadable:
            return "Backup file can’t be read. Choose another folder or create a new backup."
        }
    }
}

#Preview {
    NavigationStack {
        BackupSettingsView(
            viewModel: BackupSettingsViewModel(
                notificationService: AppEnvironment.preview.appState.notificationService,
                pillNotificationService: AppEnvironment.preview.pillAppState.notificationService
            )
        )
    }
    .environmentObject(AppEnvironment.preview.appState)
    .environmentObject(AppEnvironment.preview.pillAppState)
}
