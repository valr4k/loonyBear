import Foundation

@MainActor
protocol HabitRepository {
    func fetchDashboardHabits() throws -> [HabitCardProjection]
    func fetchHabitDetails(id: UUID) throws -> HabitDetailsProjection?
    func reconcilePastDays(today: Date) throws -> Int
    func createHabit(from draft: CreateHabitDraft) throws -> UUID
    func completeHabitToday(id: UUID) throws -> Bool
    func completeHabitDay(id: UUID, on day: Date) throws -> Bool
    func skipHabitToday(id: UUID) throws -> Bool
    func skipHabitDay(id: UUID, on day: Date) throws -> Bool
    func clearHabitDayStateToday(id: UUID) throws -> Bool
    func clearHabitDayState(id: UUID, on day: Date) throws -> Bool
    func deleteHabit(id: UUID) throws -> Bool
    func setHabitArchived(id: UUID, isArchived: Bool) throws -> Bool
    func updateHabit(from draft: EditHabitDraft) throws
    func restoreHabit(from draft: EditHabitDraft, historyMode: RestoreHistoryMode) throws -> Bool
}

extension HabitRepository {
    @discardableResult
    func restoreHabit(from draft: EditHabitDraft) throws -> Bool {
        try restoreHabit(from: draft, historyMode: .keepHistory)
    }
}
