import Foundation

enum PillRepositoryError: LocalizedError {
    case internalFailure
    case tooManyPills

    var errorDescription: String? {
        switch self {
        case .internalFailure:
            return "Something went wrong. Try again."
        case .tooManyPills:
            return "Limit reached. You can add up to 20 pills."
        }
    }
}

@MainActor
protocol PillRepository {
    func fetchDashboardPills() throws -> [PillCardProjection]
    func fetchPillDetails(id: UUID) throws -> PillDetailsProjection?
    func reconcilePastDays(today: Date) throws -> Int
    func createPill(from draft: PillDraft) throws -> UUID
    func updatePill(from draft: EditPillDraft) throws
    func deletePill(id: UUID) throws
    func setPillArchived(id: UUID, isArchived: Bool) throws
    func markTakenToday(id: UUID) throws
    func markPillTaken(id: UUID, on day: Date) throws
    func skipPillToday(id: UUID) throws
    func skipPillDay(id: UUID, on day: Date) throws
    func clearPillDayStateToday(id: UUID) throws
    func clearPillDayState(id: UUID, on day: Date) throws
    func movePills(from offsets: IndexSet, to destination: Int) throws
}
