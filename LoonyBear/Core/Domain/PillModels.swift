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

enum PillHistoryMode: String, Codable, Equatable {
    case scheduleBased = "scheduleBased"
    case everyDay = "everyDay"

    var usesScheduleForHistory: Bool {
        self == .scheduleBased
    }
}

struct Pill: Identifiable, Equatable {
    let id: UUID
    let name: String
    let dosage: String
    let details: String?
    let sortOrder: Int
    let startDate: Date
    let historyMode: PillHistoryMode
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

struct PillScheduleVersion: Identifiable, Equatable {
    let id: UUID
    let pillID: UUID
    let rule: ScheduleRule
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int

    init(
        id: UUID,
        pillID: UUID,
        weekdays: WeekdaySet,
        effectiveFrom: Date,
        createdAt: Date,
        version: Int
    ) {
        self.init(
            id: id,
            pillID: pillID,
            rule: .weekly(weekdays),
            effectiveFrom: effectiveFrom,
            createdAt: createdAt,
            version: version
        )
    }

    init(
        id: UUID,
        pillID: UUID,
        rule: ScheduleRule,
        effectiveFrom: Date,
        createdAt: Date,
        version: Int
    ) {
        self.id = id
        self.pillID = pillID
        self.rule = rule
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
        self.version = version
    }

    var weekdays: WeekdaySet {
        rule.weeklyDays ?? .daily
    }
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
    var needsHistoryReview = false
    var activeOverdueDay: Date?
    let sortOrder: Int
}

struct PillDetailsProjection: Equatable {
    let id: UUID
    let name: String
    let dosage: String
    let details: String?
    let startDate: Date
    let historyMode: PillHistoryMode
    let scheduleSummary: String
    let scheduleDays: WeekdaySet
    let scheduleRule: ScheduleRule
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let totalTakenDays: Int
    let takenDays: Set<Date>
    let skippedDays: Set<Date>
    var needsHistoryReview = false
    var requiredPastScheduledDays: Set<Date> = []
    var activeOverdueDay: Date?
}

struct PillDashboardProjection: Equatable {
    let pills: [PillCardProjection]

    static let empty = PillDashboardProjection(pills: [])
}

struct PillDraft: Equatable {
    var name = ""
    var dosage = ""
    var details = ""
    var startDate: Date = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    var scheduleRule: ScheduleRule = .weekly(.daily)
    var useScheduleForHistory = true
    var reminderEnabled = false
    var reminderTime = ReminderTime.default()
    var takenDays: Set<Date> = []

    var scheduleDays: WeekdaySet {
        get { scheduleRule.weeklyDays ?? .daily }
        set { scheduleRule = .weekly(newValue) }
    }

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
    var scheduleRule: ScheduleRule
    var reminderEnabled: Bool
    var reminderTime: ReminderTime
    var takenDays: Set<Date>
    var skippedDays: Set<Date>

    init(
        id: UUID,
        name: String,
        dosage: String,
        details: String,
        startDate: Date,
        scheduleDays: WeekdaySet,
        reminderEnabled: Bool,
        reminderTime: ReminderTime,
        takenDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.details = details
        self.startDate = startDate
        self.scheduleRule = .weekly(scheduleDays)
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.takenDays = takenDays
        self.skippedDays = skippedDays
    }

    init(
        id: UUID,
        name: String,
        dosage: String,
        details: String,
        startDate: Date,
        scheduleRule: ScheduleRule,
        reminderEnabled: Bool,
        reminderTime: ReminderTime,
        takenDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.details = details
        self.startDate = startDate
        self.scheduleRule = scheduleRule
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.takenDays = takenDays
        self.skippedDays = skippedDays
    }

    var scheduleDays: WeekdaySet {
        get { scheduleRule.weeklyDays ?? .daily }
        set { scheduleRule = .weekly(newValue) }
    }

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
