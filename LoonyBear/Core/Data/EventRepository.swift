import Foundation

enum EventRepositoryError: LocalizedError {
    case internalFailure

    var errorDescription: String? {
        switch self {
        case .internalFailure:
            return "Something went wrong. Try again."
        }
    }
}

@MainActor
protocol EventRepository {
    func fetchDashboardEvents() throws -> [EventCardProjection]
    func fetchEventDetails(id: UUID) throws -> EventDetailsProjection?
    func createEvent(from draft: EventDraft) throws -> UUID
    func updateEvent(from draft: EditEventDraft) throws
    func deleteEvent(id: UUID) throws
}
