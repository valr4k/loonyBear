import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance_mode") private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState

    private var buildVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "Build Version: \(version) (\(build))"
    }

    var body: some View {
        AppScreen(backgroundStyle: .settings) {
            AppCard {
                Picker("Appearance", selection: $appearanceModeRawValue) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)
            }

            AppCard {
                NavigationLink {
                    BackupSettingsView(
                        viewModel: BackupSettingsViewModel(
                            notificationService: appState.notificationService,
                            pillNotificationService: pillAppState.notificationService
                        )
                    )
                } label: {
                    settingsRow(
                        icon: "externaldrive",
                        title: "Backup",
                        subtitle: "Manual backup and restore"
                    )
                }
                .buttonStyle(.plain)

                AppSectionDivider()

                NavigationLink {
                    RulesLogicView()
                } label: {
                    settingsRow(
                        icon: "list.bullet.clipboard",
                        title: "Rules & Logic",
                        subtitle: "Reference for tracking rules"
                    )
                }
                .buttonStyle(.plain)
            }

            AppCard {
                settingsInfoRow(icon: "applewatch", title: "Apple Watch notifications")
                AppSectionDivider()
                settingsInfoRow(icon: "square.grid.2x2", title: "iPhone widgets")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(buildVersionText)
                Text("\u{00A9} valr4k vibecode app 2026")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .navigationTitle("Settings")
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.blue)
                .frame(width: 22)

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
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    private func settingsInfoRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.blue)
                .frame(width: 22)

            Text(title)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment.preview.appState)
        .environmentObject(AppEnvironment.preview.pillAppState)
}
