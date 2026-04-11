import Foundation

@MainActor
struct ReconcileHabitHistoryUseCase {
    let repository: HabitRepository

    func execute(today: Date = Date()) throws -> Int {
        try repository.reconcilePastDays(today: today)
    }
}

@MainActor
struct ReconcilePillHistoryUseCase {
    let repository: PillRepository

    func execute(today: Date = Date()) throws -> Int {
        try repository.reconcilePastDays(today: today)
    }
}
