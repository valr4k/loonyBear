import Foundation
import UIKit
import UserNotifications

enum ProjectedBadgeCountCalculator {
    static func overdueHabitCount(
        now: Date,
        habits: [HabitCardProjection],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        habits.filter { isOverdue($0, now: now, calendar: calendar) }.count
    }

    static func overduePillCount(
        now: Date,
        pills: [PillCardProjection],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        pills.filter { isOverdue($0, now: now, calendar: calendar) }.count
    }

    static func overdueCount(
        now: Date,
        habits: [HabitCardProjection],
        pills: [PillCardProjection],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let overdueHabits = overdueHabitCount(now: now, habits: habits, calendar: calendar)
        let overduePills = overduePillCount(now: now, pills: pills, calendar: calendar)
        return overdueHabits + overduePills
    }

    static func projectedOverdueCount(
        at date: Date,
        habits: [HabitReminderConfiguration],
        pills: [PillReminderConfiguration],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let overdueHabits = habits.filter { isOverdue($0, at: date, calendar: calendar) }.count
        let overduePills = pills.filter { isOverdue($0, at: date, calendar: calendar) }.count
        return overdueHabits + overduePills
    }

    private static func isOverdue(_ habit: HabitCardProjection, now: Date, calendar: Calendar) -> Bool {
        guard habit.isReminderScheduledToday else { return false }
        guard !habit.isCompletedToday else { return false }
        guard !habit.isSkippedToday else { return false }
        guard
            let reminderHour = habit.reminderHour,
            let reminderMinute = habit.reminderMinute
        else {
            return false
        }

        return reminderDate(
            hour: reminderHour,
            minute: reminderMinute,
            on: now,
            calendar: calendar
        ).map { $0 <= now } ?? false
    }

    private static func isOverdue(_ pill: PillCardProjection, now: Date, calendar: Calendar) -> Bool {
        guard pill.isReminderScheduledToday else { return false }
        guard !pill.isTakenToday else { return false }
        guard !pill.isSkippedToday else { return false }
        guard
            let reminderHour = pill.reminderHour,
            let reminderMinute = pill.reminderMinute
        else {
            return false
        }

        return reminderDate(
            hour: reminderHour,
            minute: reminderMinute,
            on: now,
            calendar: calendar
        ).map { $0 <= now } ?? false
    }

    private static func isOverdue(_ habit: HabitReminderConfiguration, at date: Date, calendar: Calendar) -> Bool {
        guard habit.reminderEnabled, let reminderTime = habit.reminderTime else { return false }

        let localDay = calendar.startOfDay(for: date)
        let normalizedStartDate = calendar.startOfDay(for: habit.startDate)
        guard localDay >= normalizedStartDate else { return false }
        guard habit.scheduleDays.contains(scheduledWeekdaySet(for: localDay, calendar: calendar)) else { return false }
        guard !habit.completedDays.contains(localDay) else { return false }
        guard !habit.skippedDays.contains(localDay) else { return false }

        return reminderDate(
            hour: reminderTime.hour,
            minute: reminderTime.minute,
            on: date,
            calendar: calendar
        ).map { $0 <= date } ?? false
    }

    private static func isOverdue(_ pill: PillReminderConfiguration, at date: Date, calendar: Calendar) -> Bool {
        guard pill.reminderEnabled, let reminderTime = pill.reminderTime else { return false }

        let localDay = calendar.startOfDay(for: date)
        let normalizedStartDate = calendar.startOfDay(for: pill.startDate)
        guard localDay >= normalizedStartDate else { return false }
        guard pill.scheduleDays.contains(scheduledWeekdaySet(for: localDay, calendar: calendar)) else { return false }
        guard !pill.takenDays.contains(localDay) else { return false }
        guard !pill.skippedDays.contains(localDay) else { return false }

        return reminderDate(
            hour: reminderTime.hour,
            minute: reminderTime.minute,
            on: date,
            calendar: calendar
        ).map { $0 <= date } ?? false
    }

    private static func reminderDate(hour: Int, minute: Int, on date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        )
    }

    private static func scheduledWeekdaySet(for date: Date, calendar: Calendar) -> WeekdaySet {
        switch calendar.component(.weekday, from: date) {
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

@MainActor
final class AppBadgeService {
    private let loadDashboardUseCase: LoadDashboardUseCase
    private let pillRepository: PillRepository

    private var calendar: Calendar {
        .autoupdatingCurrent
    }

    init(loadDashboardUseCase: LoadDashboardUseCase, pillRepository: PillRepository) {
        self.loadDashboardUseCase = loadDashboardUseCase
        self.pillRepository = pillRepository
    }

    func refreshBadge(now: Date = Date()) {
        let badgeCount = overdueCount(now: now)

        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(badgeCount, withCompletionHandler: nil)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
    }

    func overdueCount(now: Date = Date()) -> Int {
        let habits = loadDashboardUseCase.execute()
            .sections
            .flatMap(\.habits)

        let pills = pillRepository.fetchDashboardPills()

        return ProjectedBadgeCountCalculator.overdueCount(
            now: now,
            habits: habits,
            pills: pills,
            calendar: calendar
        )
    }
}
