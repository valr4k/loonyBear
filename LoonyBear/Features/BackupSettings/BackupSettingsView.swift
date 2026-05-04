import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @StateObject private var viewModel: BackupSettingsViewModel
    @State private var isShowingCreateBackupConfirmation = false
    @State private var isShowingRestoreBackupConfirmation = false
    @State private var visibleBanner: BackupBanner?
    @State private var bannerDismissTask: Task<Void, Never>?
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

                    actionsCard

                    AppHelperText(text: AppCopy.backupFolderHint)
                }
            }
        }
        .overlay(alignment: .bottom) {
            floatingBanner
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load()
            if !presentViewModelBannerIfNeeded() {
                presentActionNoticeIfNeeded()
            }
        }
        .onChange(of: viewModel.actionNoticeKind) { _, _ in
            guard viewModel.actionNoticeKind != nil else {
                dismissVisibleBanner()
                return
            }
            presentActionNoticeIfNeeded()
        }
        .onChange(of: viewModel.banner?.id) { _, _ in
            _ = presentViewModelBannerIfNeeded()
        }
        .onDisappear {
            dismissVisibleBanner()
        }
        .alert("Create backup?", isPresented: $isShowingCreateBackupConfirmation) {
            Button("Backup") {
                Task {
                    await Task.yield()
                    await viewModel.confirmCreateBackup()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new backup file will be created in the selected folder.")
        }
        .alert("Restore backup?", isPresented: $isShowingRestoreBackupConfirmation) {
            Button("Restore", role: .destructive) {
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
        .sheet(isPresented: $viewModel.isShowingFolderPicker) {
            FolderPickerView { url in
                viewModel.didPickFolder(url)
                viewModel.isShowingFolderPicker = false
            }
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
        }
    }

    @ViewBuilder
    private var floatingBanner: some View {
        if let visibleBanner {
            BackupFloatingBanner(banner: visibleBanner) {
                dismissVisibleBanner()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .zIndex(1)
        }
    }

    private func presentActionNoticeIfNeeded() {
        guard let noticeKind = viewModel.actionNoticeKind else { return }
        presentBanner(noticeKind.banner)
    }

    private func presentViewModelBannerIfNeeded() -> Bool {
        guard let banner = viewModel.banner else { return false }
        presentBanner(banner)
        viewModel.banner = nil
        return true
    }

    private func presentBanner(_ banner: BackupBanner) {
        bannerDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleBanner = banner
        }

        bannerDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard visibleBanner?.id == banner.id else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    visibleBanner = nil
                }
            }
        }
    }

    private func dismissVisibleBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleBanner = nil
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
                        BackupProgressIcon(tint: tint)
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

private struct BackupProgressIcon: View {
    let tint: Color
    @State private var isRotating = false

    var body: some View {
        Image(systemName: "progress.indicator")
            .imageScale(.medium)
            .foregroundStyle(tint)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(.linear(duration: 0.85).repeatForever(autoreverses: false), value: isRotating)
            .onAppear {
                isRotating = true
            }
            .onDisappear {
                isRotating = false
            }
    }
}

private struct BackupFloatingBanner: View {
    let banner: BackupBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 3) {
                if let title = banner.title {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text(banner.message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Label("Dismiss", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(color.opacity(0.16))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var icon: String {
        if let icon = banner.icon {
            return icon
        }

        switch banner.style {
        case .info:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch banner.style {
        case .info:
            return .blue
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}

private extension BackupActionNoticeKind {
    var banner: BackupBanner {
        switch self {
        case .noBackup:
            return BackupBanner(
                message: "No backup found. Create one to get started.",
                style: .info,
                icon: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
            )
        case .restoreAvailable:
            return BackupBanner(
                message: "Backup available. Restore when ready.",
                style: .info,
                icon: "checkmark.arrow.trianglehead.counterclockwise"
            )
        case .unreadable:
            return BackupBanner(
                message: "Backup can’t be read. Choose another location or create a new one.",
                style: .failure
            )
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
