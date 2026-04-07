import Foundation

protocol HabitRepository {
    func fetchDashboardHabits() -> [HabitCardProjection]
    func fetchHabitDetails(id: UUID) -> HabitDetailsProjection?
    func createHabit(from draft: CreateHabitDraft) throws -> UUID
    func completeHabitToday(id: UUID) throws
    func removeHabitCompletionToday(id: UUID) throws
    func deleteHabit(id: UUID) throws
    func moveHabits(of type: HabitType, from offsets: IndexSet, to destination: Int) throws
    func updateHabit(from draft: EditHabitDraft) throws
}

func reorderedItems<T>(_ items: [T], from offsets: IndexSet, to destination: Int) -> [T] {
    var reordered = items
    let movingItems = offsets.map { reordered[$0] }
    reordered.remove(atOffsets: offsets)

    var target = destination
    let removedBeforeDestination = offsets.filter { $0 < destination }.count
    target -= removedBeforeDestination
    target = min(max(target, 0), reordered.count)

    reordered.insert(contentsOf: movingItems, at: target)
    return reordered
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            remove(at: index)
        }
    }
}
