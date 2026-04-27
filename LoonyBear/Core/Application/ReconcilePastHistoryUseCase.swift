import Foundation

@MainActor
struct ReconcileHabitHistoryUseCase {
    let repository: HabitRepository
    let clock: AppClock

    init(repository: HabitRepository, clock: AppClock? = nil) {
        self.repository = repository
        self.clock = clock ?? .live
    }

    func execute(today: Date? = nil) throws -> Int {
        try repository.reconcilePastDays(today: today ?? clock.now())
    }
}

@MainActor
struct ReconcilePillHistoryUseCase {
    let repository: PillRepository
    let clock: AppClock

    init(repository: PillRepository, clock: AppClock? = nil) {
        self.repository = repository
        self.clock = clock ?? .live
    }

    func execute(today: Date? = nil) throws -> Int {
        try repository.reconcilePastDays(today: today ?? clock.now())
    }
}
