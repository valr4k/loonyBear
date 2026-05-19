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
    func restorePill(from draft: EditPillDraft, historyMode: RestoreHistoryMode) throws -> Bool
    func deletePill(id: UUID) throws -> Bool
    func setPillArchived(id: UUID, isArchived: Bool) throws -> Bool
    func markTakenToday(id: UUID) throws -> Bool
    func markPillTaken(id: UUID, on day: Date) throws -> Bool
    func skipPillToday(id: UUID) throws -> Bool
    func skipPillDay(id: UUID, on day: Date) throws -> Bool
    func clearPillDayStateToday(id: UUID) throws -> Bool
    func clearPillDayState(id: UUID, on day: Date) throws -> Bool
    func movePills(from offsets: IndexSet, to destination: Int) throws
}

extension PillRepository {
    @discardableResult
    func restorePill(from draft: EditPillDraft) throws -> Bool {
        try restorePill(from: draft, historyMode: .keepHistory)
    }
}
