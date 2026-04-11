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
        return Calendar.current.date(from: components)?
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

    var summaryOrPlaceholder: String {
        rawValue == 0 ? "Select days" : summary
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
    let weekdays: WeekdaySet
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int
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
    var startDate: Date = Calendar.current.startOfDay(for: Date())
    var scheduleDays: WeekdaySet = .daily
    var useScheduleForHistory = true
    var reminderEnabled = false
    var reminderTime = ReminderTime.default()

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct EditHabitDraft: Equatable {
    let id: UUID
    let type: HabitType
    let startDate: Date
    var name: String
    var historyMode: HabitHistoryMode
    var scheduleDays: WeekdaySet
    var reminderEnabled: Bool
    var reminderTime: ReminderTime
    var completedDays: Set<Date>
    var skippedDays: Set<Date>

    init(
        id: UUID,
        type: HabitType,
        startDate: Date,
        name: String,
        historyMode: HabitHistoryMode = .scheduleBased,
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
        self.historyMode = historyMode
        self.scheduleDays = scheduleDays
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.completedDays = completedDays
        self.skippedDays = skippedDays
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
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let currentStreak: Int
    let longestStreak: Int
    let totalCompletedDays: Int
    let completedDays: Set<Date>
    let skippedDays: Set<Date>

    var heatmapDays: [Date] {
        completedDays.sorted()
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
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
}
