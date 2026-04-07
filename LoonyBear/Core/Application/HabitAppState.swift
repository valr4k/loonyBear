import Combine
import Foundation
import UserNotifications

@MainActor
final class HabitAppState: ObservableObject {
    @Published private(set) var dashboard = DashboardProjection.empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var createHabitErrorMessage: String?
    @Published private(set) var actionErrorMessage: String?

    private let loadDashboardUseCase: LoadDashboardUseCase
    private let createHabitUseCase: CreateHabitUseCase
    private let updateHabitUseCase: UpdateHabitUseCase
    private let repository: HabitRepository
    let notificationService: NotificationService
    private let widgetSyncService: WidgetSyncService
    private let badgeService: AppBadgeService

    init(
        loadDashboardUseCase: LoadDashboardUseCase,
        createHabitUseCase: CreateHabitUseCase,
        updateHabitUseCase: UpdateHabitUseCase,
        repository: HabitRepository,
        notificationService: NotificationService,
        widgetSyncService: WidgetSyncService,
        badgeService: AppBadgeService
    ) {
        self.loadDashboardUseCase = loadDashboardUseCase
        self.createHabitUseCase = createHabitUseCase
        self.updateHabitUseCase = updateHabitUseCase
        self.repository = repository
        self.notificationService = notificationService
        self.widgetSyncService = widgetSyncService
        self.badgeService = badgeService
    }

    func load() async {
        isLoading = true
        refreshDashboard()
        hasLoadedOnce = true
        isLoading = false
    }

    func createHabit(from draft: CreateHabitDraft) throws -> UUID {
        do {
            let habitID = try createHabitUseCase.execute(draft: draft)
            createHabitErrorMessage = nil
            refreshDashboard()
            return habitID
        } catch {
            createHabitErrorMessage = error.localizedDescription
            throw error
        }
    }

    func clearCreateHabitError() {
        createHabitErrorMessage = nil
    }

    func completeHabitToday(id: UUID) {
        let didComplete = performDashboardMutation {
            try repository.completeHabitToday(id: id)
        }
        guard didComplete else { return }

        notificationService.rescheduleAllNotifications()
        notificationService.removeDeliveredNotifications(forHabitID: id, on: Date())
    }

    func removeHabitCompletionToday(id: UUID) {
        let didRemoveCompletion = performDashboardMutation {
            try repository.removeHabitCompletionToday(id: id)
        }
        guard didRemoveCompletion else { return }

        notificationService.rescheduleAllNotifications()
    }

    func deleteHabit(id: UUID) {
        do {
            dashboard = dashboardRemovingHabit(id: id)
            try repository.deleteHabit(id: id)
            widgetSyncService.syncSnapshot(from: dashboard)
            notificationService.removeNotifications(forHabitID: id)
            badgeService.refreshBadge()
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func moveHabits(of type: HabitType, from offsets: IndexSet, to destination: Int) {
        do {
            try repository.moveHabits(of: type, from: offsets, to: destination)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func clearActionError() {
        actionErrorMessage = nil
    }

    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        await notificationService.ensureAuthorizationIfNeeded()
    }

    func habitDetails(id: UUID) -> HabitDetailsProjection? {
        repository.fetchHabitDetails(id: id)
    }

    func updateHabit(from draft: EditHabitDraft) throws {
        do {
            try updateHabitUseCase.execute(draft: draft)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            actionErrorMessage = error.localizedDescription
            throw error
        }
    }

    func prepareReminderNotifications(forHabitID habitID: UUID) async {
        await notificationService.prepareReminderNotifications(forHabitID: habitID)
    }

    func syncNotificationsAfterHabitUpdate(from draft: EditHabitDraft) async {
        if draft.reminderEnabled {
            await notificationService.prepareReminderNotifications(forHabitID: draft.id)
        } else {
            notificationService.removeNotifications(forHabitID: draft.id)
        }
    }

    func refreshDashboard() {
        dashboard = loadDashboardUseCase.execute()
        widgetSyncService.syncSnapshot(from: dashboard)
        badgeService.refreshBadge()
    }

    private func performDashboardMutation(_ mutation: () throws -> Void) -> Bool {
        do {
            try mutation()
            refreshDashboard()
            actionErrorMessage = nil
            return true
        } catch {
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    private func dashboardRemovingHabit(id: UUID) -> DashboardProjection {
        let sections: [HabitSectionProjection] = dashboard.sections.compactMap { section in
            let habits = section.habits.filter { $0.id != id }
            guard !habits.isEmpty else { return nil }
            return HabitSectionProjection(id: section.id, title: section.title, habits: habits)
        }

        return DashboardProjection(sections: sections)
    }
}
