import Foundation
import UIKit
import UserNotifications

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
        let overdueHabits = loadDashboardUseCase.execute()
            .sections
            .flatMap(\.habits)
            .filter { isOverdue($0, now: now) }
            .count

        let overduePills = pillRepository.fetchDashboardPills()
            .filter { isOverdue($0, now: now) }
            .count

        return overdueHabits + overduePills
    }

    private func isOverdue(_ habit: HabitCardProjection, now: Date) -> Bool {
        guard habit.isReminderScheduledToday else { return false }
        guard !habit.isCompletedToday else { return false }
        guard
            let reminderHour = habit.reminderHour,
            let reminderMinute = habit.reminderMinute
        else {
            return false
        }

        let today = calendar.startOfDay(for: now)
        guard let reminderDate = calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: today
        ) else {
            return false
        }

        return reminderDate <= now
    }

    private func isOverdue(_ pill: PillCardProjection, now: Date) -> Bool {
        guard pill.isReminderScheduledToday else { return false }
        guard !pill.isTakenToday else { return false }
        guard
            let reminderHour = pill.reminderHour,
            let reminderMinute = pill.reminderMinute
        else {
            return false
        }

        let today = calendar.startOfDay(for: now)
        guard let reminderDate = calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: today
        ) else {
            return false
        }

        return reminderDate <= now
    }
}
