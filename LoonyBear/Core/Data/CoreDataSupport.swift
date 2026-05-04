import CoreData
import Foundation

struct CoreDataRepositoryContext {
    let readContext: NSManagedObjectContext
    let makeWriteContext: () -> NSManagedObjectContext

    func performWrite(_ work: (NSManagedObjectContext) throws -> Void) throws {
        let context = makeWriteContext()
        var thrownError: Error?

        context.performAndWait {
            do {
                try work(context)
            } catch {
                context.rollback()
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }

        refreshReadContext()
    }

    func performWrite<T>(_ work: (NSManagedObjectContext) throws -> T, missingResultError: Error) throws -> T {
        let context = makeWriteContext()
        var result: T?
        var thrownError: Error?

        context.performAndWait {
            do {
                result = try work(context)
            } catch {
                context.rollback()
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }

        refreshReadContext()

        guard let result else {
            throw missingResultError
        }

        return result
    }

    func refreshReadContext() {
        if readContext.concurrencyType == .mainQueueConcurrencyType, Thread.isMainThread {
            readContext.refreshAllObjects()
            return
        }

        readContext.performAndWait {
            readContext.refreshAllObjects()
        }
    }
}

enum EditableHistoryWindow {
    static func dates(
        startDate: Date,
        today: Date = Date(),
        maxDays: Int = 30,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedToday = calendar.startOfDay(for: today)
        let oldestAllowedDate = calendar.date(byAdding: .day, value: -(maxDays - 1), to: normalizedToday) ?? normalizedStartDate
        let editableStart = max(normalizedStartDate, oldestAllowedDate)

        let dates = (0..<maxDays).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: normalizedToday)
                .map { calendar.startOfDay(for: $0) }
        }

        return Set(dates.filter { $0 >= editableStart && $0 <= normalizedToday })
    }

    static func pastDates(
        startDate: Date,
        today: Date = Date(),
        maxDays: Int = 30,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let normalizedToday = calendar.startOfDay(for: today)
        return dates(
            startDate: startDate,
            today: normalizedToday,
            maxDays: maxDays,
            calendar: calendar
        ).filter { $0 < normalizedToday }
    }
}

enum ActiveCycleStartDate {
    static func value(
        for object: NSManagedObject,
        fallbackStartDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let normalizedStartDate = calendar.startOfDay(for: fallbackStartDate)
        guard let activeFrom = object.dateValue(forKey: "activeFrom") else {
            return normalizedStartDate
        }
        return max(normalizedStartDate, calendar.startOfDay(for: activeFrom))
    }
}

enum HistoryMonthWindow {
    static func monthStart(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    static func months(
        containing dates: Set<Date>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let months = Set(
            dates.compactMap { date in
                monthStart(containing: date, calendar: calendar)
            }
        )
        return months.sorted()
    }

    static func months(
        from startDate: Date,
        through endDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        guard normalizedStart <= normalizedEnd else { return [] }

        var months: [Date] = []
        var cursor = monthStart(containing: normalizedStart, calendar: calendar)
        let lastMonth = monthStart(containing: normalizedEnd, calendar: calendar)

        while cursor <= lastMonth {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return months
    }

    static func endOfMonth(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let monthStart = monthStart(containing: date, calendar: calendar)
        guard
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth)
        else {
            return calendar.startOfDay(for: date)
        }
        return calendar.startOfDay(for: lastDay)
    }

    static func endOfSecondNextMonth(
        from today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let currentMonthStart = monthStart(containing: today, calendar: calendar)
        guard
            let monthAfterSecondNext = calendar.date(byAdding: .month, value: 3, to: currentMonthStart),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: monthAfterSecondNext)
        else {
            return calendar.startOfDay(for: today)
        }
        return calendar.startOfDay(for: lastDay)
    }

    static func displayMonth(
        startDate: Date,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedToday = calendar.startOfDay(for: today)
        let displayDate = normalizedStartDate > normalizedToday ? normalizedStartDate : normalizedToday
        return monthStart(containing: displayDate, calendar: calendar)
    }

    static func detailsCalendarEndDate(
        startDate: Date,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedToday = calendar.startOfDay(for: today)
        let displayDate = normalizedStartDate > normalizedToday ? normalizedStartDate : normalizedToday
        return endOfMonth(containing: displayDate, calendar: calendar)
    }
}

enum StartDateSelectionWindow {
    static func range(
        offset: DateComponents,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> ClosedRange<Date> {
        let normalizedToday = calendar.startOfDay(for: today)
        let earliest = calendar.date(byAdding: offset, to: normalizedToday) ?? normalizedToday
        let latest = HistoryMonthWindow.endOfSecondNextMonth(from: normalizedToday, calendar: calendar)
        return earliest ... latest
    }
}

struct ScheduleEffectiveFromResolution: Equatable {
    let selectedDate: Date
    let resolvedDate: Date

    var wasAdjusted: Bool {
        selectedDate != resolvedDate
    }
}

enum ScheduleEffectiveFromResolver {
    static func resolve(
        scheduleRule _: ScheduleRule,
        selectedDate: Date,
        explicitDays _: Set<Date>,
        minimumDate: Date,
        maximumDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduleEffectiveFromResolution? {
        let normalizedMinimum = calendar.startOfDay(for: minimumDate)
        let normalizedMaximum = calendar.startOfDay(for: maximumDate)
        guard normalizedMinimum <= normalizedMaximum else { return nil }

        let normalizedSelected = max(calendar.startOfDay(for: selectedDate), normalizedMinimum)
        guard normalizedSelected <= normalizedMaximum else { return nil }
        return ScheduleEffectiveFromResolution(
            selectedDate: normalizedSelected,
            resolvedDate: normalizedSelected
        )
    }
}

enum EditableHistorySelection: Equatable {
    case none
    case positive
    case skipped
}

enum EditableHistoryStateMachine {
    static func nextSelection(
        current: EditableHistorySelection,
        for day: Date,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> EditableHistorySelection {
        let normalizedDay = calendar.startOfDay(for: day)
        let normalizedToday = calendar.startOfDay(for: today)

        if normalizedDay == normalizedToday {
            switch current {
            case .none:
                return .positive
            case .positive:
                return .skipped
            case .skipped:
                return .none
            }
        }

        switch current {
        case .positive:
            return .skipped
        case .skipped:
            return .positive
        case .none:
            return .positive
        }
    }
}

enum EditableHistoryContract {
    static func normalizedSelection(
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        requiredFinalizedDays: Set<Date>,
        pastDefaultSelection: EditableHistorySelection = .skipped,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> (positiveDays: Set<Date>, skippedDays: Set<Date>) {
        let normalizedToday = calendar.startOfDay(for: today)
        let normalizedRequiredFinalizedDays = Set(requiredFinalizedDays.map { calendar.startOfDay(for: $0) })
        var normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        var normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })

        let pastPositiveDays = normalizedPositiveDays.intersection(normalizedRequiredFinalizedDays)
        let missingPastStates = normalizedRequiredFinalizedDays
            .filter { $0 < normalizedToday }
            .subtracting(pastPositiveDays)
            .subtracting(normalizedSkippedDays)

        switch pastDefaultSelection {
        case .positive:
            normalizedPositiveDays.formUnion(missingPastStates)
        case .skipped:
            normalizedSkippedDays.formUnion(missingPastStates)
        case .none:
            break
        }
        normalizedSkippedDays.subtract(normalizedPositiveDays)

        return (normalizedPositiveDays, normalizedSkippedDays)
    }
}

enum EditableHistoryValidationError: LocalizedError, Equatable {
    case missingHabitPastDays([Date])
    case missingPillPastDays([Date])

    var errorDescription: String? {
        switch self {
        case .missingHabitPastDays:
            return Self.message(actionLabel: "Completed")
        case .missingPillPastDays:
            return Self.message(actionLabel: "Taken")
        }
    }

    private static func message(actionLabel: String) -> String {
        "Mark all past days as \(actionLabel) or Skipped."
    }
}

enum EditableHistoryValidation {
    static func missingPastDays(
        editableDays: Set<Date>,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let normalizedToday = calendar.startOfDay(for: today)
        let normalizedEditablePastDays = Set(
            editableDays
                .map { calendar.startOfDay(for: $0) }
                .filter { $0 < normalizedToday }
        )
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })

        return normalizedEditablePastDays
            .subtracting(normalizedPositiveDays)
            .subtracting(normalizedSkippedDays)
            .sorted()
    }
}

protocol HistoryScheduleVersionLike {
    nonisolated var rule: ScheduleRule { get }
    nonisolated var effectiveFrom: Date { get }
    nonisolated var createdAt: Date { get }
    nonisolated var version: Int { get }
}

extension HabitScheduleVersion: HistoryScheduleVersionLike {}
extension PillScheduleVersion: HistoryScheduleVersionLike {}

struct SchedulePreviewVersion: HistoryScheduleVersionLike {
    let rule: ScheduleRule
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int
}

enum SchedulePreviewSupport {
    static func scheduledDays<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        through endDate: Date,
        schedules: [Schedule],
        replacementRule: ScheduleRule,
        effectiveFrom: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let previewSchedules = previewSchedules(
            from: schedules,
            replacementRule: replacementRule,
            effectiveFrom: effectiveFrom,
            calendar: calendar
        )
        return HistoryScheduleApplicability.scheduledDays(
            startDate: startDate,
            through: endDate,
            schedules: previewSchedules,
            calendar: calendar
        )
    }

    static func previewSchedules<Schedule: HistoryScheduleVersionLike>(
        from schedules: [Schedule],
        replacementRule: ScheduleRule,
        effectiveFrom: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SchedulePreviewVersion] {
        let normalizedEffectiveFrom = calendar.startOfDay(for: effectiveFrom)
        var previewSchedules = schedules.compactMap { schedule -> SchedulePreviewVersion? in
            let scheduleEffectiveFrom = calendar.startOfDay(for: schedule.effectiveFrom)
            guard scheduleEffectiveFrom < normalizedEffectiveFrom else { return nil }
            return SchedulePreviewVersion(
                rule: schedule.rule,
                effectiveFrom: scheduleEffectiveFrom,
                createdAt: schedule.createdAt,
                version: schedule.version
            )
        }
        previewSchedules.append(
            SchedulePreviewVersion(
                rule: replacementRule,
                effectiveFrom: normalizedEffectiveFrom,
                createdAt: .distantFuture,
                version: Int.max
            )
        )
        return previewSchedules
    }
}

enum DashboardScheduleSummary {
    static func text<Schedule: HistoryScheduleVersionLike>(
        latestSchedule: Schedule?,
        startDate: Date,
        endDate: Date?,
        schedules: [Schedule],
        today: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        guard let latestSchedule else {
            return "No days selected"
        }

        if case .intervalDays = latestSchedule.rule,
           let intervalPreview = nextIntervalPreview(
                latestSchedule: latestSchedule,
                startDate: startDate,
                endDate: endDate,
                schedules: schedules,
                today: today,
                calendar: calendar
           ) {
            return intervalPreview
        }

        return latestSchedule.rule.summary
    }

    private static func nextIntervalPreview<Schedule: HistoryScheduleVersionLike>(
        latestSchedule: Schedule,
        startDate: Date,
        endDate: Date?,
        schedules: [Schedule],
        today: Date,
        calendar: Calendar
    ) -> String? {
        guard latestSchedule.rule.isValidSelection else { return nil }

        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedToday = calendar.startOfDay(for: today)
        let normalizedEffectiveFrom = calendar.startOfDay(for: latestSchedule.effectiveFrom)
        var cursor = max(max(normalizedToday, normalizedStartDate), normalizedEffectiveFrom)
        let searchLimit = endDate
            .map { calendar.startOfDay(for: $0) }
            ?? (calendar.date(byAdding: .day, value: 30, to: cursor) ?? cursor)
        guard cursor <= searchLimit else { return nil }

        var labels: [String] = []
        while cursor <= searchLimit, labels.count < 3 {
            if HistoryScheduleApplicability.isScheduled(
                on: cursor,
                startDate: startDate,
                endDate: endDate,
                from: schedules,
                calendar: calendar
            ) {
                labels.append(weekdayLabel(for: cursor, calendar: calendar))
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: nextDay)
        }

        guard !labels.isEmpty else { return nil }
        return "Next: \(labels.joined(separator: ", "))"
    }

    private static func weekdayLabel(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.weekdaySet(for: date)
        return WeekdaySet.orderedDays.first { $0.1 == weekday }?.0 ?? "Sun"
    }
}

enum HistoryScheduleApplicability {
    static func pastEditableDays(
        in editableDays: Set<Date>,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let normalizedToday = calendar.startOfDay(for: today)
        return Set(editableDays.map { calendar.startOfDay(for: $0) }.filter { $0 < normalizedToday })
    }

    static func pastScheduledEditableDays<Schedule: HistoryScheduleVersionLike>(
        in editableDays: Set<Date>,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let pastEditableDays = pastEditableDays(in: editableDays, today: today, calendar: calendar)
        return Set(pastEditableDays.filter { day in
            isScheduled(on: day, startDate: startDate, endDate: endDate, from: schedules, calendar: calendar)
        })
    }

    static func scheduledDays<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        through endDate: Date,
        limitingTo scheduleEndDate: Date? = nil,
        schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedRequestedEndDate = calendar.startOfDay(for: endDate)
        let normalizedEndDate = scheduleEndDate
            .map { min(normalizedRequestedEndDate, calendar.startOfDay(for: $0)) }
            ?? normalizedRequestedEndDate
        guard normalizedStartDate <= normalizedEndDate else { return [] }

        var result: Set<Date> = []
        var cursor = normalizedStartDate

        while cursor <= normalizedEndDate {
            if isScheduled(on: cursor, startDate: startDate, endDate: scheduleEndDate, from: schedules, calendar: calendar) {
                result.insert(cursor)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    static func pastRequiredEditableDays<Schedule: HistoryScheduleVersionLike>(
        in editableDays: Set<Date>,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        historyMode: HabitHistoryMode,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        switch historyMode {
        case .scheduleBased:
            return pastScheduledEditableDays(
                in: editableDays,
                startDate: startDate,
                endDate: endDate,
                schedules: schedules,
                today: today,
                calendar: calendar
            )
        case .everyDay:
            return pastEditableDays(
                in: editableDays,
                today: today,
                calendar: calendar
            )
        }
    }

    static func isScheduled<Schedule: HistoryScheduleVersionLike>(
        on day: Date,
        startDate: Date,
        endDate: Date? = nil,
        from schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let normalizedDay = calendar.startOfDay(for: day)
        guard normalizedDay >= calendar.startOfDay(for: startDate) else {
            return false
        }
        if let endDate, normalizedDay > calendar.startOfDay(for: endDate) {
            return false
        }

        guard let schedule = effectiveSchedule(on: day, from: schedules, calendar: calendar) else {
            return false
        }
        return schedule.rule.isScheduled(on: day, anchorDate: schedule.effectiveFrom, calendar: calendar)
    }

    static func effectiveRule<Schedule: HistoryScheduleVersionLike>(
        on day: Date,
        from schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduleRule? {
        effectiveSchedule(on: day, from: schedules, calendar: calendar)?.rule
    }

    static func effectiveSchedule<Schedule: HistoryScheduleVersionLike>(
        on day: Date,
        from schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Schedule? {
        let normalizedDay = calendar.startOfDay(for: day)
        return schedules
            .sorted { lhs, rhs in
                if lhs.effectiveFrom != rhs.effectiveFrom {
                    return lhs.effectiveFrom < rhs.effectiveFrom
                }
                if lhs.version != rhs.version {
                    return lhs.version < rhs.version
                }
                return lhs.createdAt < rhs.createdAt
            }
            .last { calendar.startOfDay(for: $0.effectiveFrom) <= normalizedDay }
    }
}

enum ScheduledOverdueState {
    static func activeOverdueDay<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let latestDueDay = latestScheduledDueDay(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            now: now,
            calendar: calendar
        ) else {
            return nil
        }

        let normalizedLatestDueDay = calendar.startOfDay(for: latestDueDay)
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })

        guard
            !normalizedPositiveDays.contains(normalizedLatestDueDay),
            !normalizedSkippedDays.contains(normalizedLatestDueDay)
        else {
            return nil
        }

        return normalizedLatestDueDay
    }

    static func actionableOverdueDay<Schedule: HistoryScheduleVersionLike>(
        anchorDay: Date?,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let anchorDay else { return nil }

        let normalizedAnchorDay = calendar.startOfDay(for: anchorDay)
        let dueDays = dueScheduledDays(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            positiveDays: positiveDays,
            skippedDays: skippedDays,
            now: now,
            calendar: calendar
        )

        return dueDays.contains(normalizedAnchorDay) ? normalizedAnchorDay : nil
    }

    static func dueScheduledDays<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        now: Date,
        calendar: Calendar
    ) -> [Date] {
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })

        return scheduledDueDays(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            now: now,
            calendar: calendar
        )
        .filter {
            !normalizedPositiveDays.contains($0) && !normalizedSkippedDays.contains($0)
        }
    }

    private static func scheduledDueDays<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        now: Date,
        calendar: Calendar
    ) -> [Date] {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedToday = calendar.startOfDay(for: now)
        let normalizedEndDate = endDate.map { calendar.startOfDay(for: $0) }
        let finalDueDay = normalizedEndDate.map { min(normalizedToday, $0) } ?? normalizedToday
        guard normalizedStartDate <= finalDueDay else { return [] }

        let normalizedSchedules = sortedSchedules(schedules)
        var dueDays: [Date] = []
        var cursor = normalizedStartDate

        while cursor <= finalDueDay {
            let dueDate = reminderTime.flatMap {
                calendar.date(
                    bySettingHour: $0.hour,
                    minute: $0.minute,
                    second: 0,
                    of: cursor
                )
            } ?? cursor

            if isScheduled(cursor, startDate: startDate, endDate: normalizedEndDate, schedules: normalizedSchedules, calendar: calendar),
               dueDate <= now {
                dueDays.append(cursor)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return dueDays
    }

    private static func latestScheduledDueDay<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedEndDate = endDate.map { calendar.startOfDay(for: $0) }
        var cursor = min(calendar.startOfDay(for: now), normalizedEndDate ?? calendar.startOfDay(for: now))
        guard normalizedStartDate <= cursor else { return nil }

        let normalizedSchedules = sortedSchedules(schedules)

        while cursor >= normalizedStartDate {
            let dueDate = reminderTime.flatMap {
                calendar.date(
                    bySettingHour: $0.hour,
                    minute: $0.minute,
                    second: 0,
                    of: cursor
                )
            } ?? cursor

            if dueDate <= now,
               isScheduled(cursor, startDate: startDate, endDate: normalizedEndDate, schedules: normalizedSchedules, calendar: calendar) {
                return cursor
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            let previousDay = calendar.startOfDay(for: previous)
            guard previousDay < cursor else { break }
            cursor = previousDay
        }

        return nil
    }

    private static func isScheduled<Schedule: HistoryScheduleVersionLike>(
        _ day: Date,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        calendar: Calendar
    ) -> Bool {
        let normalizedDay = calendar.startOfDay(for: day)
        guard normalizedDay >= calendar.startOfDay(for: startDate) else {
            return false
        }
        if let endDate, normalizedDay > calendar.startOfDay(for: endDate) {
            return false
        }

        guard let schedule = schedules.last(where: {
            calendar.startOfDay(for: $0.effectiveFrom) <= normalizedDay
        }) else {
            return false
        }
        return schedule.rule.isScheduled(on: normalizedDay, anchorDate: schedule.effectiveFrom, calendar: calendar)
    }

    private static func sortedSchedules<Schedule: HistoryScheduleVersionLike>(_ schedules: [Schedule]) -> [Schedule] {
        schedules.sorted { lhs, rhs in
            if lhs.effectiveFrom != rhs.effectiveFrom {
                return lhs.effectiveFrom < rhs.effectiveFrom
            }
            if lhs.version != rhs.version {
                return lhs.version < rhs.version
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

enum ScheduleLifecycleSupport {
    static func shouldAutoArchive<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date?,
        schedules: [Schedule],
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })
        let finalizedDays = normalizedPositiveDays.union(normalizedSkippedDays)

        if let endDate {
            guard let finalScheduledDay = lastScheduledDay(
                startDate: startDate,
                endDate: endDate,
                schedules: schedules,
                calendar: calendar
            ) else {
                return false
            }
            return finalizedDays.contains(finalScheduledDay)
        }

        guard
            let latestSchedule = schedules.sorted(by: { lhs, rhs in
                if lhs.effectiveFrom != rhs.effectiveFrom {
                    return lhs.effectiveFrom > rhs.effectiveFrom
                }
                if lhs.version != rhs.version {
                    return lhs.version > rhs.version
                }
                return lhs.createdAt > rhs.createdAt
            }).first,
            latestSchedule.rule == .oneTime
        else {
            return false
        }

        return finalizedDays.contains(calendar.startOfDay(for: latestSchedule.effectiveFrom))
    }

    static func lastScheduledDay<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date,
        schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        var cursor = calendar.startOfDay(for: endDate)
        guard normalizedStartDate <= cursor else { return nil }

        while cursor >= normalizedStartDate {
            if HistoryScheduleApplicability.isScheduled(
                on: cursor,
                startDate: normalizedStartDate,
                endDate: endDate,
                from: schedules,
                calendar: calendar
            ) {
                return cursor
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            let previousDay = calendar.startOfDay(for: previous)
            guard previousDay < cursor else { break }
            cursor = previousDay
        }

        return nil
    }
}

enum OverdueAnchorKind: String {
    case habit
    case pill
}

protocol OverdueAnchorStore {
    func anchorDay(for kind: OverdueAnchorKind, id: UUID, calendar: Calendar) -> Date?
    func setAnchorDay(_ day: Date, for kind: OverdueAnchorKind, id: UUID, calendar: Calendar)
    func clearAnchorDay(for kind: OverdueAnchorKind, id: UUID)
    func clearAllAnchors()
}

final class UserDefaultsOverdueAnchorStore: OverdueAnchorStore {
    static let shared = UserDefaultsOverdueAnchorStore()

    private let defaults: UserDefaults
    private let key = "overdue_anchor_days"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func anchorDay(for kind: OverdueAnchorKind, id: UUID, calendar: Calendar) -> Date? {
        guard let timestamp = values()[storageKey(for: kind, id: id)] else { return nil }
        return calendar.startOfDay(for: Date(timeIntervalSince1970: timestamp))
    }

    func setAnchorDay(_ day: Date, for kind: OverdueAnchorKind, id: UUID, calendar: Calendar) {
        var values = values()
        values[storageKey(for: kind, id: id)] = calendar.startOfDay(for: day).timeIntervalSince1970
        defaults.set(values, forKey: key)
    }

    func clearAnchorDay(for kind: OverdueAnchorKind, id: UUID) {
        var values = values()
        values.removeValue(forKey: storageKey(for: kind, id: id))
        defaults.set(values, forKey: key)
    }

    func clearAllAnchors() {
        defaults.removeObject(forKey: key)
    }

    private func values() -> [String: TimeInterval] {
        defaults.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
    }

    private func storageKey(for kind: OverdueAnchorKind, id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }
}

enum CoreDataScheduleSupport {
    static func latestScheduleObject(in relationship: NSMutableSet) -> NSManagedObject? {
        (relationship.allObjects as? [NSManagedObject])?
            .sorted { lhs, rhs in
                let lhsEffectiveFrom = lhs.dateValue(forKey: "effectiveFrom") ?? .distantPast
                let rhsEffectiveFrom = rhs.dateValue(forKey: "effectiveFrom") ?? .distantPast
                if lhsEffectiveFrom != rhsEffectiveFrom {
                    return lhsEffectiveFrom > rhsEffectiveFrom
                }

                let lhsVersion = lhs.int32Value(forKey: "version")
                let rhsVersion = rhs.int32Value(forKey: "version")
                if lhsVersion != rhsVersion {
                    return lhsVersion > rhsVersion
                }

                let lhsCreatedAt = lhs.dateValue(forKey: "createdAt") ?? .distantPast
                let rhsCreatedAt = rhs.dateValue(forKey: "createdAt") ?? .distantPast
                return lhsCreatedAt > rhsCreatedAt
            }
            .first
    }

    nonisolated static func isNewerSchedule<Schedule: HistoryScheduleVersionLike>(_ lhs: Schedule, _ rhs: Schedule) -> Bool {
        if lhs.effectiveFrom != rhs.effectiveFrom {
            return lhs.effectiveFrom > rhs.effectiveFrom
        }
        if lhs.version != rhs.version {
            return lhs.version > rhs.version
        }
        return lhs.createdAt > rhs.createdAt
    }

    static func apply(_ rule: ScheduleRule, to object: NSManagedObject) {
        object.setValue(rule.kind.rawValue, forKey: "scheduleKindRaw")
        object.setValue(Int16(rule.storageWeekdayMask), forKey: "weekdayMask")
        object.setValue(Int16(rule.storageIntervalDays), forKey: "intervalDays")
    }

    static func nextVersion(in relationship: NSMutableSet) -> Int32 {
        let rows = (relationship.allObjects as? [NSManagedObject]) ?? []
        let maxVersion = rows
            .map { $0.int32Value(forKey: "version", default: 1) }
            .max() ?? 0
        return maxVersion + 1
    }

    static func deleteScheduleObjects(
        in relationship: NSMutableSet,
        onOrAfter effectiveFrom: Date,
        calendar: Calendar,
        context: NSManagedObjectContext
    ) {
        let cutoff = calendar.startOfDay(for: effectiveFrom)
        let rows = (relationship.allObjects as? [NSManagedObject]) ?? []

        for row in rows {
            guard let rowEffectiveFrom = row.dateValue(forKey: "effectiveFrom") else { continue }
            if calendar.startOfDay(for: rowEffectiveFrom) >= cutoff {
                context.delete(row)
            }
        }
    }

    nonisolated static func rule(from object: NSManagedObject) -> ScheduleRule? {
        ScheduleRule.make(
            kindRaw: object.stringValue(forKey: "scheduleKindRaw"),
            weekdayMask: object.int16Value(forKey: "weekdayMask"),
            intervalDays: object.int16Value(forKey: "intervalDays", default: Int16(ScheduleRule.defaultIntervalDays)),
            effectiveFrom: object.dateValue(forKey: "effectiveFrom")
        )
    }
}

enum CoreDataHistorySupport {
    static func groupedHistoryObjectsByDay(
        _ objects: [NSManagedObject],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date: [NSManagedObject]] {
        Dictionary(grouping: objects.compactMap { object -> (Date, NSManagedObject)? in
            guard let localDate = object.dateValue(forKey: "localDate") else { return nil }
            return (calendar.startOfDay(for: localDate), object)
        }, by: \.0).mapValues { entries in
            entries.map(\.1)
        }
    }

    static func primaryHistoryObject(in objects: [NSManagedObject]) -> NSManagedObject? {
        objects.max { lhs, rhs in
            let lhsCreatedAt = lhs.dateValue(forKey: "createdAt") ?? .distantPast
            let rhsCreatedAt = rhs.dateValue(forKey: "createdAt") ?? .distantPast
            if lhsCreatedAt != rhsCreatedAt {
                return lhsCreatedAt < rhsCreatedAt
            }
            return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
        }
    }
}

enum CoreDataFetchSupport {
    static func fetchObject(
        entityName: String,
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchHistoryObject(
        entityName: String,
        ownerKey: String,
        ownerID: UUID,
        localDate: Date,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        try fetchHistoryObjects(
            entityName: entityName,
            ownerKey: ownerKey,
            ownerID: ownerID,
            localDate: localDate,
            in: context
        ).first
    }

    static func fetchHistoryObjects(
        entityName: String,
        ownerKey: String,
        ownerID: UUID,
        localDate: Date,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "\(ownerKey) == %@", ownerID as CVarArg),
            NSPredicate(format: "localDate == %@", localDate as CVarArg),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    static func fetchHistoryObjects(
        entityName: String,
        ownerKey: String,
        ownerID: UUID,
        localDates: Set<Date>,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        guard !localDates.isEmpty else { return [] }

        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "\(ownerKey) == %@", ownerID as CVarArg),
            NSPredicate(format: "localDate IN %@", Array(localDates)),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }
}

enum CoreDataRelationshipLoadingSupport {
    static func compactHistoryModels<Model, Source: RawRepresentable>(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        makeModel: (UUID, Date, Source, Date) -> Model
    ) -> [Model] where Source.RawValue == String {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        return rows.compactMap { row in
            guard
                let id = row.uuidValue(forKey: "id"),
                let localDate = row.dateValue(forKey: "localDate"),
                let sourceRaw = row.stringValue(forKey: "sourceRaw"),
                let source = Source(rawValue: sourceRaw),
                let createdAt = row.dateValue(forKey: "createdAt")
            else {
                return nil
            }

            return makeModel(id, localDate, source, createdAt)
        }
    }

    static func validatedHistoryModels<Model, Source: RawRepresentable>(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        area: String,
        invalidMessage: String,
        report: inout IntegrityReportBuilder,
        makeModel: (UUID, Date, Source, Date) -> Model
    ) -> [Model]? where Source.RawValue == String {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        var models: [Model] = []

        for row in rows {
            guard
                let id = row.uuidValue(forKey: "id"),
                let localDate = row.dateValue(forKey: "localDate"),
                let sourceRaw = row.stringValue(forKey: "sourceRaw"),
                let source = Source(rawValue: sourceRaw),
                let createdAt = row.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: area,
                    entityName: row.entityName,
                    object: row,
                    message: invalidMessage
                )
                return nil
            }

            models.append(makeModel(id, localDate, source, createdAt))
        }

        return models
    }

    static func compactScheduleModels<Model>(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        makeModel: (UUID, ScheduleRule, Date, Date, Int) -> Model
    ) -> [Model] {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        return rows.compactMap { row in
            guard
                let id = row.uuidValue(forKey: "id"),
                let effectiveFrom = row.dateValue(forKey: "effectiveFrom"),
                let createdAt = row.dateValue(forKey: "createdAt")
            else {
                return nil
            }

            guard let rule = CoreDataScheduleSupport.rule(from: row) else { return nil }

            return makeModel(id, rule, effectiveFrom, createdAt, Int(row.int32Value(forKey: "version", default: 1)))
        }
    }

    static func validatedScheduleModels<Model>(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        area: String,
        missingFieldsMessage: String,
        invalidMaskMessage: String,
        report: inout IntegrityReportBuilder,
        makeModel: (UUID, ScheduleRule, Date, Date, Int) -> Model
    ) -> [Model]? {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        var models: [Model] = []

        for row in rows {
            guard
                let id = row.uuidValue(forKey: "id"),
                let effectiveFrom = row.dateValue(forKey: "effectiveFrom"),
                let createdAt = row.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: area,
                    entityName: row.entityName,
                    object: row,
                    message: missingFieldsMessage
                )
                return nil
            }

            guard let rule = CoreDataScheduleSupport.rule(from: row) else {
                report.append(
                    area: area,
                    entityName: row.entityName,
                    object: row,
                    message: invalidMaskMessage
                )
                return nil
            }

            models.append(
                makeModel(
                    id,
                    rule,
                    effectiveFrom,
                    createdAt,
                    Int(row.int32Value(forKey: "version", default: 1))
                )
            )
        }

        return models
    }
}

extension NSManagedObject {
    var entityName: String {
        entity.name ?? "UnknownEntity"
    }

    nonisolated func uuidValue(forKey key: String) -> UUID? {
        value(forKey: key) as? UUID
    }

    nonisolated func stringValue(forKey key: String) -> String? {
        value(forKey: key) as? String
    }

    nonisolated func dateValue(forKey key: String) -> Date? {
        value(forKey: key) as? Date
    }

    nonisolated func boolValue(forKey key: String, default defaultValue: Bool = false) -> Bool {
        value(forKey: key) as? Bool ?? defaultValue
    }

    nonisolated func int16Value(forKey key: String) -> Int {
        Int(value(forKey: key) as? Int16 ?? 0)
    }

    nonisolated func int16Value(forKey key: String, default defaultValue: Int16) -> Int {
        Int(value(forKey: key) as? Int16 ?? defaultValue)
    }

    nonisolated func int32Value(forKey key: String, default defaultValue: Int32 = 0) -> Int32 {
        value(forKey: key) as? Int32 ?? defaultValue
    }
}

extension Calendar {
    nonisolated func weekdaySet(for date: Date) -> WeekdaySet {
        switch component(.weekday, from: date) {
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
