import Foundation

@MainActor
struct PillSideEffectCoordinator {
    let notificationService: PillNotificationService
    let clock: AppClock
    let rescheduleAllReminderNotifications: (() -> Void)?

    init(
        notificationService: PillNotificationService,
        clock: AppClock? = nil,
        rescheduleAllReminderNotifications: (() -> Void)? = nil
    ) {
        self.notificationService = notificationService
        self.clock = clock ?? .live
        self.rescheduleAllReminderNotifications = rescheduleAllReminderNotifications
    }

    func refreshDerivedState() {}

    func handleDailyMutation(forPillID pillID: UUID, on day: Date? = nil) {
        let logicalDay = day ?? clock.now()
        notificationService.removeSnoozedNotifications(forPillID: pillID, on: logicalDay) {
            self.notificationService.removePendingNotification(forPillID: pillID, on: logicalDay)
            self.notificationService.removeDeliveredNotifications(forPillID: pillID, on: logicalDay)
            if let rescheduleAllReminderNotifications = self.rescheduleAllReminderNotifications {
                rescheduleAllReminderNotifications()
            } else {
                self.notificationService.rescheduleNotifications(forPillID: pillID)
            }
        }
    }

    func handleDeletion(forPillID pillID: UUID) {
        notificationService.removeNotifications(forPillID: pillID)
        rescheduleAllReminderNotifications?()
    }

    func prepareReminderNotifications(forPillID pillID: UUID) async {
        await notificationService.prepareReminderNotifications(forPillID: pillID)
        rescheduleAllReminderNotifications?()
    }

    func syncNotificationsAfterUpdate(from draft: EditPillDraft) async {
        if draft.reminderEnabled {
            await notificationService.prepareReminderNotifications(forPillID: draft.id)
        } else {
            notificationService.removeNotifications(forPillID: draft.id)
        }
        rescheduleAllReminderNotifications?()
    }
}
