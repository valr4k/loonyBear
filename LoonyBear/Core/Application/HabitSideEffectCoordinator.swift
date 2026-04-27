import Foundation

@MainActor
struct HabitSideEffectCoordinator {
    let notificationService: NotificationService
    let widgetSyncService: WidgetSyncService
    let clock: AppClock

    init(
        notificationService: NotificationService,
        widgetSyncService: WidgetSyncService,
        clock: AppClock? = nil
    ) {
        self.notificationService = notificationService
        self.widgetSyncService = widgetSyncService
        self.clock = clock ?? .live
    }

    func refreshDerivedState(with dashboard: DashboardProjection) {
        widgetSyncService.syncSnapshot(from: dashboard)
    }

    func handleDailyMutation(forHabitID habitID: UUID, on day: Date? = nil) {
        let logicalDay = day ?? clock.now()
        notificationService.removePendingNotification(forHabitID: habitID, on: logicalDay)
        notificationService.removeDeliveredNotifications(forHabitID: habitID, on: logicalDay)
        notificationService.rescheduleNotifications(forHabitID: habitID)
    }

    func handleDeletion(forHabitID habitID: UUID, dashboard: DashboardProjection) {
        widgetSyncService.syncSnapshot(from: dashboard)
        notificationService.removeNotifications(forHabitID: habitID)
    }

    func syncNotificationsAfterUpdate(from draft: EditHabitDraft) async {
        if draft.reminderEnabled {
            await notificationService.prepareReminderNotifications(forHabitID: draft.id)
        } else {
            notificationService.removeNotifications(forHabitID: draft.id)
        }
    }
}
