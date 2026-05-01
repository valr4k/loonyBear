import SwiftUI

enum SettingsRoute: String, Hashable {
    case backup
    case rulesLogic
}

struct SettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    let onBackupRestoreComplete: () -> Void

    init(onBackupRestoreComplete: @escaping () -> Void = {}) {
        self.onBackupRestoreComplete = onBackupRestoreComplete
    }

    private var buildVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) • Build (\(build))"
    }

    var body: some View {
        AppScreen(backgroundStyle: .settings) {
            VStack(alignment: .leading, spacing: 8) {
                AppFormSectionHeader(title: "Appearance")

                AppCard {
                    Picker("Appearance", selection: $appearanceModeRawValue) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(12)

                    AppSectionDivider()

                    tintRow
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                AppFormSectionHeader(title: "App")

                AppCard {
                    NavigationLink(value: SettingsRoute.backup) {
                        settingsRow(
                            icon: "arrow.trianglehead.2.clockwise.rotate.90.icloud",
                            title: "Backup",
                            subtitle: "Manual backup and restore"
                        )
                    }
                    .buttonStyle(.plain)

                    AppSectionDivider()

                    NavigationLink(value: SettingsRoute.rulesLogic) {
                        settingsRow(
                            icon: "list.bullet.clipboard",
                            title: "Rules & Logic",
                            subtitle: "Reference for tracking rules"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                AppFormSectionHeader(title: "About")

                AppCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(buildVersionText)
                        Text("by valr4k vibecode app © 2026")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .backup:
                BackupSettingsView(
                    viewModel: BackupSettingsViewModel(
                        notificationService: appState.notificationService,
                        pillNotificationService: pillAppState.notificationService
                    ),
                    onRestoreComplete: onBackupRestoreComplete
                )
                .appTintedBackButton()
            case .rulesLogic:
                RulesLogicView()
                    .appTintedBackButton()
            }
        }
    }

    private var tintRow: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(AppTint.allCases) { tint in
                    Button {
                        appTintRawValue = tint.rawValue
                    } label: {
                        SettingsTintSwatch(
                            tint: tint,
                            isSelected: AppTint.stored(rawValue: appTintRawValue) == tint
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tint.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            AppListIcon(symbol: icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

private struct SettingsTintSwatch: View {
    let tint: AppTint
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.swatchColor)
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: borderWidth)
                }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint.swatchCheckmarkColor)
            }
        }
        .frame(width: AppLayout.tintSwatchSize, height: AppLayout.tintSwatchSize)
        .contentShape(Circle())
    }

    private var borderColor: Color {
        return isSelected ? tint.accentColor : Color(uiColor: .separator)
    }

    private var borderWidth: CGFloat {
        return isSelected ? 2 : 1
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment.preview.appState)
        .environmentObject(AppEnvironment.preview.pillAppState)
}
