import Foundation
import UIKit
import UserNotifications

protocol AppBadgeApplying {
    func setBadgeCount(_ badgeCount: Int)
}

struct SystemAppBadgeApplier: AppBadgeApplying {
    func setBadgeCount(_ badgeCount: Int) {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(badgeCount, withCompletionHandler: nil)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
    }
}

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
        habit.activeOverdueDay != nil
    }

    private static func isOverdue(_ pill: PillCardProjection, now: Date, calendar: Calendar) -> Bool {
        pill.activeOverdueDay != nil
    }

    private static func isOverdue(_ habit: HabitReminderConfiguration, at date: Date, calendar: Calendar) -> Bool {
        ScheduledOverdueState.activeOverdueDay(
            startDate: habit.startDate,
            schedules: effectiveHabitScheduleHistory(for: habit),
            reminderTime: habit.reminderEnabled ? habit.reminderTime : nil,
            positiveDays: habit.completedDays,
            skippedDays: habit.skippedDays,
            now: date,
            calendar: calendar
        ) != nil
    }

    private static func isOverdue(_ pill: PillReminderConfiguration, at date: Date, calendar: Calendar) -> Bool {
        ScheduledOverdueState.activeOverdueDay(
            startDate: pill.startDate,
            schedules: effectivePillScheduleHistory(for: pill),
            reminderTime: pill.reminderEnabled ? pill.reminderTime : nil,
            positiveDays: pill.takenDays,
            skippedDays: pill.skippedDays,
            now: date,
            calendar: calendar
        ) != nil
    }

    private static func effectiveHabitScheduleHistory(for habit: HabitReminderConfiguration) -> [HabitScheduleVersion] {
        guard habit.scheduleHistory.isEmpty else { return habit.scheduleHistory }
        return [
            HabitScheduleVersion(
                id: habit.id,
                habitID: habit.id,
                weekdays: habit.scheduleDays,
                effectiveFrom: habit.startDate,
                createdAt: habit.startDate,
                version: 1
            ),
        ]
    }

    private static func effectivePillScheduleHistory(for pill: PillReminderConfiguration) -> [PillScheduleVersion] {
        guard pill.scheduleHistory.isEmpty else { return pill.scheduleHistory }
        return [
            PillScheduleVersion(
                id: pill.id,
                pillID: pill.id,
                weekdays: pill.scheduleDays,
                effectiveFrom: pill.startDate,
                createdAt: pill.startDate,
                version: 1
            ),
        ]
    }

}

@MainActor
final class AppBadgeService {
    private let loadDashboardUseCase: LoadDashboardUseCase
    private let pillRepository: PillRepository
    private let calendar: Calendar
    private let clock: AppClock
    private let badgeApplier: AppBadgeApplying
    private var lastBadgeCount: Int?

    init(
        loadDashboardUseCase: LoadDashboardUseCase,
        pillRepository: PillRepository,
        calendar: Calendar = .autoupdatingCurrent,
        clock: AppClock? = nil,
        badgeApplier: AppBadgeApplying? = nil
    ) {
        let resolvedClock = clock ?? AppClock(calendar: calendar)
        self.loadDashboardUseCase = loadDashboardUseCase
        self.pillRepository = pillRepository
        self.calendar = resolvedClock.calendar
        self.clock = resolvedClock
        self.badgeApplier = badgeApplier ?? SystemAppBadgeApplier()
    }

    func refreshBadge(now: Date? = nil, forceApply: Bool = false) {
        let badgeCount: Int
        do {
            badgeCount = try overdueCount(now: now)
        } catch {
            ReliabilityLog.error("badge.refresh failed: \(error.localizedDescription)")
            return
        }

        applyBadgeCountIfNeeded(badgeCount, forceApply: forceApply)
    }

    func refreshBadge(
        habitDashboard: DashboardProjection,
        pillDashboard: PillDashboardProjection,
        now: Date? = nil,
        forceApply: Bool = false
    ) {
        let currentDate = now ?? clock.now()
        let badgeCount = ProjectedBadgeCountCalculator.overdueCount(
            now: currentDate,
            habits: habitDashboard.sections.flatMap(\.habits),
            pills: pillDashboard.pills,
            calendar: calendar
        )

        applyBadgeCountIfNeeded(badgeCount, forceApply: forceApply)
    }

    private func applyBadgeCountIfNeeded(_ badgeCount: Int, forceApply: Bool) {
        guard forceApply || lastBadgeCount != badgeCount else { return }
        lastBadgeCount = badgeCount
        badgeApplier.setBadgeCount(badgeCount)
    }

    func overdueCount(now: Date? = nil) throws -> Int {
        let currentDate = now ?? clock.now()
        let habits = try loadDashboardUseCase.execute()
            .sections
            .flatMap(\.habits)

        let pills = try pillRepository.fetchDashboardPills()

        return ProjectedBadgeCountCalculator.overdueCount(
            now: currentDate,
            habits: habits,
            pills: pills,
            calendar: calendar
        )
    }
}
