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

enum HabitSectionID: String, Hashable {
    case build
    case quit
    case archived

    init(type: HabitType) {
        switch type {
        case .build:
            self = .build
        case .quit:
            self = .quit
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

    nonisolated static let monday = WeekdaySet(rawValue: 1 << 0)
    nonisolated static let tuesday = WeekdaySet(rawValue: 1 << 1)
    nonisolated static let wednesday = WeekdaySet(rawValue: 1 << 2)
    nonisolated static let thursday = WeekdaySet(rawValue: 1 << 3)
    nonisolated static let friday = WeekdaySet(rawValue: 1 << 4)
    nonisolated static let saturday = WeekdaySet(rawValue: 1 << 5)
    nonisolated static let sunday = WeekdaySet(rawValue: 1 << 6)

    nonisolated static let weekdays: WeekdaySet = [.monday, .tuesday, .wednesday, .thursday, .friday]
    nonisolated static let weekends: WeekdaySet = [.saturday, .sunday]
    nonisolated static let daily: WeekdaySet = [.weekdays, .weekends]

    nonisolated static let orderedDays: [(String, WeekdaySet)] = [
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
            if let singleDayLabel {
                return "Weekly on \(singleDayLabel)"
            }
            return selectedDayLabels.joined(separator: ", ")
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
            if let singleDayLabel {
                return "Weekly on \(singleDayLabel)"
            }
            return selectedDayLabels.joined(separator: ", ")
        }
    }

    var summaryOrPlaceholder: String {
        rawValue == 0 ? "Select days" : summary
    }

    var compactSummaryOrPlaceholder: String {
        rawValue == 0 ? "Select days" : compactSummary
    }

    private var singleDayLabel: String? {
        guard rawValue.nonzeroBitCount == 1 else { return nil }
        return selectedDayLabels.first
    }

    private var selectedDayLabels: [String] {
        Self.orderedDays.compactMap { contains($0.1) ? $0.0 : nil }
    }
}

enum ScheduleRule: Equatable, Hashable {
    enum Kind: String, Codable {
        case weekly
        case daily
        case weekdays
        case weekends
        case intervalDays
        case oneTime
    }

    nonisolated static let defaultIntervalDays = 2
    nonisolated static let intervalDaysRange = 2 ... 5
    nonisolated private static let validWeekdayMask = WeekdaySet.daily.rawValue

    case weekly(WeekdaySet)
    case intervalDays(Int)
    case oneTime

    var kind: Kind {
        switch self {
        case .weekly:
            return .weekly
        case .intervalDays:
            return .intervalDays
        case .oneTime:
            return .oneTime
        }
    }

    var weeklyDays: WeekdaySet? {
        switch self {
        case let .weekly(days):
            return days
        case .intervalDays, .oneTime:
            return nil
        }
    }

    var intervalDays: Int? {
        switch self {
        case let .intervalDays(days):
            return days
        case .weekly, .oneTime:
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
        case .intervalDays, .oneTime:
            return 0
        }
    }

    var storageIntervalDays: Int {
        switch self {
        case .weekly, .oneTime:
            return Self.defaultIntervalDays
        case let .intervalDays(days):
            return days
        }
    }

    var isValidSelection: Bool {
        switch self {
        case let .weekly(days):
            return days.rawValue != 0
        case let .intervalDays(days):
            return Self.intervalDaysRange.contains(days)
        case .oneTime:
            return true
        }
    }

    var isOneTime: Bool {
        if case .oneTime = self {
            return true
        }
        return false
    }

    var summary: String {
        switch self {
        case let .weekly(days):
            return days.summaryOrPlaceholder
        case let .intervalDays(days):
            return intervalSummary(for: days)
        case .oneTime:
            return "Never repeat"
        }
    }

    var compactSummary: String {
        switch self {
        case let .weekly(days):
            return days.compactSummaryOrPlaceholder
        case let .intervalDays(days):
            return intervalSummary(for: days)
        case .oneTime:
            return "Never"
        }
    }

    func isScheduled(on day: Date, anchorDate: Date, calendar: Calendar) -> Bool {
        let normalizedDay = calendar.startOfDay(for: day)
        let normalizedAnchor = calendar.startOfDay(for: anchorDate)
        guard normalizedDay >= normalizedAnchor else { return false }

        switch self {
        case let .weekly(days):
            return days.contains(calendar.weekdaySet(for: normalizedDay))
        case let .intervalDays(days):
            guard Self.intervalDaysRange.contains(days) else { return false }
            return isIntervalScheduled(days: days, from: normalizedAnchor, to: normalizedDay, calendar: calendar)
        case .oneTime:
            return normalizedDay == normalizedAnchor
        }
    }

    nonisolated static func make(kindRaw: String?, weekdayMask: Int, intervalDays: Int) -> ScheduleRule? {
        let kind: Kind
        if let kindRaw {
            guard let parsedKind = Kind(rawValue: kindRaw) else { return nil }
            kind = parsedKind
        } else {
            kind = .weekly
        }

        switch kind {
        case .weekly:
            guard isValidWeekdayMask(weekdayMask) else { return nil }
            return .weekly(WeekdaySet(rawValue: weekdayMask))
        case .daily:
            return .weekly(.daily)
        case .weekdays:
            return .weekly(.weekdays)
        case .weekends:
            return .weekly(.weekends)
        case .intervalDays:
            if intervalDays == 1 {
                return .weekly(.daily)
            }
            guard intervalDaysRange.contains(intervalDays) else { return nil }
            return .intervalDays(intervalDays)
        case .oneTime:
            return .oneTime
        }
    }

    nonisolated static func make(
        kindRaw: String?,
        weekdayMask: Int,
        intervalDays: Int,
        effectiveFrom: Date?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduleRule? {
        if let currentRule = make(kindRaw: kindRaw, weekdayMask: weekdayMask, intervalDays: intervalDays) {
            return currentRule
        }

        guard let kindRaw else { return nil }
        switch kindRaw {
        case "weeklyInterval":
            if intervalDays == 1 {
                return .weekly(.daily)
            }
            guard intervalDays == 7, let effectiveFrom else {
                return nil
            }
            return .weekly(calendar.weekdaySet(for: effectiveFrom))
        case "biweekly":
            return nil
        default:
            return nil
        }
    }

    nonisolated private static func isValidWeekdayMask(_ rawValue: Int) -> Bool {
        rawValue >= 0 && (rawValue & ~validWeekdayMask) == 0
    }

    private func intervalSummary(for days: Int) -> String {
        return "Every \(days) days"
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
    let endDate: Date?
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
    var startsInFuture = false
    var futureStartDate: Date? = nil
    var isArchived = false
    let sortOrder: Int
}

struct HabitSectionProjection: Identifiable, Equatable {
    let id: HabitSectionID
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
    var endDate: Date?
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
    var endDate: Date?
    var name: String
    var scheduleRule: ScheduleRule
    var reminderEnabled: Bool
    var reminderTime: ReminderTime
    var completedDays: Set<Date>
    var skippedDays: Set<Date>
    var scheduleEffectiveFrom: Date?

    init(
        id: UUID,
        type: HabitType,
        startDate: Date,
        endDate: Date? = nil,
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
        self.endDate = endDate
        self.name = name
        self.scheduleRule = .weekly(scheduleDays)
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.completedDays = completedDays
        self.skippedDays = skippedDays
        scheduleEffectiveFrom = nil
    }

    init(
        id: UUID,
        type: HabitType,
        startDate: Date,
        endDate: Date? = nil,
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
        self.endDate = endDate
        self.name = name
        self.scheduleRule = scheduleRule
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.completedDays = completedDays
        self.skippedDays = skippedDays
        scheduleEffectiveFrom = nil
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
    let endDate: Date?
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
    let scheduleHistory: [HabitScheduleVersion]
    let scheduledDates: Set<Date>
    var needsHistoryReview = false
    var requiredPastScheduledDays: Set<Date> = []
    var activeOverdueDay: Date?
    var isArchived = false

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
