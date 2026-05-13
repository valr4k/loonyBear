import Combine
import SwiftUI

struct HomeQuickActionRoute: Equatable {
    let selectedTab: AppTab
    let settingsPath: [SettingsRoute]
}

enum HomeQuickActionRouter {
    static func route(for action: HomeQuickAction?) -> HomeQuickActionRoute? {
        switch action {
        case .createBackup:
            return HomeQuickActionRoute(selectedTab: .settings, settingsPath: [.backup])
        case nil:
            return nil
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var appState: HabitAppState
    @EnvironmentObject private var pillAppState: PillAppState
    @EnvironmentObject private var eventAppState: EventAppState
    @ObservedObject private var quickActionCenter = HomeQuickActionCenter.shared
    @SceneStorage("selected_tab") private var selectedTabRawValue = AppTab.myPills.rawValue
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue
    @State private var presentedHabitSheet: HabitSheet?
    @State private var presentedPillSheet: PillSheet?
    @State private var presentedEventSheet: EventSheet?
    @State private var pendingHabitSheetAfterDismiss: HabitSheet?
    @State private var pendingPillSheetAfterDismiss: PillSheet?
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
                    onOpenArchivedPill: { pill in
                        presentedPillSheet = .archivedReadOnly(pill.id)
                    },
                    onEditPill: { pill in
                        presentedPillSheet = .edit(pill.id)
                    }
                )
                .environmentObject(pillAppState)
                .navigationTitle("My Pills")
                .sheet(item: $presentedPillSheet, onDismiss: handlePillSheetDismiss) { sheet in
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
                    onOpenArchivedHabit: { habit in
                        presentedHabitSheet = .archivedReadOnly(habit.id)
                    },
                    onEditHabit: { habit in
                        presentedHabitSheet = .edit(habit.id)
                    }
                )
                .environmentObject(appState)
                .navigationTitle("My Habits")
                .sheet(item: $presentedHabitSheet, onDismiss: handleHabitSheetDismiss) { sheet in
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
                MyEventsView(
                    currentTime: currentTime,
                    onCreateEvent: {
                        presentedEventSheet = .create
                    },
                    onEditEvent: { event in
                        presentedEventSheet = .edit(event.id)
                    }
                )
                .environmentObject(eventAppState)
                .navigationTitle("Events")
                .sheet(item: $presentedEventSheet, onDismiss: restoreTabBarVisualState) { sheet in
                    NavigationStack {
                        eventSheetContent(for: sheet)
                    }
                }
            }
                .tag(AppTab.events)
                .tabItem {
                    Label("Events", systemImage: "calendar.badge")
                }

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
            presentedEventSheet = nil
            selectedTab.wrappedValue = .myHabits
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyPillsTab)) { _ in
            presentedHabitSheet = nil
            presentedPillSheet = nil
            presentedEventSheet = nil
            selectedTab.wrappedValue = .myPills
        }
        .onAppear {
            if quickActionCenter.pendingAction == nil {
                restoreSettingsPathIfNeeded()
            } else {
                didRestoreSettingsPath = true
            }
            routeQuickActionIfNeeded(quickActionCenter.pendingAction)
        }
        .onChange(of: settingsPath) { _, routes in
            persistSettingsPath(routes)
        }
        .onChange(of: quickActionCenter.pendingAction) { _, action in
            routeQuickActionIfNeeded(action)
        }
        .onChange(of: selectedTabRawValue) { _, rawValue in
            clearPendingRestoreSheets(for: AppTab(rawValue: rawValue) ?? .myPills)
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

    private func restoreTabBarVisualState() {
        LoonyBearApp.refreshTabBarAppearance(for: AppTint.stored(rawValue: appTintRawValue))
        DispatchQueue.main.async {
            LoonyBearApp.refreshTabBarAppearance(for: AppTint.stored(rawValue: appTintRawValue))
        }
    }

    private func routeQuickActionIfNeeded(_ action: HomeQuickAction?) {
        guard let route = HomeQuickActionRouter.route(for: action) else { return }

        if presentedHabitSheet != nil {
            presentedHabitSheet = nil
        }
        if presentedPillSheet != nil {
            presentedPillSheet = nil
        }
        if presentedEventSheet != nil {
            presentedEventSheet = nil
        }
        if selectedTab.wrappedValue != route.selectedTab {
            selectedTab.wrappedValue = route.selectedTab
        }
        if settingsPath != route.settingsPath {
            settingsPath = route.settingsPath
        }
        quickActionCenter.consume(.createBackup)
    }

    @ViewBuilder
    private func habitSheetContent(for sheet: HabitSheet) -> some View {
        switch sheet {
        case .create:
            CreateHabitView()
                .environmentObject(appState)
        case .edit(let habitID):
            HabitEditSheetLoader(habitID: habitID)
                .environmentObject(appState)
        case .archivedReadOnly(let habitID):
            HabitEditSheetLoader(
                habitID: habitID,
                isReadOnly: true,
                onRestoreRequested: {
                    openHabitRestoreAfterCurrentSheetDismisses(habitID: habitID)
                }
            )
                .environmentObject(appState)
        case .restore(let habitID):
            HabitEditSheetLoader(habitID: habitID, startsInRestoreMode: true)
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private func pillSheetContent(for sheet: PillSheet) -> some View {
        switch sheet {
        case .create:
            CreatePillView()
                .environmentObject(pillAppState)
        case .edit(let pillID):
            PillEditSheetLoader(pillID: pillID)
                .environmentObject(pillAppState)
        case .archivedReadOnly(let pillID):
            PillEditSheetLoader(
                pillID: pillID,
                isReadOnly: true,
                onRestoreRequested: {
                    openPillRestoreAfterCurrentSheetDismisses(pillID: pillID)
                }
            )
                .environmentObject(pillAppState)
        case .restore(let pillID):
            PillEditSheetLoader(pillID: pillID, startsInRestoreMode: true)
                .environmentObject(pillAppState)
        }
    }

    @ViewBuilder
    private func eventSheetContent(for sheet: EventSheet) -> some View {
        switch sheet {
        case .create:
            CreateEventView()
                .environmentObject(eventAppState)
        case .edit(let eventID):
            EventEditSheetLoader(eventID: eventID)
                .environmentObject(eventAppState)
        }
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

    private func handleHabitSheetDismiss() {
        restoreTabBarVisualState()
        guard let pendingHabitSheetAfterDismiss else { return }
        self.pendingHabitSheetAfterDismiss = nil
        DispatchQueue.main.async {
            guard selectedTab.wrappedValue == .myHabits else { return }
            presentedHabitSheet = pendingHabitSheetAfterDismiss
        }
    }

    private func handlePillSheetDismiss() {
        restoreTabBarVisualState()
        guard let pendingPillSheetAfterDismiss else { return }
        self.pendingPillSheetAfterDismiss = nil
        DispatchQueue.main.async {
            guard selectedTab.wrappedValue == .myPills else { return }
            presentedPillSheet = pendingPillSheetAfterDismiss
        }
    }

    private func clearPendingRestoreSheets(for tab: AppTab) {
        if tab != .myHabits {
            pendingHabitSheetAfterDismiss = nil
        }
        if tab != .myPills {
            pendingPillSheetAfterDismiss = nil
        }
    }

    private func openHabitRestoreAfterCurrentSheetDismisses(habitID: UUID) {
        pendingHabitSheetAfterDismiss = .restore(habitID)
        presentedHabitSheet = nil
    }

    private func openPillRestoreAfterCurrentSheetDismisses(pillID: UUID) {
        pendingPillSheetAfterDismiss = .restore(pillID)
        presentedPillSheet = nil
    }
}

private struct HabitEditSheetLoader: View {
    @EnvironmentObject private var appState: HabitAppState
    let habitID: UUID
    var isReadOnly = false
    var startsInRestoreMode = false
    var onRestoreRequested: (() -> Void)?
    @State private var state: HabitEditSheetLoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
            case .found(let details):
                EditHabitView(
                    details: details,
                    isReadOnly: isReadOnly,
                    startsInRestoreMode: startsInRestoreMode,
                    onRestoreRequested: onRestoreRequested
                )
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
    var isReadOnly = false
    var startsInRestoreMode = false
    var onRestoreRequested: (() -> Void)?
    @State private var state: PillEditSheetLoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
            case .found(let details):
                EditPillView(
                    details: details,
                    isReadOnly: isReadOnly,
                    startsInRestoreMode: startsInRestoreMode,
                    onRestoreRequested: onRestoreRequested
                )
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

private struct EventEditSheetLoader: View {
    @EnvironmentObject private var eventAppState: EventAppState
    let eventID: UUID
    @State private var state: EventEditSheetLoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
            case .found(let details):
                EditEventView(details: details)
                    .environmentObject(eventAppState)
            case .notFound:
                ContentUnavailableView(
                    "Event not found",
                    systemImage: "calendar.badge",
                    description: Text("This event is no longer available.")
                )
            case .integrityError(let message):
                ContentUnavailableView(
                    "Event data problem",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .task(id: eventID) {
            state = .loading
            switch eventAppState.inspectEventDetailsState(id: eventID) {
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

private enum EventEditSheetLoadState {
    case loading
    case found(EventDetailsProjection)
    case notFound
    case integrityError(String)
}

#Preview {
    RootTabView()
        .environmentObject(AppEnvironment.preview.appState)
        .environmentObject(AppEnvironment.preview.pillAppState)
        .environmentObject(AppEnvironment.preview.eventAppState)
}

enum AppTab: String, Hashable {
    case myHabits
    case myPills
    case events
    case settings
}

private enum HabitSheet: Hashable, Identifiable {
    case create
    case edit(UUID)
    case archivedReadOnly(UUID)
    case restore(UUID)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let id):
            return "edit_\(id.uuidString)"
        case .archivedReadOnly(let id):
            return "archived_read_only_\(id.uuidString)"
        case .restore(let id):
            return "restore_\(id.uuidString)"
        }
    }
}

private enum PillSheet: Hashable, Identifiable {
    case create
    case edit(UUID)
    case archivedReadOnly(UUID)
    case restore(UUID)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let id):
            return "edit_\(id.uuidString)"
        case .archivedReadOnly(let id):
            return "archived_read_only_\(id.uuidString)"
        case .restore(let id):
            return "restore_\(id.uuidString)"
        }
    }
}

private enum EventSheet: Hashable, Identifiable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let id):
            return "edit_\(id.uuidString)"
        }
    }
}
