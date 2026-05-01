import Combine
import Foundation

enum PillDetailsLoadState {
    case found(PillDetailsProjection)
    case notFound
    case integrityError(String)
}

@MainActor
final class PillAppState: ObservableObject {
    @Published private(set) var dashboard = PillDashboardProjection.empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var detailErrorMessage: String?

    private let reconcileHistoryUseCase: ReconcilePillHistoryUseCase
    private let repository: PillRepository
    let notificationService: PillNotificationService
    private let sideEffectCoordinator: PillSideEffectCoordinator
    private let writeCoordinator = AppStateWriteCoordinator(name: "LoonyBear.PillAppState.WriteQueue")
    private let clock: AppClock

    init(
        reconcileHistoryUseCase: ReconcilePillHistoryUseCase,
        repository: PillRepository,
        notificationService: PillNotificationService,
        badgeService: AppBadgeService,
        clock: AppClock? = nil,
        rescheduleAllReminderNotifications: (() -> Void)? = nil
    ) {
        let resolvedClock = clock ?? .live
        self.reconcileHistoryUseCase = reconcileHistoryUseCase
        self.repository = repository
        self.notificationService = notificationService
        self.clock = resolvedClock
        sideEffectCoordinator = PillSideEffectCoordinator(
            notificationService: notificationService,
            clock: resolvedClock,
            rescheduleAllReminderNotifications: rescheduleAllReminderNotifications
        )
    }

    func load() {
        isLoading = true
        refreshDashboard()
        hasLoadedOnce = true
        isLoading = false
    }

    func refreshDashboard() {
        do {
            dashboard = PillDashboardProjection(pills: try repository.fetchDashboardPills())
            sideEffectCoordinator.refreshDerivedState()
            actionErrorMessage = nil
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func handleAppDidBecomeActive() async {
        let shouldMarkInitialLoad = !hasLoadedOnce
        if shouldMarkInitialLoad {
            isLoading = true
        }

        await writeCoordinator.performReconciliation(
            logPrefix: "pill.history.reconcile",
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

    func pillDetails(id: UUID) throws -> PillDetailsProjection? {
        try repository.fetchPillDetails(id: id)
    }

    func inspectPillDetailsState(id: UUID) -> PillDetailsLoadState {
        do {
            guard let details = try repository.fetchPillDetails(id: id) else {
                return .notFound
            }
            return .found(details)
        } catch {
            return .integrityError(error.localizedDescription)
        }
    }

    func loadPillDetailsState(id: UUID) -> PillDetailsLoadState {
        let state = inspectPillDetailsState(id: id)
        switch state {
        case .found, .notFound:
            detailErrorMessage = nil
        case .integrityError(let message):
            detailErrorMessage = message
        }
        return state
    }

    func createPill(from draft: PillDraft) async throws -> UUID {
        try await writeCoordinator.performThrowingMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.repository.createPill(from: draft)
        }
    }

    func updatePill(from draft: EditPillDraft) async throws {
        try await writeCoordinator.performThrowingMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.repository.updatePill(from: draft)
        }
    }

    func markTakenToday(id: UUID) async {
        await markPillTaken(id: id, on: clock.now())
    }

    func markPillTaken(id: UUID, on day: Date) async {
        let didMutate = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            refreshOnFailure: true
        ) {
            try self.repository.markPillTaken(id: id, on: day)
        }
        guard didMutate else { return }

        sideEffectCoordinator.handleDailyMutation(forPillID: id, on: day)
    }

    func skipPillToday(id: UUID) async {
        await skipPillDay(id: id, on: clock.now())
    }

    func skipPillDay(id: UUID, on day: Date) async {
        let didMutate = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            refreshOnFailure: true
        ) {
            try self.repository.skipPillDay(id: id, on: day)
        }
        guard didMutate else { return }

        sideEffectCoordinator.handleDailyMutation(forPillID: id, on: day)
    }

    func clearPillDayStateToday(id: UUID) async {
        await clearPillDayState(id: id, on: clock.now())
    }

    func clearPillDayState(id: UUID, on day: Date) async {
        let didMutate = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            refreshOnFailure: true
        ) {
            try self.repository.clearPillDayState(id: id, on: day)
        }
        guard didMutate else { return }

        sideEffectCoordinator.handleDailyMutation(forPillID: id, on: day)
    }

    func deletePill(id: UUID) async {
        let didDelete = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            refreshOnFailure: true
        ) {
            try self.repository.deletePill(id: id)
        }
        guard didDelete else { return }

        sideEffectCoordinator.handleDeletion(forPillID: id)
    }

    func movePills(from offsets: IndexSet, to destination: Int) async {
        _ = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            refreshOnFailure: true
        ) {
            try self.repository.movePills(from: offsets, to: destination)
        }
    }

    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        await notificationService.ensureAuthorizationIfNeeded()
    }

    func prepareReminderNotifications(forPillID pillID: UUID) async {
        await sideEffectCoordinator.prepareReminderNotifications(forPillID: pillID)
    }

    func syncNotificationsAfterPillUpdate(from draft: EditPillDraft) async {
        await sideEffectCoordinator.syncNotificationsAfterUpdate(from: draft)
    }

    func clearActionError() {
        actionErrorMessage = nil
    }

}
