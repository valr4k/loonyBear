import Foundation

enum HabitType: String, Codable, CaseIterable, Identifiable {
    case build
    case quit

    var id: String { rawValue }

    var sectionTitle: String {
        switch self {
        case .build:
            return "Build Habit"
        case .quit:
            return "Quit Habit"
        }
    }
}

enum CompletionSource: String, Codable {
    case swipe = "swipe"
    case manualEdit = "manual edit"
    case notification = "notification"
    case restore = "restore"
    case autoFill = "auto fill"
    case skipped = "skipped"

    var countsAsCompletion: Bool {
        self != .skipped
    }
}

enum HabitHistoryMode: String, Codable, Equatable {
    case scheduleBased = "scheduleBased"
    case everyDay = "everyDay"

    var usesScheduleForHistory: Bool {
        self == .scheduleBased
    }
}

struct ReminderTime: Codable, Equatable {
    let hour: Int
    let minute: Int

    static func `default`(calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) -> ReminderTime {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        let roundedMinute = ((minute + 4) / 5) * 5

        if roundedMinute == 60 {
            return ReminderTime(hour: (hour + 1) % 24, minute: 0)
        }

        return ReminderTime(hour: hour, minute: roundedMinute)
    }

    var formatted: String {
        let components = DateComponents(hour: hour, minute: minute)
        return Calendar.autoupdatingCurrent.date(from: components)?
            .formatted(date: .omitted, time: .shortened) ?? "Not set"
    }
}

struct WeekdaySet: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let monday = WeekdaySet(rawValue: 1 << 0)
    static let tuesday = WeekdaySet(rawValue: 1 << 1)
    static let wednesday = WeekdaySet(rawValue: 1 << 2)
    static let thursday = WeekdaySet(rawValue: 1 << 3)
    static let friday = WeekdaySet(rawValue: 1 << 4)
    static let saturday = WeekdaySet(rawValue: 1 << 5)
    static let sunday = WeekdaySet(rawValue: 1 << 6)

    static let weekdays: WeekdaySet = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekends: WeekdaySet = [.saturday, .sunday]
    static let daily: WeekdaySet = [.weekdays, .weekends]

    static let orderedDays: [(String, WeekdaySet)] = [
        ("Mon", .monday),
        ("Tue", .tuesday),
        ("Wed", .wednesday),
        ("Thu", .thursday),
        ("Fri", .friday),
        ("Sat", .saturday),
        ("Sun", .sunday),
    ]

    var summary: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekends:
            return "Weekends"
        default:
            let labels = Self.orderedDays.compactMap { contains($0.1) ? $0.0 : nil }
            return labels.joined(separator: ", ")
        }
    }

    var compactSummary: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekends:
            return "Weekends"
        default:
            return "Custom"
        }
    }

    var summaryOrPlaceholder: String {
        rawValue == 0 ? "Select days" : summary
    }

    var compactSummaryOrPlaceholder: String {
        rawValue == 0 ? "Select days" : compactSummary
    }
}

enum ScheduleIntervalPreset: String, Codable, CaseIterable, Hashable {
    case daily
    case weekdays
    case weekends
    case weekly
    case biweekly

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekends:
            return "Weekends"
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Biweekly"
        }
    }

    var storageWeekdayMask: Int {
        switch self {
        case .daily:
            return WeekdaySet.daily.rawValue
        case .weekdays:
            return WeekdaySet.weekdays.rawValue
        case .weekends:
            return WeekdaySet.weekends.rawValue
        case .weekly, .biweekly:
            return 0
        }
    }

    var storageIntervalDays: Int {
        switch self {
        case .daily:
            return 1
        case .weekly:
            return 7
        case .biweekly:
            return 14
        case .weekdays, .weekends:
            return ScheduleRule.defaultIntervalDays
        }
    }
}

enum ScheduleRule: Equatable, Hashable {
    enum Kind: String, Codable {
        case weekly
        case daily
        case weekdays
        case weekends
        case weeklyInterval
        case biweekly
        case intervalDays
    }

    nonisolated static let defaultIntervalDays = 2
    nonisolated static let intervalDaysRange = 2 ... 14
    nonisolated private static let validWeekdayMask = WeekdaySet.daily.rawValue

    case weekly(WeekdaySet)
    case intervalPreset(ScheduleIntervalPreset)
    case intervalDays(Int)

    var kind: Kind {
        switch self {
        case .weekly:
            return .weekly
        case let .intervalPreset(preset):
            switch preset {
            case .daily:
                return .daily
            case .weekdays:
                return .weekdays
            case .weekends:
                return .weekends
            case .weekly:
                return .weeklyInterval
            case .biweekly:
                return .biweekly
            }
        case .intervalDays:
            return .intervalDays
        }
    }

    var weeklyDays: WeekdaySet? {
        switch self {
        case let .weekly(days):
            return days
        case .intervalPreset(.daily):
            return .daily
        case .intervalPreset(.weekdays):
            return .weekdays
        case .intervalPreset(.weekends):
            return .weekends
        case .intervalPreset(.weekly), .intervalPreset(.biweekly), .intervalDays:
            return nil
        }
    }

    var intervalDays: Int? {
        switch self {
        case .intervalPreset(.daily):
            return 1
        case .intervalPreset(.weekly):
            return 7
        case .intervalPreset(.biweekly):
            return 14
        case let .intervalDays(days):
            return days
        case .weekly, .intervalPreset(.weekdays), .intervalPreset(.weekends):
            return nil
        }
    }

    var customIntervalDays: Int? {
        guard case let .intervalDays(days) = self else { return nil }
        return days
    }

    var storageWeekdayMask: Int {
        switch self {
        case let .weekly(days):
            return days.rawValue
        case let .intervalPreset(preset):
            return preset.storageWeekdayMask
        case .intervalDays:
            return 0
        }
    }

    var storageIntervalDays: Int {
        switch self {
        case .weekly:
            return Self.defaultIntervalDays
        case let .intervalPreset(preset):
            return preset.storageIntervalDays
        case let .intervalDays(days):
            return days
        }
    }

    var isValidSelection: Bool {
        switch self {
        case let .weekly(days):
            return days.rawValue != 0
        case .intervalPreset:
            return true
        case let .intervalDays(days):
            return Self.intervalDaysRange.contains(days)
        }
    }

    var summary: String {
        switch self {
        case let .weekly(days):
            return days.summaryOrPlaceholder
        case let .intervalPreset(preset):
            return preset.title
        case let .intervalDays(days):
            return intervalSummary(for: days)
        }
    }

    var compactSummary: String {
        switch self {
        case let .weekly(days):
            return days.compactSummaryOrPlaceholder
        case let .intervalPreset(preset):
            return preset.title
        case let .intervalDays(days):
            return intervalSummary(for: days)
        }
    }

    func isScheduled(on day: Date, anchorDate: Date, calendar: Calendar) -> Bool {
        let normalizedDay = calendar.startOfDay(for: day)
        let normalizedAnchor = calendar.startOfDay(for: anchorDate)
        guard normalizedDay >= normalizedAnchor else { return false }

        switch self {
        case let .weekly(days):
            return days.contains(calendar.weekdaySet(for: normalizedDay))
        case let .intervalPreset(preset):
            switch preset {
            case .daily:
                return true
            case .weekdays:
                return WeekdaySet.weekdays.contains(calendar.weekdaySet(for: normalizedDay))
            case .weekends:
                return WeekdaySet.weekends.contains(calendar.weekdaySet(for: normalizedDay))
            case .weekly:
                return isIntervalScheduled(days: 7, from: normalizedAnchor, to: normalizedDay, calendar: calendar)
            case .biweekly:
                return isIntervalScheduled(days: 14, from: normalizedAnchor, to: normalizedDay, calendar: calendar)
            }
        case let .intervalDays(days):
            guard Self.intervalDaysRange.contains(days) else { return false }
            return isIntervalScheduled(days: days, from: normalizedAnchor, to: normalizedDay, calendar: calendar)
        }
    }

    nonisolated static func make(kindRaw: String?, weekdayMask: Int, intervalDays: Int) -> ScheduleRule? {
        let kind = kindRaw.flatMap(Kind.init(rawValue:)) ?? .weekly
        switch kind {
        case .weekly:
            guard isValidWeekdayMask(weekdayMask) else { return nil }
            return .weekly(WeekdaySet(rawValue: weekdayMask))
        case .daily:
            return .intervalPreset(.daily)
        case .weekdays:
            return .intervalPreset(.weekdays)
        case .weekends:
            return .intervalPreset(.weekends)
        case .weeklyInterval:
            return .intervalPreset(.weekly)
        case .biweekly:
            return .intervalPreset(.biweekly)
        case .intervalDays:
            if intervalDays == 1 {
                return .intervalPreset(.daily)
            }
            guard intervalDaysRange.contains(intervalDays) else { return nil }
            return .intervalDays(intervalDays)
        }
    }

    nonisolated private static func isValidWeekdayMask(_ rawValue: Int) -> Bool {
        rawValue >= 0 && (rawValue & ~validWeekdayMask) == 0
    }

    private func intervalSummary(for days: Int) -> String {
        "Every \(days) days"
    }

    private func isIntervalScheduled(days: Int, from normalizedAnchor: Date, to normalizedDay: Date, calendar: Calendar) -> Bool {
        let dayDifference = calendar.dateComponents([.day], from: normalizedAnchor, to: normalizedDay).day ?? 0
        return dayDifference % days == 0
    }
}

struct Habit: Identifiable, Equatable {
    let id: UUID
    let type: HabitType
    let name: String
    let sortOrder: Int
    let startDate: Date
    let historyMode: HabitHistoryMode
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

struct HabitCompletion: Identifiable, Equatable {
    let id: UUID
    let habitID: UUID
    let localDate: Date
    let source: CompletionSource
    let createdAt: Date
}

struct HabitScheduleVersion: Identifiable, Equatable {
    let id: UUID
    let habitID: UUID
    let rule: ScheduleRule
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int

    init(
        id: UUID,
        habitID: UUID,
        weekdays: WeekdaySet,
        effectiveFrom: Date,
        createdAt: Date,
        version: Int
    ) {
        self.init(
            id: id,
            habitID: habitID,
            rule: .weekly(weekdays),
            effectiveFrom: effectiveFrom,
            createdAt: createdAt,
            version: version
        )
    }

    init(
        id: UUID,
        habitID: UUID,
        rule: ScheduleRule,
        effectiveFrom: Date,
        createdAt: Date,
        version: Int
    ) {
        self.id = id
        self.habitID = habitID
        self.rule = rule
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
        self.version = version
    }

    var weekdays: WeekdaySet {
        rule.weeklyDays ?? .daily
    }
}

struct HabitCardProjection: Identifiable, Equatable, Hashable {
    let id: UUID
    let type: HabitType
    let name: String
    let scheduleSummary: String
    let currentStreak: Int
    let reminderText: String?
    let reminderHour: Int?
    let reminderMinute: Int?
    let isReminderScheduledToday: Bool
    let isCompletedToday: Bool
    let isSkippedToday: Bool
    var needsHistoryReview = false
    var activeOverdueDay: Date?
    let sortOrder: Int
}

struct HabitSectionProjection: Identifiable, Equatable {
    let id: HabitType
    let title: String
    let habits: [HabitCardProjection]
}

struct DashboardProjection: Equatable {
    let sections: [HabitSectionProjection]

    static let empty = DashboardProjection(sections: [])
}

struct CreateHabitDraft: Equatable {
    var type: HabitType = .build
    var name = ""
    var startDate: Date = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    var scheduleRule: ScheduleRule = .weekly(.daily)
    var useScheduleForHistory = true
    var reminderEnabled = false
    var reminderTime = ReminderTime.default()

    var scheduleDays: WeekdaySet {
        get { scheduleRule.weeklyDays ?? .daily }
        set { scheduleRule = .weekly(newValue) }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct EditHabitDraft: Equatable {
    let id: UUID
    let type: HabitType
    let startDate: Date
    var name: String
    var scheduleRule: ScheduleRule
    var reminderEnabled: Bool
    var reminderTime: ReminderTime
    var completedDays: Set<Date>
    var skippedDays: Set<Date>

    init(
        id: UUID,
        type: HabitType,
        startDate: Date,
        name: String,
        scheduleDays: WeekdaySet,
        reminderEnabled: Bool,
        reminderTime: ReminderTime,
        completedDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.name = name
        self.scheduleRule = .weekly(scheduleDays)
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.completedDays = completedDays
        self.skippedDays = skippedDays
    }

    init(
        id: UUID,
        type: HabitType,
        startDate: Date,
        name: String,
        scheduleRule: ScheduleRule,
        reminderEnabled: Bool,
        reminderTime: ReminderTime,
        completedDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.name = name
        self.scheduleRule = scheduleRule
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.completedDays = completedDays
        self.skippedDays = skippedDays
    }

    var scheduleDays: WeekdaySet {
        get { scheduleRule.weeklyDays ?? .daily }
        set { scheduleRule = .weekly(newValue) }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HabitDetailsProjection: Equatable {
    let id: UUID
    let type: HabitType
    let name: String
    let startDate: Date
    let historyMode: HabitHistoryMode
    let scheduleSummary: String
    let scheduleDays: WeekdaySet
    let scheduleRule: ScheduleRule
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let currentStreak: Int
    let longestStreak: Int
    let totalCompletedDays: Int
    let completedDays: Set<Date>
    let skippedDays: Set<Date>
    var needsHistoryReview = false
    var requiredPastScheduledDays: Set<Date> = []
    var activeOverdueDay: Date?

    var heatmapDays: [Date] {
        completedDays.sorted()
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    static let storageKey = "appearance_mode"

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    static func stored(rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? .system
    }
}
