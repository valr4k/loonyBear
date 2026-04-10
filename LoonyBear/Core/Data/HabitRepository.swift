import Foundation

protocol HabitRepository {
    func fetchDashboardHabits() throws -> [HabitCardProjection]
    func fetchHabitDetails(id: UUID) throws -> HabitDetailsProjection?
    func createHabit(from draft: CreateHabitDraft) throws -> UUID
    func completeHabitToday(id: UUID) throws
    func skipHabitToday(id: UUID) throws
    func clearHabitDayStateToday(id: UUID) throws
    func deleteHabit(id: UUID) throws
    func updateHabit(from draft: EditHabitDraft) throws
}
