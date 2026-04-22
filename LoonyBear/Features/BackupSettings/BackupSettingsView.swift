import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @StateObject private var viewModel: BackupSettingsViewModel
    @State private var isShowingCreateBackupConfirmation = false
    @State private var isShowingRestoreBackupConfirmation = false

    init(viewModel: BackupSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
                title: "Latest backup",
                value: viewModel.status.latestBackupText,
                iconColor: viewModel.status.hasLatestBackup ? .green : .red,
                isTappable: false,
                action: nil
            )

            AppSectionDivider(inset: 52)

            BackupInfoRow(
                icon: viewModel.status.hasLatestBackup ? "externaldrive" : "externaldrive.badge.xmark",
                title: "Total size",
                value: viewModel.status.fileSizeText,
                iconColor: viewModel.status.hasLatestBackup ? .blue : .secondary,
                isTappable: false,
                action: nil
            )

            AppSectionDivider(inset: 52)

            BackupInfoRow(
                icon: "folder",
                title: "Folder",
                value: viewModel.status.folderName,
                iconColor: viewModel.status.hasUsableFolder ? .blue : .secondary,
                valueColor: viewModel.status.hasUsableFolder ? .blue : .red,
                isTappable: true,
                action: viewModel.chooseFolder
            )
        }
    }

    private var latestBackupIcon: String {
        viewModel.status.hasLatestBackup ? "checkmark.icloud" : "exclamationmark.icloud"
    }

    private var actionsCard: some View {
        AppCard {
            BackupActionRow(
                icon: "arrow.clockwise",
                title: "Create Backup",
                isEnabled: viewModel.status.hasSelectedFolder && !viewModel.isPerformingOperation,
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

            AppSectionDivider(inset: 52)

            BackupActionRow(
                icon: "arrow.counterclockwise",
                title: "Restore Backup",
                isEnabled: viewModel.status.hasSelectedFolder && !viewModel.isPerformingOperation,
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
    var iconColor: Color = .blue
    var valueColor: Color = .secondary
    let isTappable: Bool
    let action: (() -> Void)?

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
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

private struct BackupActionRow: View {
    let icon: String
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.blue)
                    } else {
                        AppActionIcon(symbol: icon)
                    }
                }
                .frame(width: AppLayout.listIconWidth, height: AppLayout.listIconWidth)

                Text(title)
                    .foregroundStyle(isEnabled ? .blue : .secondary)

                Spacer()
            }
            .padding(.horizontal, AppLayout.rowHorizontalPadding)
            .padding(.vertical, AppLayout.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
