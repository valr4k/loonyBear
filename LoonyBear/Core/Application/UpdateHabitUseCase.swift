import Foundation

@MainActor
struct UpdateHabitUseCase {
    let repository: HabitRepository

    func execute(draft: EditHabitDraft) throws {
        guard !draft.trimmedName.isEmpty else {
            throw CreateHabitError.emptyName
        }

        guard draft.scheduleDays.rawValue != 0 else {
            throw CreateHabitError.noScheduleDays
        }

        try repository.updateHabit(from: draft)
    }
}
