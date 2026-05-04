import Foundation

enum CreateHabitError: LocalizedError, Equatable {
    case emptyName
    case noScheduleDays
    case tooManyHabits

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a habit name."
        case .noScheduleDays:
            return AppCopy.chooseAtLeastOneDay
        case .tooManyHabits:
            return "Limit reached. You can add up to 20 habits."
        }
    }
}

@MainActor
struct CreateHabitUseCase {
    let repository: HabitRepository

    func execute(draft: CreateHabitDraft) throws -> UUID {
        guard !draft.trimmedName.isEmpty else {
            throw CreateHabitError.emptyName
        }

        guard draft.scheduleRule.isValidSelection else {
            throw CreateHabitError.noScheduleDays
        }

        return try repository.createHabit(from: draft)
    }
}
