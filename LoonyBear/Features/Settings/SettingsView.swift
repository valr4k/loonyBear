import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance_mode") private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState

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
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                AppFormSectionHeader(title: "App")

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
                            icon: "arrow.trianglehead.2.clockwise.rotate.90.icloud",
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

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment.preview.appState)
        .environmentObject(AppEnvironment.preview.pillAppState)
}
