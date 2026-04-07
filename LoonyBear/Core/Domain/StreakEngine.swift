import Foundation

enum StreakEngine {
    static func currentStreak(
        completions: [HabitCompletion],
        schedules: [HabitScheduleVersion],
        today: Date,
        calendar: Calendar = .current
    ) -> Int {
        return metrics(
            completions: completions,
            schedules: schedules,
            today: today,
            calendar: calendar
        ).current
    }

    static func longestStreak(
        completions: [HabitCompletion],
        schedules: [HabitScheduleVersion],
        calendar: Calendar = .current
    ) -> Int {
        let latestCompletion = completions
            .map { calendar.startOfDay(for: $0.localDate) }
            .max() ?? calendar.startOfDay(for: Date())

        return metrics(
            completions: completions,
            schedules: schedules,
            today: latestCompletion,
            calendar: calendar
        ).longest
    }

    private static func metrics(
        completions: [HabitCompletion],
        schedules: [HabitScheduleVersion],
        today: Date,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        let completionDays = Set(completions.map { calendar.startOfDay(for: $0.localDate) })
        guard let earliestCompletion = completionDays.min() else {
            return (0, 0)
        }

        let normalizedSchedules = schedules.sorted {
            if $0.effectiveFrom != $1.effectiveFrom {
                return $0.effectiveFrom < $1.effectiveFrom
            }
            if $0.version != $1.version {
                return $0.version < $1.version
            }
            return $0.createdAt < $1.createdAt
        }
        let normalizedToday = calendar.startOfDay(for: today)
        let start = earliestRelevantDate(
            earliestCompletion: earliestCompletion,
            earliestScheduleEffectiveFrom: normalizedSchedules.first?.effectiveFrom,
            calendar: calendar
        )

        var cursor = start
        var running = 0
        var longest = 0
        var current = 0

        while cursor <= normalizedToday {
            let hasCompletion = completionDays.contains(cursor)
            let isScheduled = weekdays(on: cursor, from: normalizedSchedules, calendar: calendar)?
                .contains(cursor.weekdayMask(calendar: calendar)) ?? false

            if hasCompletion {
                running += 1
                longest = max(longest, running)
            } else if isScheduled && cursor < normalizedToday {
                // A missed scheduled day resets the streak at the start of the next local day,
                // so an uncompleted scheduled "today" doesn't zero out the current streak yet.
                running = 0
            }

            if cursor == normalizedToday {
                current = running
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }

            cursor = next
        }

        return (current, longest)
    }

    private static func earliestRelevantDate(
        earliestCompletion: Date,
        earliestScheduleEffectiveFrom: Date?,
        calendar: Calendar
    ) -> Date {
        guard let earliestScheduleEffectiveFrom else {
            return earliestCompletion
        }

        return min(
            calendar.startOfDay(for: earliestCompletion),
            calendar.startOfDay(for: earliestScheduleEffectiveFrom)
        )
    }

    private static func weekdays(
        on day: Date,
        from schedules: [HabitScheduleVersion],
        calendar: Calendar
    ) -> WeekdaySet? {
        let normalizedDay = calendar.startOfDay(for: day)

        return schedules.last {
            calendar.startOfDay(for: $0.effectiveFrom) <= normalizedDay
        }?.weekdays
    }
}

private extension Date {
    func weekdayMask(calendar: Calendar) -> WeekdaySet {
        switch calendar.component(.weekday, from: self) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }
}
