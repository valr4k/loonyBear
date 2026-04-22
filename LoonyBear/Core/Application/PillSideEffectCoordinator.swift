import Foundation

@MainActor
struct PillSideEffectCoordinator {
    let notificationService: PillNotificationService
    let badgeService: AppBadgeService
    let clock: AppClock

    init(
        notificationService: PillNotificationService,
        badgeService: AppBadgeService,
        clock: AppClock = .live
    ) {
        self.notificationService = notificationService
        self.badgeService = badgeService
        self.clock = clock
    }

    func refreshDerivedState() {
        badgeService.refreshBadge()
    }

    func handleDailyMutation(forPillID pillID: UUID, on day: Date? = nil) {
        let logicalDay = day ?? clock.now()
        notificationService.removeSnoozedNotifications(forPillID: pillID, on: logicalDay) {
            self.notificationService.rescheduleAllNotifications()
            self.notificationService.removeDeliveredNotifications(forPillID: pillID, on: logicalDay)
        }
    }

    func handleDeletion(forPillID pillID: UUID) {
        notificationService.removeNotifications(forPillID: pillID)
    }

    func syncNotificationsAfterUpdate(from draft: EditPillDraft) async {
        if draft.reminderEnabled {
            await notificationService.prepareReminderNotifications(forPillID: draft.id)
        } else {
            notificationService.removeNotifications(forPillID: draft.id)
        }
    }
}
