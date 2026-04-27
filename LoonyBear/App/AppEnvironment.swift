import CoreData
import Foundation

enum AppBootstrapState {
    case ready(AppEnvironment)
    case persistenceFailure(Error)
}

struct AppEnvironment {
    let persistenceController: PersistenceController
    let appState: HabitAppState
    let pillAppState: PillAppState
    let notificationCoordinator: AppNotificationCoordinator
    let badgeService: AppBadgeService
    let lifecycleRefreshCoordinator: AppLifecycleRefreshCoordinator
    let startupHealthCheckCoordinator: AppStartupHealthCheckCoordinator

    @MainActor
    static func live() -> AppBootstrapState {
        let persistenceController = PersistenceController.shared
        let clock = AppClock()
        let calendar = clock.calendar
        if let loadError = persistenceController.loadError {
            return .persistenceFailure(loadError)
        }

        let repository = CoreDataHabitRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let notificationService = NotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let pillNotificationService = PillNotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let pillRepository = CoreDataPillRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let loadDashboardUseCase = LoadDashboardUseCase(repository: repository)
        let widgetSyncService = WidgetSyncService(clock: clock)
        let badgeService = AppBadgeService(
            loadDashboardUseCase: loadDashboardUseCase,
            pillRepository: pillRepository,
            calendar: calendar,
            clock: clock
        )
        let appState = HabitAppState(
            loadDashboardUseCase: loadDashboardUseCase,
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository, clock: clock),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: widgetSyncService,
            badgeService: badgeService,
            clock: clock
        )
        let pillAppState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: pillRepository, clock: clock),
            repository: pillRepository,
            notificationService: pillNotificationService,
            badgeService: badgeService,
            clock: clock
        )
        let notificationCoordinator = AppNotificationCoordinator(
            habitNotificationService: notificationService,
            pillNotificationService: pillNotificationService,
            badgeService: badgeService,
            loadDashboardUseCase: loadDashboardUseCase,
            pillRepository: pillRepository,
            widgetSyncService: widgetSyncService
        )
        let lifecycleRefreshCoordinator = AppLifecycleRefreshCoordinator()
        let startupHealthCheckCoordinator = AppStartupHealthCheckCoordinator {
            try AppStartupHealthCheck.run(
                makeContext: persistenceController.makeBackgroundContext,
                calendar: calendar
            )
        }

        return .ready(AppEnvironment(
            persistenceController: persistenceController,
            appState: appState,
            pillAppState: pillAppState,
            notificationCoordinator: notificationCoordinator,
            badgeService: badgeService,
            lifecycleRefreshCoordinator: lifecycleRefreshCoordinator,
            startupHealthCheckCoordinator: startupHealthCheckCoordinator
        ))
    }

    @MainActor
    static var preview: AppEnvironment {
        let persistenceController = PersistenceController.preview
        let clock = AppClock()
        let calendar = clock.calendar
        let repository = CoreDataHabitRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let notificationService = NotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let pillNotificationService = PillNotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let pillRepository = CoreDataPillRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext,
            calendar: calendar,
            clock: clock
        )
        let loadDashboardUseCase = LoadDashboardUseCase(repository: repository)
        let widgetSyncService = WidgetSyncService(clock: clock)
        let badgeService = AppBadgeService(
            loadDashboardUseCase: loadDashboardUseCase,
            pillRepository: pillRepository,
            calendar: calendar,
            clock: clock
        )
        let appState = HabitAppState(
            loadDashboardUseCase: loadDashboardUseCase,
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository, clock: clock),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: widgetSyncService,
            badgeService: badgeService,
            clock: clock
        )
        let pillAppState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: pillRepository, clock: clock),
            repository: pillRepository,
            notificationService: pillNotificationService,
            badgeService: badgeService,
            clock: clock
        )
        let notificationCoordinator = AppNotificationCoordinator(
            habitNotificationService: notificationService,
            pillNotificationService: pillNotificationService,
            badgeService: badgeService,
            loadDashboardUseCase: loadDashboardUseCase,
            pillRepository: pillRepository,
            widgetSyncService: widgetSyncService
        )
        let lifecycleRefreshCoordinator = AppLifecycleRefreshCoordinator()
        let startupHealthCheckCoordinator = AppStartupHealthCheckCoordinator {
            try AppStartupHealthCheck.run(
                makeContext: persistenceController.makeBackgroundContext,
                calendar: calendar
            )
        }

        return AppEnvironment(
            persistenceController: persistenceController,
            appState: appState,
            pillAppState: pillAppState,
            notificationCoordinator: notificationCoordinator,
            badgeService: badgeService,
            lifecycleRefreshCoordinator: lifecycleRefreshCoordinator,
            startupHealthCheckCoordinator: startupHealthCheckCoordinator
        )
    }
}
