import Foundation

extension Notification.Name {
    static let eventBadgeBecameDue = Notification.Name("eventBadgeBecameDue")
}

enum EventBadgeSupport {
    static func count(_ events: [EventCardProjection], now: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        events.filter {
            $0.acknowledgedAt == nil && EventDurationFormatter.isCountdownComplete($0, now: now, calendar: calendar)
        }.count
    }
}

// Persist civil dates independently of the time zone in which they were selected.
enum EventLocalDate {
    nonisolated static func legacyKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        key(for: CoreDataDateOnlyStorage.normalizedDay(fromStoredDate: date, calendar: calendar), calendar: calendar)
    }

    nonisolated static func key(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        let parts = civilCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    nonisolated static func date(for key: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        guard let date = civilCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              self.key(for: date, calendar: calendar) == key else { return nil }
        return civilCalendar.startOfDay(for: date)
    }
}
