import Foundation
import UserNotifications

final class AppNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let habitNotificationService: NotificationService
    private let pillNotificationService: PillNotificationService
    private let badgeService: AppBadgeService
    private let loadDashboardUseCase: LoadDashboardUseCase?
    private let pillRepository: PillRepository?
    private let widgetSyncService: WidgetSyncService?

    init(
        habitNotificationService: NotificationService,
        pillNotificationService: PillNotificationService,
        badgeService: AppBadgeService,
        loadDashboardUseCase: LoadDashboardUseCase? = nil,
        pillRepository: PillRepository? = nil,
        widgetSyncService: WidgetSyncService? = nil
    ) {
        self.habitNotificationService = habitNotificationService
        self.pillNotificationService = pillNotificationService
        self.badgeService = badgeService
        self.loadDashboardUseCase = loadDashboardUseCase
        self.pillRepository = pillRepository
        self.widgetSyncService = widgetSyncService
        super.init()
        center.delegate = self
    }

    func configure() async {
        registerCategories()
        _ = await habitNotificationService.ensureAuthorizationIfNeeded()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let type = response.notification.request.content.userInfo["type"] as? String else {
            completionHandler()
            return
        }

        let shouldRefreshScheduledNotifications = response.actionIdentifier != UNNotificationDefaultActionIdentifier
        let refreshDerivedStateAndComplete = {
            _ = Task { @MainActor in
                if shouldRefreshScheduledNotifications {
                    await self.rescheduleAllReminderNotifications()
                }
                let habitDashboard = try? self.loadDashboardUseCase?.execute()
                let pillDashboard: PillDashboardProjection?
                if let pillRepository = self.pillRepository,
                   let pills = try? pillRepository.fetchDashboardPills() {
                    pillDashboard = PillDashboardProjection(pills: pills)
                } else {
                    pillDashboard = nil
                }
                if
                    !type.hasPrefix("pill"),
                    let widgetSyncService = self.widgetSyncService,
                    let habitDashboard
                {
                    widgetSyncService.syncSnapshot(from: habitDashboard)
                }
                if let habitDashboard, let pillDashboard {
                    self.badgeService.refreshBadge(
                        habitDashboard: habitDashboard,
                        pillDashboard: pillDashboard,
                        forceApply: true
                    )
                } else {
                    self.badgeService.refreshBadge(forceApply: true)
                }
                completionHandler()
            }
        }

        if type.hasPrefix("pill") {
            pillNotificationService.handleNotificationResponse(response) { _ in
                refreshDerivedStateAndComplete()
            }
            return
        }

        habitNotificationService.handleNotificationResponse(response) { _ in
            refreshDerivedStateAndComplete()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    private func registerCategories() {
        let categories = Set(
            habitNotificationService.notificationCategories() +
                pillNotificationService.notificationCategories()
        )
        center.setNotificationCategories(categories)
    }

    @MainActor
    private func rescheduleAllReminderNotifications() async {
        await withCheckedContinuation { continuation in
            habitNotificationService.rescheduleAllNotifications {
                self.pillNotificationService.rescheduleAllNotifications {
                    continuation.resume()
                }
            }
        }
    }
}
