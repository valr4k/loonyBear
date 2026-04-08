import Foundation

protocol HabitRepository {
    func fetchDashboardHabits() -> [HabitCardProjection]
    func fetchHabitDetails(id: UUID) -> HabitDetailsProjection?
    func createHabit(from draft: CreateHabitDraft) throws -> UUID
    func completeHabitToday(id: UUID) throws
    func removeHabitCompletionToday(id: UUID) throws
    func deleteHabit(id: UUID) throws
    func updateHabit(from draft: EditHabitDraft) throws
}
