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
        if let rescheduleAllReminderNotifications {
            rescheduleAllReminderNotifications()
        } else {
            notificationService.rescheduleNotifications(forHabitID: habitID)
        }
    }

    func handleDeletion(forHabitID habitID: UUID, dashboard: DashboardProjection) {
        widgetSyncService.syncSnapshot(from: dashboard)
        notificationService.removeNotifications(forHabitID: habitID)
        rescheduleAllReminderNotifications?()
    }

    func handleArchiveChange(forHabitID habitID: UUID, dashboard: DashboardProjection, isArchived: Bool) {
        widgetSyncService.syncSnapshot(from: dashboard)
        if isArchived {
            notificationService.removeNotifications(forHabitID: habitID)
        } else if let rescheduleAllReminderNotifications {
            rescheduleAllReminderNotifications()
        } else {
            notificationService.rescheduleNotifications(forHabitID: habitID)
        }
    }

    func prepareReminderNotifications(forHabitID habitID: UUID) async {
        await notificationService.prepareReminderNotifications(forHabitID: habitID)
        rescheduleAllReminderNotifications?()
    }

    func syncNotificationsAfterUpdate(from draft: EditHabitDraft) async {
        if draft.reminderEnabled {
            await notificationService.prepareReminderNotifications(forHabitID: draft.id)
        } else {
            notificationService.removeNotifications(forHabitID: draft.id)
        }
        rescheduleAllReminderNotifications?()
    }
}
