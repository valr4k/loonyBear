import Foundation

@MainActor
struct HabitSideEffectCoordinator {
    let notificationService: NotificationService
    let widgetSyncService: WidgetSyncService
    let clock: AppClock
    let rescheduleAllReminderNotifications: (() -> Void)?

    init(
        notificationService: NotificationService,
        widgetSyncService: WidgetSyncService,
        clock: AppClock? = nil,
        rescheduleAllReminderNotifications: (() -> Void)? = nil
    ) {
        self.notificationService = notificationService
        self.widgetSyncService = widgetSyncService
        self.clock = clock ?? .live
        self.rescheduleAllReminderNotifications = rescheduleAllReminderNotifications
    }

    func refreshDerivedState(with dashboard: DashboardProjection) {
        widgetSyncService.syncSnapshot(from: dashboard)
    }

    func handleDailyMutation(forHabitID habitID: UUID, on day: Date? = nil) {
        let logicalDay = day ?? clock.now()
        notificationService.removePendingNotification(forHabitID: habitID, on: logicalDay)
        notificationService.removeDeliveredNotifications(forHabitID: habitID, on: logicalDay)
        rescheduleBadgeBearingNotifications {
            notificationService.rescheduleNotifications(forHabitID: habitID)
        }
    }

    func handleDeletion(forHabitID habitID: UUID, dashboard: DashboardProjection) {
        widgetSyncService.syncSnapshot(from: dashboard)
        removeBadgeBearingNotifications(forHabitID: habitID)
    }

    func handleArchiveChange(forHabitID habitID: UUID, dashboard: DashboardProjection, isArchived: Bool) {
        widgetSyncService.syncSnapshot(from: dashboard)
        if isArchived {
            removeBadgeBearingNotifications(forHabitID: habitID)
        } else {
            rescheduleBadgeBearingNotifications {
                notificationService.rescheduleNotifications(forHabitID: habitID)
            }
        }
    }

    func prepareReminderNotifications(forHabitID habitID: UUID) async {
        if await notificationService.ensureAuthorizationIfNeeded() {
            rescheduleBadgeBearingNotifications {
                notificationService.rescheduleNotifications(forHabitID: habitID)
            }
        }
    }

    func syncNotificationsAfterUpdate(from draft: EditHabitDraft) async {
        if draft.reminderEnabled {
            await prepareReminderNotifications(forHabitID: draft.id)
        } else {
            removeBadgeBearingNotifications(forHabitID: draft.id)
        }
    }

    private func rescheduleBadgeBearingNotifications(fallback: () -> Void) {
        if let rescheduleAllReminderNotifications {
            rescheduleAllReminderNotifications()
        } else {
            fallback()
        }
    }

    private func removeBadgeBearingNotifications(forHabitID habitID: UUID) {
        guard let rescheduleAllReminderNotifications else {
            notificationService.removeNotifications(forHabitID: habitID)
            return
        }

        notificationService.removeNotifications(forHabitID: habitID) {
            rescheduleAllReminderNotifications()
        }
    }
}
