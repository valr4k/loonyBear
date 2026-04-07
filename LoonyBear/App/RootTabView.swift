import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @State private var selectedTab: AppTab = .myHabits
    @State private var habitsPath = NavigationPath()
    @State private var pillsPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $habitsPath) {
                MyHabitsView(
                    onCreateHabit: {
                        habitsPath.append(HabitRoute.create)
                    },
                    onSelectHabit: { habit in
                        habitsPath.append(HabitRoute.details(habit.id))
                    }
                )
                .environmentObject(appState)
                .navigationTitle("My Habits")
                .navigationDestination(for: HabitRoute.self) { route in
                    switch route {
                    case .create:
                        CreateHabitView()
                            .environmentObject(appState)
                    case .details(let habitID):
                        if let habit = habitProjection(for: habitID) {
                            HabitDetailsView(habit: habit)
                        } else {
                            ContentUnavailableView(
                                "Habit not found",
                                systemImage: "checklist",
                                description: Text("This habit is no longer available.")
                            )
                        }
                    }
                }
            }
                .tag(AppTab.myHabits)
                .tabItem {
                    Label("My Habits", systemImage: "checklist")
                }

            NavigationStack(path: $pillsPath) {
                MyPillsView(
                    onCreatePill: {
                        pillsPath.append(PillRoute.create)
                    },
                    onSelectPill: { pill in
                        pillsPath.append(PillRoute.details(pill.id))
                    }
                )
                .environmentObject(pillAppState)
                .navigationTitle("My Pills")
                .navigationDestination(for: PillRoute.self) { route in
                    switch route {
                    case .create:
                        CreatePillView()
                            .environmentObject(pillAppState)
                    case .details(let pillID):
                        if let pill = pillProjection(for: pillID) {
                            PillDetailsView(pill: pill)
                        } else {
                            ContentUnavailableView(
                                "Pill not found",
                                systemImage: "pills",
                                description: Text("This pill is no longer available.")
                            )
                        }
                    }
                }
            }
                .tag(AppTab.myPills)
                .tabItem {
                    Label("My Pills", systemImage: "pills")
                }

            NavigationStack {
                SettingsView()
            }
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyHabitsTab)) { _ in
            habitsPath = NavigationPath()
            selectedTab = .myHabits
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyPillsTab)) { _ in
            pillsPath = NavigationPath()
            selectedTab = .myPills
        }
    }

    private func habitProjection(for id: UUID) -> HabitCardProjection? {
        appState.dashboard.sections
            .flatMap(\.habits)
            .first { $0.id == id }
    }

    private func pillProjection(for id: UUID) -> PillCardProjection? {
        pillAppState.dashboard.pills
            .first { $0.id == id }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppEnvironment.preview.appState)
        .environmentObject(AppEnvironment.preview.pillAppState)
}

private enum AppTab: Hashable {
    case myHabits
    case myPills
    case settings
}

private enum HabitRoute: Hashable {
    case create
    case details(UUID)
}

private enum PillRoute: Hashable {
    case create
    case details(UUID)
}
