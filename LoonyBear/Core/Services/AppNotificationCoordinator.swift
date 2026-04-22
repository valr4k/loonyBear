import Foundation
import UserNotifications

final class AppNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let habitNotificationService: NotificationService
    private let pillNotificationService: PillNotificationService
    private let badgeService: AppBadgeService

    init(
        habitNotificationService: NotificationService,
        pillNotificationService: PillNotificationService,
        badgeService: AppBadgeService
    ) {
        self.habitNotificationService = habitNotificationService
        self.pillNotificationService = pillNotificationService
        self.badgeService = badgeService
        super.init()
        center.delegate = self
    }

    func configure() async {
        registerCategories()
        _ = await habitNotificationService.ensureAuthorizationIfNeeded()
        await MainActor.run {
            badgeService.refreshBadge()
        }
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

        let finishResponse = {
            _ = Task { @MainActor in
                self.badgeService.refreshBadge()
                completionHandler()
            }
        }

        if type.hasPrefix("pill") {
            pillNotificationService.handleNotificationResponse(response) { _ in
                finishResponse()
            }
            return
        }

        habitNotificationService.handleNotificationResponse(response) { _ in
            finishResponse()
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
}
