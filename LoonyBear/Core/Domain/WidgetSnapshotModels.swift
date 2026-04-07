import Foundation

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let sections: [WidgetSectionSnapshot]
}

struct WidgetSectionSnapshot: Codable {
    let type: String
    let title: String
    let habits: [WidgetHabitSnapshot]
}

struct WidgetHabitSnapshot: Codable {
    let id: UUID
    let name: String
    let scheduleSummary: String
    let currentStreak: Int
    let isCompletedToday: Bool
}
