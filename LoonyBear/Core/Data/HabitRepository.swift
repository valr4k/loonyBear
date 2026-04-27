import Foundation

@MainActor
protocol HabitRepository {
    func fetchDashboardHabits() throws -> [HabitCardProjection]
    func fetchHabitDetails(id: UUID) throws -> HabitDetailsProjection?
    func reconcilePastDays(today: Date) throws -> Int
    func createHabit(from draft: CreateHabitDraft) throws -> UUID
    func completeHabitToday(id: UUID) throws
    func completeHabitDay(id: UUID, on day: Date) throws
    func skipHabitToday(id: UUID) throws
    func skipHabitDay(id: UUID, on day: Date) throws
    func clearHabitDayStateToday(id: UUID) throws
    func clearHabitDayState(id: UUID, on day: Date) throws
    func deleteHabit(id: UUID) throws
    func updateHabit(from draft: EditHabitDraft) throws
}
