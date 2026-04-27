import Combine
import CoreData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: HabitAppState
    @StateObject private var pillAppState: PillAppState
    @State private var didLoadInitialState = false
    @State private var currentTime = Date()
    private let notificationCoordinator: AppNotificationCoordinator
    private let badgeService: AppBadgeService
    private let lifecycleRefreshCoordinator: AppLifecycleRefreshCoordinator
    private let startupHealthCheckCoordinator: AppStartupHealthCheckCoordinator
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(
        appState: HabitAppState,
        pillAppState: PillAppState,
        notificationCoordinator: AppNotificationCoordinator,
        badgeService: AppBadgeService,
        lifecycleRefreshCoordinator: AppLifecycleRefreshCoordinator,
        startupHealthCheckCoordinator: AppStartupHealthCheckCoordinator
    ) {
        _appState = StateObject(wrappedValue: appState)
        _pillAppState = StateObject(wrappedValue: pillAppState)
        self.notificationCoordinator = notificationCoordinator
        self.badgeService = badgeService
        self.lifecycleRefreshCoordinator = lifecycleRefreshCoordinator
        self.startupHealthCheckCoordinator = startupHealthCheckCoordinator
    }

    var body: some View {
        RootTabView(currentTime: currentTime)
            .environmentObject(appState)
            .environmentObject(pillAppState)
            .task {
                guard !didLoadInitialState else { return }
                didLoadInitialState = true
                await lifecycleRefreshCoordinator.perform {
                    await notificationCoordinator.configure()
                    await appState.handleAppDidBecomeActive()
                    await pillAppState.handleAppDidBecomeActive()
                    refreshBadgeFromDashboards()
                }
                Task {
                    await startupHealthCheckCoordinator.runIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .habitStoreDidChange)) { _ in
                appState.refreshDashboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pillStoreDidChange)) { _ in
                pillAppState.refreshDashboard()
            }
            .onReceive(minuteTimer) { now in
                guard didLoadInitialState, scenePhase == .active else { return }
                currentTime = now
                Task {
                    await lifecycleRefreshCoordinator.perform {
                        await appState.handleAppDidBecomeActive()
                        await pillAppState.handleAppDidBecomeActive()
                        refreshBadgeFromDashboards(now: now)
                    }
                }
            }
            .onChange(of: appState.dashboard) { _, _ in
                refreshBadgeFromDashboards()
            }
            .onChange(of: pillAppState.dashboard) { _, _ in
                refreshBadgeFromDashboards()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard didLoadInitialState, newPhase == .active else { return }
                currentTime = Date()
                Task {
                    await lifecycleRefreshCoordinator.perform {
                        await appState.handleAppDidBecomeActive()
                        await pillAppState.handleAppDidBecomeActive()
                        refreshBadgeFromDashboards()
                    }
                }
            }
    }

    private func refreshBadgeFromDashboards(now: Date? = nil) {
        badgeService.refreshBadge(
            habitDashboard: appState.dashboard,
            pillDashboard: pillAppState.dashboard,
            now: now
        )
    }
}
