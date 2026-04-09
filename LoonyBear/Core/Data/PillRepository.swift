import Foundation

enum PillRepositoryError: LocalizedError {
    case internalFailure

    var errorDescription: String? {
        switch self {
        case .internalFailure:
            return "Pill operation failed unexpectedly."
        }
    }
}

protocol PillRepository {
    func fetchDashboardPills() -> [PillCardProjection]
    func fetchPillDetails(id: UUID) -> PillDetailsProjection?
    func createPill(from draft: PillDraft) throws -> UUID
    func updatePill(from draft: EditPillDraft) throws
    func deletePill(id: UUID) throws
    func markTakenToday(id: UUID) throws
    func skipPillToday(id: UUID) throws
    func clearPillDayStateToday(id: UUID) throws
    func movePills(from offsets: IndexSet, to destination: Int) throws
}
