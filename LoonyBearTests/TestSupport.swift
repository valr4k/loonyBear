import Foundation

@testable import LoonyBear

enum TestSupport {
    static func makeDate(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func makeSchedule(
        habitID: UUID,
        weekdays: WeekdaySet,
        effectiveFrom: Date,
        version: Int
    ) -> HabitScheduleVersion {
        HabitScheduleVersion(
            id: UUID(),
            habitID: habitID,
            weekdays: weekdays,
            effectiveFrom: effectiveFrom,
            createdAt: effectiveFrom,
            version: version
        )
    }

    static func makeCompletion(
        habitID: UUID,
        localDate: Date,
        source: CompletionSource = .manualEdit
    ) -> HabitCompletion {
        HabitCompletion(
            id: UUID(),
            habitID: habitID,
            localDate: localDate,
            source: source,
            createdAt: localDate
        )
    }
}
