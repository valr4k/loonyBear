import Foundation

@MainActor
struct PillSideEffectCoordinator {
    let notificationService: PillNotificationService
    let clock: AppClock

    init(
        notificationService: PillNotificationService,
        clock: AppClock? = nil
    ) {
        self.notificationService = notificationService
        self.clock = clock ?? .live
    }

    func refreshDerivedState() {}

    func handleDailyMutation(forPillID pillID: UUID, on day: Date? = nil) {
        let logicalDay = day ?? clock.now()
        notificationService.removeSnoozedNotifications(forPillID: pillID, on: logicalDay) {
            self.notificationService.removePendingNotification(forPillID: pillID, on: logicalDay)
            self.notificationService.removeDeliveredNotifications(forPillID: pillID, on: logicalDay)
            self.notificationService.rescheduleNotifications(forPillID: pillID)
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
