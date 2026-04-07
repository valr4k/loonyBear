import Combine
import CoreData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: HabitAppState
    @StateObject private var pillAppState: PillAppState
    @State private var didLoadInitialState = false
    private let notificationCoordinator: AppNotificationCoordinator
    private let badgeService: AppBadgeService
    private let badgeRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(
        appState: HabitAppState,
        pillAppState: PillAppState,
        notificationCoordinator: AppNotificationCoordinator,
        badgeService: AppBadgeService
    ) {
        _appState = StateObject(wrappedValue: appState)
        _pillAppState = StateObject(wrappedValue: pillAppState)
        self.notificationCoordinator = notificationCoordinator
        self.badgeService = badgeService
    }

    var body: some View {
        RootTabView()
            .environmentObject(appState)
            .environmentObject(pillAppState)
            .task {
                guard !didLoadInitialState else { return }
                didLoadInitialState = true
                await notificationCoordinator.configure()
                await appState.load()
                pillAppState.load()
                badgeService.refreshBadge()
            }
            .onReceive(NotificationCenter.default.publisher(for: .habitStoreDidChange)) { _ in
                appState.refreshDashboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pillStoreDidChange)) { _ in
                pillAppState.refreshDashboard()
            }
            .onReceive(badgeRefreshTimer) { _ in
                guard didLoadInitialState, scenePhase == .active else { return }
                badgeService.refreshBadge()
            }
    }
}
