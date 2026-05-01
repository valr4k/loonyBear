import Combine
import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @SceneStorage("selected_tab") private var selectedTabRawValue = AppTab.myPills.rawValue
    @State private var presentedHabitSheet: HabitSheet?
    @State private var presentedPillSheet: PillSheet?
    @SceneStorage("settings_route") private var settingsRouteRawValue = ""
    @State private var settingsPath: [SettingsRoute] = []
    @State private var didRestoreSettingsPath = false
    let currentTime: Date

    init(currentTime: Date = Date()) {
        self.currentTime = currentTime
    }

    var body: some View {
        TabView(selection: selectedTab) {
            NavigationStack {
                MyPillsView(
                    currentTime: currentTime,
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
                    currentTime: currentTime,
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

            NavigationStack(path: $settingsPath) {
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
            selectedTab.wrappedValue = .myHabits
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyPillsTab)) { _ in
            presentedHabitSheet = nil
            presentedPillSheet = nil
            selectedTab.wrappedValue = .myPills
        }
        .onAppear {
            restoreSettingsPathIfNeeded()
        }
        .onChange(of: settingsPath) { _, routes in
            persistSettingsPath(routes)
        }
    }

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: {
                AppTab(rawValue: selectedTabRawValue) ?? .myPills
            },
            set: { tab in
                selectedTabRawValue = tab.rawValue
            }
        )
    }

    private func restoreSettingsPathIfNeeded() {
        guard !didRestoreSettingsPath else { return }
        didRestoreSettingsPath = true

        guard let route = SettingsRoute(rawValue: settingsRouteRawValue) else {
            return
        }

        settingsPath = [route]
    }

    private func persistSettingsPath(_ routes: [SettingsRoute]) {
        let rawValue = routes.last?.rawValue ?? ""
        guard settingsRouteRawValue != rawValue else { return }
        settingsRouteRawValue = rawValue
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
            HabitEditSheetLoader(habitID: habitID)
                .environmentObject(appState)
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
            PillEditSheetLoader(pillID: pillID)
                .environmentObject(pillAppState)
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
            now: currentTime,
            habits: appState.dashboard.sections.flatMap(\.habits)
        )
    }

    private var overduePillCount: Int {
        ProjectedBadgeCountCalculator.overduePillCount(
            now: currentTime,
            pills: pillAppState.dashboard.pills
        )
    }
}

private struct HabitEditSheetLoader: View {
    @EnvironmentObject private var appState: HabitAppState
    let habitID: UUID
    @State private var state: HabitEditSheetLoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
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
        .task(id: habitID) {
            state = .loading
            switch appState.inspectHabitDetailsState(id: habitID) {
            case .found(let details):
                state = .found(details)
            case .notFound:
                state = .notFound
            case .integrityError(let message):
                state = .integrityError(message)
            }
        }
    }
}

private enum HabitEditSheetLoadState {
    case loading
    case found(HabitDetailsProjection)
    case notFound
    case integrityError(String)
}

private struct PillEditSheetLoader: View {
    @EnvironmentObject private var pillAppState: PillAppState
    let pillID: UUID
    @State private var state: PillEditSheetLoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
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
        .task(id: pillID) {
            state = .loading
            switch pillAppState.inspectPillDetailsState(id: pillID) {
            case .found(let details):
                state = .found(details)
            case .notFound:
                state = .notFound
            case .integrityError(let message):
                state = .integrityError(message)
            }
        }
    }
}

private enum PillEditSheetLoadState {
    case loading
    case found(PillDetailsProjection)
    case notFound
    case integrityError(String)
}

#Preview {
    RootTabView()
        .environmentObject(AppEnvironment.preview.appState)
        .environmentObject(AppEnvironment.preview.pillAppState)
}

private enum AppTab: String, Hashable {
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
