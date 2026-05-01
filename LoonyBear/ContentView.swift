import Combine
import CoreData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: HabitAppState
    @StateObject private var pillAppState: PillAppState
    @State private var didStartInitialStateLoad = false
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
                guard !didStartInitialStateLoad else { return }
                didStartInitialStateLoad = true
                await lifecycleRefreshCoordinator.perform {
                    await notificationCoordinator.configure()
                    await appState.handleAppDidBecomeActive()
                    await pillAppState.handleAppDidBecomeActive()
                    refreshBadgeFromDashboards(forceApply: true)
                }
                didLoadInitialState = true
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
                let previousTime = currentTime
                currentTime = now

                if shouldRefreshDashboardsForTimelineTransition(from: previousTime, to: now) {
                    appState.refreshDashboard()
                    pillAppState.refreshDashboard()
                }
                refreshBadgeFromDashboards(now: now)
            }
            .onChange(of: appState.dashboard) { _, _ in
                refreshBadgeFromDashboards(forceApply: true)
            }
            .onChange(of: pillAppState.dashboard) { _, _ in
                refreshBadgeFromDashboards(forceApply: true)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard didLoadInitialState, newPhase == .active else { return }
                currentTime = Date()
                Task {
                    await lifecycleRefreshCoordinator.perform {
                        await appState.handleAppDidBecomeActive()
                        await pillAppState.handleAppDidBecomeActive()
                        refreshBadgeFromDashboards(forceApply: true)
                    }
                }
            }
    }

    private func refreshBadgeFromDashboards(now: Date? = nil, forceApply: Bool = false) {
        badgeService.refreshBadge(
            habitDashboard: appState.dashboard,
            pillDashboard: pillAppState.dashboard,
            now: now,
            forceApply: forceApply
        )
    }

    private func shouldRefreshDashboardsForTimelineTransition(from previousTime: Date, to currentTime: Date) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        if !calendar.isDate(previousTime, inSameDayAs: currentTime) {
            return true
        }

        return habitReminderBecameDue(from: previousTime, to: currentTime, calendar: calendar) ||
            pillReminderBecameDue(from: previousTime, to: currentTime, calendar: calendar)
    }

    private func habitReminderBecameDue(from previousTime: Date, to currentTime: Date, calendar: Calendar) -> Bool {
        appState.dashboard.sections
            .flatMap(\.habits)
            .contains {
                guard
                    !$0.isCompletedToday,
                    !$0.isSkippedToday,
                    $0.isReminderScheduledToday,
                    let hour = $0.reminderHour,
                    let minute = $0.reminderMinute
                else {
                    return false
                }
                return reminderTimeBecameDue(hour: hour, minute: minute, from: previousTime, to: currentTime, calendar: calendar)
            }
    }

    private func pillReminderBecameDue(from previousTime: Date, to currentTime: Date, calendar: Calendar) -> Bool {
        pillAppState.dashboard.pills.contains {
            guard
                !$0.isTakenToday,
                !$0.isSkippedToday,
                $0.isReminderScheduledToday,
                let hour = $0.reminderHour,
                let minute = $0.reminderMinute
            else {
                return false
            }
            return reminderTimeBecameDue(hour: hour, minute: minute, from: previousTime, to: currentTime, calendar: calendar)
        }
    }

    private func reminderTimeBecameDue(
        hour: Int,
        minute: Int,
        from previousTime: Date,
        to currentTime: Date,
        calendar: Calendar
    ) -> Bool {
        guard let dueTime = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: currentTime
        ) else {
            return false
        }

        return previousTime < dueTime && dueTime <= currentTime
    }
}
