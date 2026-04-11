import Combine
import Foundation
import UserNotifications

enum HabitDetailsLoadState {
    case found(HabitDetailsProjection)
    case notFound
    case integrityError(String)
}

@MainActor
final class HabitAppState: ObservableObject {
    @Published private(set) var dashboard = DashboardProjection.empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var createHabitErrorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var detailErrorMessage: String?

    private let loadDashboardUseCase: LoadDashboardUseCase
    private let createHabitUseCase: CreateHabitUseCase
    private let updateHabitUseCase: UpdateHabitUseCase
    private let reconcileHistoryUseCase: ReconcileHabitHistoryUseCase
    private let repository: HabitRepository
    let notificationService: NotificationService
    private let sideEffectCoordinator: HabitSideEffectCoordinator

    init(
        loadDashboardUseCase: LoadDashboardUseCase,
        createHabitUseCase: CreateHabitUseCase,
        updateHabitUseCase: UpdateHabitUseCase,
        reconcileHistoryUseCase: ReconcileHabitHistoryUseCase,
        repository: HabitRepository,
        notificationService: NotificationService,
        widgetSyncService: WidgetSyncService,
        badgeService: AppBadgeService
    ) {
        self.loadDashboardUseCase = loadDashboardUseCase
        self.createHabitUseCase = createHabitUseCase
        self.updateHabitUseCase = updateHabitUseCase
        self.reconcileHistoryUseCase = reconcileHistoryUseCase
        self.repository = repository
        self.notificationService = notificationService
        sideEffectCoordinator = HabitSideEffectCoordinator(
            notificationService: notificationService,
            widgetSyncService: widgetSyncService,
            badgeService: badgeService
        )
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

        sideEffectCoordinator.handleDailyMutation(forHabitID: id)
    }

    func skipHabitToday(id: UUID) {
        let didSkip = performDashboardMutation {
            try repository.skipHabitToday(id: id)
        }
        guard didSkip else { return }

        sideEffectCoordinator.handleDailyMutation(forHabitID: id)
    }

    func clearHabitDayStateToday(id: UUID) {
        let didClearDayState = performDashboardMutation {
            try repository.clearHabitDayStateToday(id: id)
        }
        guard didClearDayState else { return }

        sideEffectCoordinator.handleDailyMutation(forHabitID: id)
    }

    func deleteHabit(id: UUID) {
        do {
            dashboard = dashboardRemovingHabit(id: id)
            try repository.deleteHabit(id: id)
            sideEffectCoordinator.handleDeletion(forHabitID: id, dashboard: dashboard)
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

    func habitDetails(id: UUID) throws -> HabitDetailsProjection? {
        try repository.fetchHabitDetails(id: id)
    }

    func inspectHabitDetailsState(id: UUID) -> HabitDetailsLoadState {
        do {
            guard let details = try repository.fetchHabitDetails(id: id) else {
                return .notFound
            }
            return .found(details)
        } catch {
            return .integrityError(error.localizedDescription)
        }
    }

    func loadHabitDetailsState(id: UUID) -> HabitDetailsLoadState {
        let state = inspectHabitDetailsState(id: id)
        switch state {
        case .found, .notFound:
            detailErrorMessage = nil
        case .integrityError(let message):
            detailErrorMessage = message
        }
        return state
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
        await sideEffectCoordinator.syncNotificationsAfterUpdate(from: draft)
    }

    func handleAppDidBecomeActive() {
        var reconciliationErrorMessage: String?

        do {
            let finalizedDays = try reconcileHistoryUseCase.execute()
            if finalizedDays > 0 {
                ReliabilityLog.info("habit.history.reconcile finalized \(finalizedDays) day(s)")
            }
        } catch {
            reconciliationErrorMessage = error.localizedDescription
            ReliabilityLog.error("habit.history.reconcile failed: \(error.localizedDescription)")
        }

        refreshDashboard()
        if let reconciliationErrorMessage {
            actionErrorMessage = reconciliationErrorMessage
        }
        notificationService.handleAppDidBecomeActive()
    }

    func refreshDashboard() {
        do {
            dashboard = try loadDashboardUseCase.execute()
            sideEffectCoordinator.refreshDerivedState(with: dashboard)
            actionErrorMessage = nil
        } catch {
            actionErrorMessage = error.localizedDescription
        }
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
