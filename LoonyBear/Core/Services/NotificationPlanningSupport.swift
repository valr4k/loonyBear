import Foundation

struct HabitNotificationCandidate: Equatable {
    let habitID: UUID
    let habitName: String
    let localDate: Date
    let scheduledDateTime: Date
}

struct PillNotificationCandidate: Equatable {
    let pillID: UUID
    let pillName: String
    let dosage: String
    let localDate: Date
    let scheduledDateTime: Date
}

enum HabitNotificationDeliveryPlan: Equatable {
    case individual(HabitNotificationCandidate, projectedBadgeCount: Int)
    case aggregated([HabitNotificationCandidate], scheduledDateTime: Date, projectedBadgeCount: Int)
}

enum PillNotificationDeliveryPlan: Equatable {
    case individual(PillNotificationCandidate, projectedBadgeCount: Int)
    case aggregated([PillNotificationCandidate], scheduledDateTime: Date, projectedBadgeCount: Int)
}

enum ReminderPlanningSupport {
    static func habitCandidates(
        reminders: [HabitReminderConfiguration],
        now: Date,
        schedulingWindowDays: Int,
        calendar: Calendar
    ) -> [HabitNotificationCandidate] {
        let today = calendar.startOfDay(for: now)

        return reminders.flatMap { reminder -> [HabitNotificationCandidate] in
            guard reminder.reminderEnabled, let reminderTime = reminder.reminderTime else { return [] }
            let normalizedStartDate = calendar.startOfDay(for: reminder.startDate)

            return (0 ..< schedulingWindowDays).compactMap { offset in
                guard let localDay = calendar.date(byAdding: .day, value: offset, to: today) else {
                    return nil
                }

                let normalizedDay = calendar.startOfDay(for: localDay)
                guard normalizedDay >= normalizedStartDate else { return nil }
                guard isScheduled(normalizedDay, for: reminder, calendar: calendar) else { return nil }
                guard !reminder.completedDays.contains(normalizedDay) else { return nil }
                guard !reminder.skippedDays.contains(normalizedDay) else { return nil }
                guard let scheduledDateTime = calendar.date(
                    bySettingHour: reminderTime.hour,
                    minute: reminderTime.minute,
                    second: 0,
                    of: normalizedDay
                ) else {
                    return nil
                }
                guard scheduledDateTime > now else { return nil }

                return HabitNotificationCandidate(
                    habitID: reminder.id,
                    habitName: reminder.name,
                    localDate: normalizedDay,
                    scheduledDateTime: scheduledDateTime
                )
            }
        }
    }

    static func pillCandidates(
        reminders: [PillReminderConfiguration],
        now: Date,
        schedulingWindowDays: Int,
        calendar: Calendar
    ) -> [PillNotificationCandidate] {
        let today = calendar.startOfDay(for: now)

        return reminders.flatMap { reminder -> [PillNotificationCandidate] in
            guard reminder.reminderEnabled, let reminderTime = reminder.reminderTime else { return [] }
            let normalizedStartDate = calendar.startOfDay(for: reminder.startDate)

            return (0 ..< schedulingWindowDays).compactMap { offset in
                guard let localDay = calendar.date(byAdding: .day, value: offset, to: today) else {
                    return nil
                }

                let normalizedDay = calendar.startOfDay(for: localDay)
                guard normalizedDay >= normalizedStartDate else { return nil }
                guard isScheduled(normalizedDay, for: reminder, calendar: calendar) else { return nil }
                guard !reminder.takenDays.contains(normalizedDay) else { return nil }
                guard !reminder.skippedDays.contains(normalizedDay) else { return nil }
                guard let scheduledDateTime = calendar.date(
                    bySettingHour: reminderTime.hour,
                    minute: reminderTime.minute,
                    second: 0,
                    of: normalizedDay
                ) else {
                    return nil
                }
                guard scheduledDateTime > now else { return nil }

                return PillNotificationCandidate(
                    pillID: reminder.id,
                    pillName: reminder.name,
                    dosage: reminder.dosage,
                    localDate: normalizedDay,
                    scheduledDateTime: scheduledDateTime
                )
            }
        }
    }

    static func habitDeliveries(
        candidates: [HabitNotificationCandidate],
        habits: [HabitReminderConfiguration],
        pills: [PillReminderConfiguration],
        aggregationThreshold: Int,
        calendar: Calendar
    ) -> [HabitNotificationDeliveryPlan] {
        let groupedCandidates = Dictionary(grouping: candidates, by: \.scheduledDateTime)
        return groupedCandidates.keys.sorted().flatMap { scheduledDateTime -> [HabitNotificationDeliveryPlan] in
            let group = groupedCandidates[scheduledDateTime] ?? []
            guard !group.isEmpty else { return [] }

            let projectedBadgeCount = ProjectedBadgeCountCalculator.projectedOverdueCount(
                at: scheduledDateTime,
                habits: habits,
                pills: pills,
                calendar: calendar
            )

            if group.count < aggregationThreshold {
                return group.map { .individual($0, projectedBadgeCount: projectedBadgeCount) }
            }

            return [.aggregated(group, scheduledDateTime: scheduledDateTime, projectedBadgeCount: projectedBadgeCount)]
        }
    }

    static func pillDeliveries(
        candidates: [PillNotificationCandidate],
        habits: [HabitReminderConfiguration],
        pills: [PillReminderConfiguration],
        aggregationThreshold: Int,
        calendar: Calendar
    ) -> [PillNotificationDeliveryPlan] {
        let groupedCandidates = Dictionary(grouping: candidates, by: \.scheduledDateTime)
        return groupedCandidates.keys.sorted().flatMap { scheduledDateTime -> [PillNotificationDeliveryPlan] in
            let group = groupedCandidates[scheduledDateTime] ?? []
            guard !group.isEmpty else { return [] }

            let projectedBadgeCount = ProjectedBadgeCountCalculator.projectedOverdueCount(
                at: scheduledDateTime,
                habits: habits,
                pills: pills,
                calendar: calendar
            )

            if group.count < aggregationThreshold {
                return group.map { .individual($0, projectedBadgeCount: projectedBadgeCount) }
            }

            return [.aggregated(group, scheduledDateTime: scheduledDateTime, projectedBadgeCount: projectedBadgeCount)]
        }
    }

    private static func isScheduled(_ day: Date, for reminder: HabitReminderConfiguration, calendar: Calendar) -> Bool {
        guard !reminder.scheduleHistory.isEmpty else {
            return reminder.scheduleDays.contains(calendar.weekdaySet(for: day))
        }
        return HistoryScheduleApplicability.effectiveWeekdays(
            on: day,
            from: reminder.scheduleHistory,
            calendar: calendar
        )?.contains(calendar.weekdaySet(for: day)) ?? false
    }

    private static func isScheduled(_ day: Date, for reminder: PillReminderConfiguration, calendar: Calendar) -> Bool {
        guard !reminder.scheduleHistory.isEmpty else {
            return reminder.scheduleDays.contains(calendar.weekdaySet(for: day))
        }
        return HistoryScheduleApplicability.effectiveWeekdays(
            on: day,
            from: reminder.scheduleHistory,
            calendar: calendar
        )?.contains(calendar.weekdaySet(for: day)) ?? false
    }
}
