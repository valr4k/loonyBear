import Foundation

@MainActor
struct HabitSideEffectCoordinator {
    let notificationService: NotificationService
    let widgetSyncService: WidgetSyncService
    let badgeService: AppBadgeService
    let clock: AppClock

    init(
        notificationService: NotificationService,
        widgetSyncService: WidgetSyncService,
        badgeService: AppBadgeService,
        clock: AppClock = .live
    ) {
        self.notificationService = notificationService
        self.widgetSyncService = widgetSyncService
        self.badgeService = badgeService
        self.clock = clock
    }

    func refreshDerivedState(with dashboard: DashboardProjection) {
        widgetSyncService.syncSnapshot(from: dashboard)
        badgeService.refreshBadge()
    }

    func handleDailyMutation(forHabitID habitID: UUID, on day: Date? = nil) {
        let logicalDay = day ?? clock.now()
        notificationService.rescheduleAllNotifications()
        notificationService.removeDeliveredNotifications(forHabitID: habitID, on: logicalDay)
    }

    func handleDeletion(forHabitID habitID: UUID, dashboard: DashboardProjection) {
        widgetSyncService.syncSnapshot(from: dashboard)
        notificationService.removeNotifications(forHabitID: habitID)
        badgeService.refreshBadge()
    }

    func syncNotificationsAfterUpdate(from draft: EditHabitDraft) async {
        if draft.reminderEnabled {
            await notificationService.prepareReminderNotifications(forHabitID: draft.id)
        } else {
            notificationService.removeNotifications(forHabitID: draft.id)
        }
    }
}
