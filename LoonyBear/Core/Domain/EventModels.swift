import Foundation

enum EventMode: String, Codable, CaseIterable, Hashable {
    case countdown
    case countUp = "elapsed"

    var title: String {
        switch self {
        case .countdown:
            return "Countdown"
        case .countUp:
            return "Count Up"
        }
    }
}

struct EventCardProjection: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let mode: EventMode
    let date: Date
    let sortOrder: Int
}

struct EventDetailsProjection: Equatable {
    let id: UUID
    let name: String
    let mode: EventMode
    let date: Date
}

struct EventDashboardProjection: Equatable {
    let events: [EventCardProjection]

    static let empty = EventDashboardProjection(events: [])
}

struct EventDraft: Equatable {
    var name = ""
    var mode: EventMode
    var date: Date

    init(
        name: String = "",
        mode: EventMode = .countdown,
        date: Date = EventDateDefaults.countdownDate()
    ) {
        self.name = name
        self.mode = mode
        self.date = date
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct EditEventDraft: Equatable {
    let id: UUID
    var name: String
    var mode: EventMode
    var date: Date

    init(details: EventDetailsProjection) {
        id = details.id
        name = details.name
        mode = details.mode
        date = details.date
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum EventDateDefaults {
    static func countdownDate(
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.startOfDay(for: today)
    }

    static func countUpDate(
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.startOfDay(for: today)
    }
}

enum EventValidation {
    static func isDateValid(
        mode: EventMode,
        date: Date,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let normalizedDate = calendar.startOfDay(for: date)
        let normalizedToday = calendar.startOfDay(for: today)

        switch mode {
        case .countdown:
            return normalizedDate >= normalizedToday
        case .countUp:
            return normalizedDate <= normalizedToday
        }
    }

    static func validationMessage(
        mode: EventMode,
        date: Date,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard !isDateValid(mode: mode, date: date, today: today, calendar: calendar) else {
            return nil
        }

        switch mode {
        case .countdown:
            return AppCopy.countdownDateMustBeFuture
        case .countUp:
            return AppCopy.countUpDateMustBePast
        }
    }
}

enum EventDurationFormatter {
    static func text(
        for event: EventCardProjection,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        switch event.mode {
        case .countdown:
            return "\(countdownDayCount(for: event, now: now, calendar: calendar))d"
        case .countUp:
            return countUpText(from: event.date, to: now, calendar: calendar)
        }
    }

    static func isCountdownComplete(
        _ event: EventCardProjection,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard event.mode == .countdown else { return false }
        let today = calendar.startOfDay(for: now)
        let eventDate = calendar.startOfDay(for: event.date)
        return eventDate <= today
    }

    private static func countdownDayCount(
        for event: EventCardProjection,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let eventDate = calendar.startOfDay(for: event.date)
        let rawDays = calendar.dateComponents([.day], from: today, to: eventDate).day ?? 0
        return max(0, rawDays)
    }

    private static func countUpText(
        from date: Date,
        to now: Date,
        calendar: Calendar
    ) -> String {
        let eventDate = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard eventDate < today else { return "0d" }

        let components = calendar.dateComponents([.year, .month, .day], from: eventDate, to: today)
        let years = max(0, components.year ?? 0)
        let months = max(0, components.month ?? 0)
        let days = max(0, components.day ?? 0)

        if years > 0 {
            return "\(years)yr \(months)mo \(days)d"
        }
        if months > 0 {
            return "\(months)mo \(days)d"
        }
        return "\(days)d"
    }

}
