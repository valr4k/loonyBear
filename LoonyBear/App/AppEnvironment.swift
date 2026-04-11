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

    @MainActor
    static func live() -> AppBootstrapState {
        let persistenceController = PersistenceController.shared
        if let loadError = persistenceController.loadError {
            return .persistenceFailure(loadError)
        }

        let repository = CoreDataHabitRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let pillNotificationService = PillNotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let widgetSyncService = WidgetSyncService()
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            pillRepository: pillRepository
        )
        let appState = HabitAppState(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: widgetSyncService,
            badgeService: badgeService
        )
        let pillAppState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: pillRepository),
            repository: pillRepository,
            notificationService: pillNotificationService,
            badgeService: badgeService
        )
        let notificationCoordinator = AppNotificationCoordinator(
            habitNotificationService: notificationService,
            pillNotificationService: pillNotificationService,
            badgeService: badgeService
        )

        return .ready(AppEnvironment(
            persistenceController: persistenceController,
            appState: appState,
            pillAppState: pillAppState,
            notificationCoordinator: notificationCoordinator,
            badgeService: badgeService
        ))
    }

    @MainActor
    static var preview: AppEnvironment {
        let persistenceController = PersistenceController.preview
        let repository = CoreDataHabitRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let pillNotificationService = PillNotificationService(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistenceController.container.viewContext,
            makeWriteContext: persistenceController.makeBackgroundContext
        )
        let widgetSyncService = WidgetSyncService()
        let badgeService = AppBadgeService(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            pillRepository: pillRepository
        )
        let appState = HabitAppState(
            loadDashboardUseCase: LoadDashboardUseCase(repository: repository),
            createHabitUseCase: CreateHabitUseCase(repository: repository),
            updateHabitUseCase: UpdateHabitUseCase(repository: repository),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: repository),
            repository: repository,
            notificationService: notificationService,
            widgetSyncService: widgetSyncService,
            badgeService: badgeService
        )
        let pillAppState = PillAppState(
            reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: pillRepository),
            repository: pillRepository,
            notificationService: pillNotificationService,
            badgeService: badgeService
        )
        let notificationCoordinator = AppNotificationCoordinator(
            habitNotificationService: notificationService,
            pillNotificationService: pillNotificationService,
            badgeService: badgeService
        )

        return AppEnvironment(
            persistenceController: persistenceController,
            appState: appState,
            pillAppState: pillAppState,
            notificationCoordinator: notificationCoordinator,
            badgeService: badgeService
        )
    }
}
