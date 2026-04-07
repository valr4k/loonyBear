import Foundation

struct LoadDashboardUseCase {
    let repository: HabitRepository

    func execute() -> DashboardProjection {
        let habits = repository.fetchDashboardHabits()

        let grouped = Dictionary(grouping: habits, by: \.type)
        let sections = HabitType.allCases.compactMap { type -> HabitSectionProjection? in
            let sectionHabits = grouped[type, default: []]
            guard !sectionHabits.isEmpty else { return nil }
            return HabitSectionProjection(
                id: type,
                title: type.sectionTitle,
                habits: sectionHabits
            )
        }

        return DashboardProjection(sections: sections)
    }
}
