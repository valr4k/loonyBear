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
            self.rescheduleBadgeBearingNotifications {
                self.notificationService.rescheduleNotifications(forPillID: pillID)
            }
        }
    }

    func handleDeletion(forPillID pillID: UUID) {
        removeBadgeBearingNotifications(forPillID: pillID)
    }

    func handleArchiveChange(forPillID pillID: UUID, isArchived: Bool) {
        if isArchived {
            removeBadgeBearingNotifications(forPillID: pillID)
        } else {
            rescheduleBadgeBearingNotifications {
                notificationService.rescheduleNotifications(forPillID: pillID)
            }
        }
    }

    func prepareReminderNotifications(forPillID pillID: UUID) async {
        if await notificationService.ensureAuthorizationIfNeeded() {
            rescheduleBadgeBearingNotifications {
                notificationService.rescheduleNotifications(forPillID: pillID)
            }
        }
    }

    func syncNotificationsAfterUpdate(from draft: EditPillDraft) async {
        if draft.reminderEnabled {
            await prepareReminderNotifications(forPillID: draft.id)
        } else {
            removeBadgeBearingNotifications(forPillID: draft.id)
        }
    }

    private func rescheduleBadgeBearingNotifications(fallback: () -> Void) {
        if let rescheduleAllReminderNotifications {
            rescheduleAllReminderNotifications()
        } else {
            fallback()
        }
    }

    private func removeBadgeBearingNotifications(forPillID pillID: UUID) {
        guard let rescheduleAllReminderNotifications else {
            notificationService.removeNotifications(forPillID: pillID)
            return
        }

        notificationService.removeNotifications(forPillID: pillID) {
            rescheduleAllReminderNotifications()
        }
    }
}
