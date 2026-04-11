import Foundation

@MainActor
struct PillSideEffectCoordinator {
    let notificationService: PillNotificationService
    let badgeService: AppBadgeService

    func refreshDerivedState() {
        badgeService.refreshBadge()
    }

    func handleDailyMutation(forPillID pillID: UUID, on day: Date = Date()) {
        notificationService.removeSnoozedNotifications(forPillID: pillID, on: day) {
            self.notificationService.rescheduleAllNotifications()
            self.notificationService.removeDeliveredNotifications(forPillID: pillID, on: day)
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
