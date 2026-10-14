import Combine
import Foundation
import SwiftUI

enum EventDetailsLoadState {
    case found(EventDetailsProjection)
    case notFound
    case integrityError(String)
}

@MainActor
final class EventAppState: ObservableObject {
    @Published private(set) var dashboard = EventDashboardProjection.empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var detailErrorMessage: String?

    private let repository: EventRepository
    private let onBadgeStateChanged: () -> Void
    private let writeCoordinator = AppStateWriteCoordinator(name: "LoonyBear.EventAppState.WriteQueue")

    init(repository: EventRepository, onBadgeStateChanged: @escaping () -> Void = {}) {
        self.repository = repository
        self.onBadgeStateChanged = onBadgeStateChanged
    }

    func load() {
        isLoading = true
        do { try repository.prepareLocalDates() } catch {
            actionErrorMessage = UserFacingErrorMessage.text(for: error)
            isLoading = false
            hasLoadedOnce = true
            return
        }
        refreshDashboard()
        hasLoadedOnce = true
        isLoading = false
    }

    func refreshDashboard() {
        do {
            let events = try repository.fetchDashboardEvents()
            let nextDashboard = PerformanceLog.measure("event.dashboard.projection") {
                EventDashboardProjection(events: events)
            }
            PerformanceLog.measure("event.dashboard.publish") {
                dashboard = nextDashboard
            }
            actionErrorMessage = nil
        } catch {
            actionErrorMessage = UserFacingErrorMessage.text(for: error)
        }
    }

    func eventDetails(id: UUID) throws -> EventDetailsProjection? {
        try repository.fetchEventDetails(id: id)
    }

    func inspectEventDetailsState(id: UUID) -> EventDetailsLoadState {
        do {
            guard let details = try repository.fetchEventDetails(id: id) else {
                return .notFound
            }
            return .found(details)
        } catch {
            return .integrityError(error.localizedDescription)
        }
    }

    func loadEventDetailsState(id: UUID) -> EventDetailsLoadState {
        let state = inspectEventDetailsState(id: id)
        switch state {
        case .found, .notFound:
            detailErrorMessage = nil
        case .integrityError(let message):
            detailErrorMessage = message
        }
        return state
    }

    func createEvent(from draft: EventDraft) async throws -> UUID {
        let id = try await writeCoordinator.performThrowingMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.repository.createEvent(from: draft)
        }
        onBadgeStateChanged()
        return id
    }

    func updateEvent(from draft: EditEventDraft) async throws {
        try await writeCoordinator.performThrowingMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 }
        ) {
            try self.repository.updateEvent(from: draft)
        }
        onBadgeStateChanged()
    }

    func deleteEvent(id: UUID) async {
        let didDelete = await writeCoordinator.performMutation(
            refresh: refreshDashboard,
            setError: { self.actionErrorMessage = $0 },
            refreshOnFailure: true
        ) {
            try self.repository.deleteEvent(id: id)
        }
        if didDelete { onBadgeStateChanged() }
    }

    func acknowledgeEvent(id: UUID) async {
        let didChange = await writeCoordinator.performMutation(
            refresh: refreshDashboard, setError: { self.actionErrorMessage = $0 }
        ) { try self.repository.acknowledgeEvent(id: id) }
        if didChange { onBadgeStateChanged() }
    }

    func reorderEvents(ids: [UUID], mode: EventMode) async {
        _ = await writeCoordinator.performMutation(
            refresh: refreshDashboard, setError: { self.actionErrorMessage = $0 }, refreshOnFailure: true
        ) { try self.repository.reorderEvents(ids: ids, mode: mode) }
    }

    func clearActionError() {
        actionErrorMessage = nil
    }
}
