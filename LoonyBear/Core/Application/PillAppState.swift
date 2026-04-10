import Combine
import Foundation
import UserNotifications

@MainActor
final class PillAppState: ObservableObject {
    @Published private(set) var dashboard = PillDashboardProjection.empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var actionErrorMessage: String?

    private let repository: PillRepository
    let notificationService: PillNotificationService
    private let sideEffectCoordinator: PillSideEffectCoordinator

    init(repository: PillRepository, notificationService: PillNotificationService, badgeService: AppBadgeService) {
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
        dashboard = PillDashboardProjection(pills: repository.fetchDashboardPills())
        sideEffectCoordinator.refreshDerivedState()
    }

    func handleAppDidBecomeActive() {
        notificationService.handleAppDidBecomeActive()
    }

    func pillDetails(id: UUID) -> PillDetailsProjection? {
        repository.fetchPillDetails(id: id)
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
