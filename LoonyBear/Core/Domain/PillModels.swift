import Foundation

enum PillCompletionSource: String, Codable {
    case swipe = "swipe"
    case manualEdit = "manual edit"
    case notification = "notification"
    case restore = "restore"
    case skipped = "skipped"

    var countsAsIntake: Bool {
        self != .skipped
    }
}

struct Pill: Identifiable, Equatable {
    let id: UUID
    let name: String
    let dosage: String
    let details: String?
    let sortOrder: Int
    let startDate: Date
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

struct PillScheduleVersion: Identifiable, Equatable {
    let id: UUID
    let pillID: UUID
    let weekdays: WeekdaySet
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int
}

struct PillIntake: Identifiable, Equatable {
    let id: UUID
    let pillID: UUID
    let localDate: Date
    let source: PillCompletionSource
    let createdAt: Date
}

struct PillCardProjection: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let dosage: String
    let scheduleSummary: String
    let totalTakenDays: Int
    let reminderText: String?
    let reminderHour: Int?
    let reminderMinute: Int?
    let isReminderScheduledToday: Bool
    let isScheduledToday: Bool
    let isTakenToday: Bool
    let isSkippedToday: Bool
    let sortOrder: Int
}

struct PillDetailsProjection: Equatable {
    let id: UUID
    let name: String
    let dosage: String
    let details: String?
    let startDate: Date
    let scheduleSummary: String
    let scheduleDays: WeekdaySet
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let totalTakenDays: Int
    let takenDays: Set<Date>
    let skippedDays: Set<Date>
}

struct PillDashboardProjection: Equatable {
    let pills: [PillCardProjection]

    static let empty = PillDashboardProjection(pills: [])
}

struct PillDraft: Equatable {
    var name = ""
    var dosage = ""
    var details = ""
    var startDate: Date = Calendar.current.startOfDay(for: Date())
    var scheduleDays: WeekdaySet = .daily
    var useScheduleForHistory = true
    var reminderEnabled = false
    var reminderTime = ReminderTime.default()
    var takenDays: Set<Date> = []

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDosage: String {
        dosage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDetails: String? {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct EditPillDraft: Equatable {
    let id: UUID
    var name: String
    var dosage: String
    var details: String
    let startDate: Date
    var scheduleDays: WeekdaySet
    var reminderEnabled: Bool
    var reminderTime: ReminderTime
    var takenDays: Set<Date>
    var skippedDays: Set<Date>

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDosage: String {
        dosage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDetails: String? {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
