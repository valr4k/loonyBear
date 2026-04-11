import Combine
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @State private var selectedTab: AppTab = .myPills
    @State private var presentedHabitSheet: HabitSheet?
    @State private var presentedPillSheet: PillSheet?
    @State private var badgeNow = Date()

    private let badgeRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
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
                .badge(overduePillCount)

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
                .badge(overdueHabitCount)

            NavigationStack {
                SettingsView()
            }
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyHabitsTab)) { _ in
            presentedPillSheet = nil
            presentedHabitSheet = nil
            selectedTab = .myHabits
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyPillsTab)) { _ in
            presentedHabitSheet = nil
            presentedPillSheet = nil
            selectedTab = .myPills
        }
        .onReceive(badgeRefreshTimer) { now in
            badgeNow = now
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            badgeNow = Date()
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
                HabitDetailsView(habit: habit) { id in
                    presentedHabitSheet = .edit(id)
                }
                    .environmentObject(appState)
            } else {
                ContentUnavailableView(
                    "Habit not found",
                    systemImage: "checklist",
                    description: Text("This habit is no longer available.")
                )
            }
        case .edit(let habitID):
            switch appState.inspectHabitDetailsState(id: habitID) {
            case .found(let details):
                EditHabitView(details: details)
                    .environmentObject(appState)
            case .notFound:
                ContentUnavailableView(
                    "Habit not found",
                    systemImage: "checklist",
                    description: Text("This habit is no longer available.")
                )
            case .integrityError(let message):
                ContentUnavailableView(
                    "Habit data problem",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
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
                PillDetailsView(pill: pill) { id in
                    presentedPillSheet = .edit(id)
                }
                    .environmentObject(pillAppState)
            } else {
                ContentUnavailableView(
                    "Pill not found",
                    systemImage: "pills",
                    description: Text("This pill is no longer available.")
                )
            }
        case .edit(let pillID):
            switch pillAppState.inspectPillDetailsState(id: pillID) {
            case .found(let details):
                EditPillView(details: details)
                    .environmentObject(pillAppState)
            case .notFound:
                ContentUnavailableView(
                    "Pill not found",
                    systemImage: "pills",
                    description: Text("This pill is no longer available.")
                )
            case .integrityError(let message):
                ContentUnavailableView(
                    "Pill data problem",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
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

    private var overdueHabitCount: Int {
        ProjectedBadgeCountCalculator.overdueHabitCount(
            now: badgeNow,
            habits: appState.dashboard.sections.flatMap(\.habits)
        )
    }

    private var overduePillCount: Int {
        ProjectedBadgeCountCalculator.overduePillCount(
            now: badgeNow,
            pills: pillAppState.dashboard.pills
        )
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
