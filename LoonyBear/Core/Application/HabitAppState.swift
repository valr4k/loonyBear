import Combine
import Foundation

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
    private let writeCoordinator = AppStateWriteCoordinator(name: "LoonyBear.HabitAppState.WriteQueue")
    private let clock: AppClock

    init(
        loadDashboardUseCase: LoadDashboardUseCase,
        createHabitUseCase: CreateHabitUseCase,
        updateHabitUseCase: UpdateHabitUseCase,
        reconcileHistoryUseCase: ReconcileHabitHistoryUseCase,
        repository: HabitRepository,
        notificationService: NotificationService,
        widgetSyncService: WidgetSyncService,
        badgeService: AppBadgeService,
        clock: AppClock? = nil,
        rescheduleAllReminderNotifications: (() -> Void)? = nil
    ) {
        let resolvedClock = clock ?? .live
        self.loadDashboardUseCase = loadDashboardUseCase
        self.createHabitUseCase = createHabitUseCase
        self.updateHabitUseCase = updateHabitUseCase
        self.reconcileHistoryUseCase = reconcileHistoryUseCase
        self.repository = repository
        self.notificationService = notificationService
        self.clock = resolvedClock
        sideEffectCoordinator = HabitSideEffectCoordinator(
            notificationService: notificationService,
            widgetSyncService: widgetSyncService,
            clock: resolvedClock,
            rescheduleAllReminderNotifications: rescheduleAllReminderNotifications
        )
    }

    func load() async {
        isLoading = true
        refreshDashboard()
        hasLoadedOnce = true
        isLoading = false
    }

    func createHabit(from draft: CreateHabitDraft) async throws -> UUID {
        try await writeCoordinator.performThrowingMutation(
            refresh: refreshDashboard,
            setError: { self.createHabitErrorMessage = $0 }
        ) {
            try self.createHabitUseCase.execute(draft: draft)
        }
    }

    func clearCreateHabitError() {
        createHabitErrorMessage = nil
    }

    func completeHabitToday(id: UUID) async {
        await completeHabitDay(id: id, on: clock.now())
    }

    func completeHabitDay(id: UUID, on day: Date) async {
        let didComplete = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.repository.completeHabitDay(id: id, on: day)
        }
        guard didComplete else { return }

        sideEffectCoordinator.handleDailyMutation(forHabitID: id, on: day)
    }

    func skipHabitToday(id: UUID) async {
        await skipHabitDay(id: id, on: clock.now())
    }

    func skipHabitDay(id: UUID, on day: Date) async {
        let didSkip = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.repository.skipHabitDay(id: id, on: day)
        }
        guard didSkip else { return }

        sideEffectCoordinator.handleDailyMutation(forHabitID: id, on: day)
    }

    func clearHabitDayStateToday(id: UUID) async {
        await clearHabitDayState(id: id, on: clock.now())
    }

    func clearHabitDayState(id: UUID, on day: Date) async {
        let didClearDayState = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.repository.clearHabitDayState(id: id, on: day)
        }
        guard didClearDayState else { return }

        sideEffectCoordinator.handleDailyMutation(forHabitID: id, on: day)
    }

    func deleteHabit(id: UUID) async {
        do {
            dashboard = dashboardRemovingHabit(id: id)
            try await writeCoordinator.performWriteOperation {
                try self.repository.deleteHabit(id: id)
            }
            sideEffectCoordinator.handleDeletion(forHabitID: id, dashboard: dashboard)
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func setHabitArchived(id: UUID, isArchived: Bool) async {
        let didChange = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            refreshOnFailure: true
        ) {
            try self.repository.setHabitArchived(id: id, isArchived: isArchived)
        }
        guard didChange else { return }

        sideEffectCoordinator.handleArchiveChange(
            forHabitID: id,
            dashboard: dashboard,
            isArchived: isArchived
        )
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

    func updateHabit(from draft: EditHabitDraft) async throws {
        try await writeCoordinator.performThrowingMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.updateHabitUseCase.execute(draft: draft)
        }
    }

    func prepareReminderNotifications(forHabitID habitID: UUID) async {
        await sideEffectCoordinator.prepareReminderNotifications(forHabitID: habitID)
    }

    func syncNotificationsAfterHabitUpdate(from draft: EditHabitDraft) async {
        await sideEffectCoordinator.syncNotificationsAfterUpdate(from: draft)
    }

    func handleAppDidBecomeActive() async {
        let shouldMarkInitialLoad = !hasLoadedOnce
        if shouldMarkInitialLoad {
            isLoading = true
        }

        await writeCoordinator.performReconciliation(
            logPrefix: "habit.history.reconcile",
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            afterRefresh: notificationService.handleAppDidBecomeActive
        ) {
            try self.reconcileHistoryUseCase.execute()
        }

        if shouldMarkInitialLoad {
            hasLoadedOnce = true
            isLoading = false
        }
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

    private func dashboardRemovingHabit(id: UUID) -> DashboardProjection {
        let sections: [HabitSectionProjection] = dashboard.sections.compactMap { section in
            let habits = section.habits.filter { $0.id != id }
            guard !habits.isEmpty else { return nil }
            return HabitSectionProjection(id: section.id, title: section.title, habits: habits)
        }

        return DashboardProjection(sections: sections)
    }
}
