import Foundation

@MainActor
struct LoadDashboardUseCase {
    let repository: HabitRepository

    func execute() throws -> DashboardProjection {
        let habits = try repository.fetchDashboardHabits()
        let activeHabits = habits.filter { !$0.isArchived }
        let archivedHabits = habits.filter(\.isArchived)

        let grouped = Dictionary(grouping: activeHabits, by: \.type)
        var sections = HabitType.allCases.compactMap { type -> HabitSectionProjection? in
            let sectionHabits = grouped[type, default: []]
            guard !sectionHabits.isEmpty else { return nil }
            return HabitSectionProjection(
                id: HabitSectionID(type: type),
                title: type.sectionTitle,
                habits: sectionHabits
            )
        }
        if !archivedHabits.isEmpty {
            sections.append(
                HabitSectionProjection(
                    id: .archived,
                    title: "Archived",
                    habits: archivedHabits
                )
            )
        }

        return DashboardProjection(sections: sections)
    }
}
