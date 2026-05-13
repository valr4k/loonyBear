import Foundation

enum StreakEngine {
    struct Seed: Equatable {
        let resumeDate: Date
        let running: Int
        let longest: Int
    }

    static func currentStreak(
        completions: [HabitCompletion],
        skippedCompletions: [HabitCompletion] = [],
        schedules: [HabitScheduleVersion],
        startDate: Date? = nil,
        today: Date,
        calendar: Calendar = .current
    ) -> Int {
        let completionDays = Set(completions.map { calendar.startOfDay(for: $0.localDate) })
        let skippedDays = Set(skippedCompletions.map { calendar.startOfDay(for: $0.localDate) })

        return metrics(
            earliestCompletionDate: completionDays.min(),
            containsCompletion: { completionDays.contains(calendar.startOfDay(for: $0)) },
            containsSkippedCompletion: { skippedDays.contains(calendar.startOfDay(for: $0)) },
            schedules: schedules,
            startDate: startDate,
            today: today,
            seed: nil,
            calendar: calendar
        ).current
    }

    static func longestStreak(
        completions: [HabitCompletion],
        schedules: [HabitScheduleVersion],
        startDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Int {
        let completionDays = Set(completions.map { calendar.startOfDay(for: $0.localDate) })
        let latestCompletion = completionDays.max() ?? calendar.startOfDay(for: Date())

        return metrics(
            earliestCompletionDate: completionDays.min(),
            containsCompletion: { completionDays.contains(calendar.startOfDay(for: $0)) },
            containsSkippedCompletion: { _ in false },
            schedules: schedules,
            startDate: startDate,
            today: latestCompletion,
            seed: nil,
            calendar: calendar
        ).longest
    }

    static func currentStreak<Schedule: HistoryScheduleVersionLike>(
        earliestCompletionDate: Date?,
        containsCompletion: (Date) -> Bool,
        containsSkippedCompletion: (Date) -> Bool = { _ in false },
        schedules: [Schedule],
        startDate: Date? = nil,
        today: Date,
        seed: Seed? = nil,
        calendar: Calendar = .current
    ) -> Int {
        metrics(
            earliestCompletionDate: earliestCompletionDate,
            containsCompletion: containsCompletion,
            containsSkippedCompletion: containsSkippedCompletion,
            schedules: schedules,
            startDate: startDate,
            today: today,
            seed: seed,
            calendar: calendar
        ).current
    }

    static func longestStreak<Schedule: HistoryScheduleVersionLike>(
        earliestCompletionDate: Date?,
        latestCompletionDate: Date?,
        containsCompletion: (Date) -> Bool,
        schedules: [Schedule],
        startDate: Date? = nil,
        seed: Seed? = nil,
        calendar: Calendar = .current
    ) -> Int {
        metrics(
            earliestCompletionDate: earliestCompletionDate,
            containsCompletion: containsCompletion,
            containsSkippedCompletion: { _ in false },
            schedules: schedules,
            startDate: startDate,
            today: latestCompletionDate ?? calendar.startOfDay(for: Date()),
            seed: seed,
            calendar: calendar
        ).longest
    }

    private static func metrics<Schedule: HistoryScheduleVersionLike>(
        earliestCompletionDate: Date?,
        containsCompletion: (Date) -> Bool,
        containsSkippedCompletion: (Date) -> Bool,
        schedules: [Schedule],
        startDate: Date?,
        today: Date,
        seed: Seed?,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        guard let earliestCompletion = earliestCompletionDate.map({ calendar.startOfDay(for: $0) }) else {
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

        if let seed {
            let seedResumeDate = calendar.startOfDay(for: seed.resumeDate)
            if seedResumeDate > cursor {
                cursor = seedResumeDate
                running = seed.running
                longest = max(longest, seed.longest)
            }
        }

        if cursor > normalizedToday {
            return (running, longest)
        }

        while cursor <= normalizedToday {
            let hasCompletion = containsCompletion(cursor)
            let hasSkip = containsSkippedCompletion(cursor)
            let activeSchedule = schedule(on: cursor, from: normalizedSchedules, calendar: calendar)
            let isScheduled = activeSchedule.map {
                $0.rule.isScheduled(on: cursor, anchorDate: $0.effectiveFrom, calendar: calendar)
            } ?? false

            if hasCompletion {
                running += 1
                longest = max(longest, running)
            } else if hasSkip && isScheduled && cursor == normalizedToday {
                // An explicit skip on a scheduled "today" should immediately zero the current streak.
                running = 0
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

    private static func schedule<Schedule: HistoryScheduleVersionLike>(
        on day: Date,
        from schedules: [Schedule],
        calendar: Calendar
    ) -> Schedule? {
        let normalizedDay = calendar.startOfDay(for: day)

        return schedules.last {
            calendar.startOfDay(for: $0.effectiveFrom) <= normalizedDay
        }
    }
}
