import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @State private var selectedTab: AppTab = .myHabits
    @State private var presentedHabitSheet: HabitSheet?
    @State private var presentedPillSheet: PillSheet?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MyHabitsView(
                    onCreateHabit: {
                        presentedHabitSheet = .create
                    },
                    onShowHabitInfo: { habit in
                        presentedHabitSheet = .details(habit.id)
                    },
                    onEditHabit: { habit in
                        presentedHabitSheet = .edit(habit.id)
                    }
                )
                .environmentObject(appState)
                .navigationTitle("My Habits")
                .sheet(item: $presentedHabitSheet) { sheet in
                    NavigationStack {
                        habitSheetContent(for: sheet)
                    }
                }
            }
                .tag(AppTab.myHabits)
                .tabItem {
                    Label("My Habits", systemImage: "checklist")
                }

            NavigationStack {
                MyPillsView(
                    onCreatePill: {
                        presentedPillSheet = .create
                    },
                    onShowPillInfo: { pill in
                        presentedPillSheet = .details(pill.id)
                    },
                    onEditPill: { pill in
                        presentedPillSheet = .edit(pill.id)
                    }
                )
                .environmentObject(pillAppState)
                .navigationTitle("My Pills")
                .sheet(item: $presentedPillSheet) { sheet in
                    NavigationStack {
                        pillSheetContent(for: sheet)
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
            presentedHabitSheet = nil
            selectedTab = .myHabits
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyPillsTab)) { _ in
            presentedPillSheet = nil
            selectedTab = .myPills
        }
    }

    @ViewBuilder
    private func habitSheetContent(for sheet: HabitSheet) -> some View {
        switch sheet {
        case .create:
            CreateHabitView()
                .environmentObject(appState)
        case .details(let habitID):
            if let habit = habitProjection(for: habitID) {
                HabitDetailsView(habit: habit)
                    .environmentObject(appState)
            } else {
                ContentUnavailableView(
                    "Habit not found",
                    systemImage: "checklist",
                    description: Text("This habit is no longer available.")
                )
            }
        case .edit(let habitID):
            if let details = appState.habitDetails(id: habitID) {
                EditHabitView(details: details)
                    .environmentObject(appState)
            } else {
                ContentUnavailableView(
                    "Habit not found",
                    systemImage: "checklist",
                    description: Text("This habit is no longer available.")
                )
            }
        }
    }

    @ViewBuilder
    private func pillSheetContent(for sheet: PillSheet) -> some View {
        switch sheet {
        case .create:
            CreatePillView()
                .environmentObject(pillAppState)
        case .details(let pillID):
            if let pill = pillProjection(for: pillID) {
                PillDetailsView(pill: pill)
                    .environmentObject(pillAppState)
            } else {
                ContentUnavailableView(
                    "Pill not found",
                    systemImage: "pills",
                    description: Text("This pill is no longer available.")
                )
            }
        case .edit(let pillID):
            if let details = pillAppState.pillDetails(id: pillID) {
                EditPillView(details: details)
                    .environmentObject(pillAppState)
            } else {
                ContentUnavailableView(
                    "Pill not found",
                    systemImage: "pills",
                    description: Text("This pill is no longer available.")
                )
            }
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

private enum HabitSheet: Hashable, Identifiable {
    case create
    case details(UUID)
    case edit(UUID)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .details(let id):
            return "details_\(id.uuidString)"
        case .edit(let id):
            return "edit_\(id.uuidString)"
        }
    }
}

private enum PillSheet: Hashable, Identifiable {
    case create
    case details(UUID)
    case edit(UUID)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .details(let id):
            return "details_\(id.uuidString)"
        case .edit(let id):
            return "edit_\(id.uuidString)"
        }
    }
}
