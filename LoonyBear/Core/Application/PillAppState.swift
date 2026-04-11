import Combine
import Foundation
import UserNotifications

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

    init(
        reconcileHistoryUseCase: ReconcilePillHistoryUseCase,
        repository: PillRepository,
        notificationService: PillNotificationService,
        badgeService: AppBadgeService
    ) {
        self.reconcileHistoryUseCase = reconcileHistoryUseCase
        self.repository = repository
        self.notificationService = notificationService
        sideEffectCoordinator = PillSideEffectCoordinator(
            notificationService: notificationService,
            badgeService: badgeService
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

    func handleAppDidBecomeActive() {
        var reconciliationErrorMessage: String?

        do {
            let finalizedDays = try reconcileHistoryUseCase.execute()
            if finalizedDays > 0 {
                ReliabilityLog.info("pill.history.reconcile finalized \(finalizedDays) day(s)")
            }
        } catch {
            reconciliationErrorMessage = error.localizedDescription
            ReliabilityLog.error("pill.history.reconcile failed: \(error.localizedDescription)")
        }

        refreshDashboard()
        if let reconciliationErrorMessage {
            actionErrorMessage = reconciliationErrorMessage
        }
        notificationService.handleAppDidBecomeActive()
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

    func createPill(from draft: PillDraft) throws -> UUID {
        do {
            let pillID = try repository.createPill(from: draft)
            refreshDashboard()
            actionErrorMessage = nil
            return pillID
        } catch {
            actionErrorMessage = error.localizedDescription
            throw error
        }
    }

    func updatePill(from draft: EditPillDraft) throws {
        do {
            try repository.updatePill(from: draft)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            actionErrorMessage = error.localizedDescription
            throw error
        }
    }

    func markTakenToday(id: UUID) {
        do {
            try repository.markTakenToday(id: id)
            sideEffectCoordinator.handleDailyMutation(forPillID: id)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func skipPillToday(id: UUID) {
        do {
            try repository.skipPillToday(id: id)
            sideEffectCoordinator.handleDailyMutation(forPillID: id)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func clearPillDayStateToday(id: UUID) {
        do {
            try repository.clearPillDayStateToday(id: id)
            sideEffectCoordinator.handleDailyMutation(forPillID: id)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func deletePill(id: UUID) {
        do {
            try repository.deletePill(id: id)
            sideEffectCoordinator.handleDeletion(forPillID: id)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func movePills(from offsets: IndexSet, to destination: Int) {
        do {
            try repository.movePills(from: offsets, to: destination)
            refreshDashboard()
            actionErrorMessage = nil
        } catch {
            refreshDashboard()
            actionErrorMessage = error.localizedDescription
        }
    }

    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        await notificationService.ensureAuthorizationIfNeeded()
    }

    func prepareReminderNotifications(forPillID pillID: UUID) async {
        await notificationService.prepareReminderNotifications(forPillID: pillID)
    }

    func syncNotificationsAfterPillUpdate(from draft: EditPillDraft) async {
        await sideEffectCoordinator.syncNotificationsAfterUpdate(from: draft)
    }

    func clearActionError() {
        actionErrorMessage = nil
    }
}
