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
        in range: ClosedRange<Date>,
        startDate: Date,
        limitingTo scheduleEndDate: Date? = nil,
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
            in: range,
            startDate: startDate,
            limitingTo: scheduleEndDate,
            schedules: previewSchedules,
            calendar: calendar
        )
    }

    static func scheduledDays<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        through endDate: Date,
        limitingTo scheduleEndDate: Date? = nil,
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
            limitingTo: scheduleEndDate,
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

enum EndDateValidationFailureReason: Equatable {
    case dateInPast
    case noScheduledDay
}

enum EndDateValidationSupport {
    private static let searchWindowDays = 31

    static func isValid<Schedule: HistoryScheduleVersionLike>(
        endDate: Date?,
        startDate: Date,
        lowerBound: Date,
        schedules: [Schedule],
        ignoresEndDate: Bool = false,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard !ignoresEndDate else {
            return true
        }
        guard let endDate else {
            return true
        }

        let normalizedEndDate = calendar.startOfDay(for: endDate)
        let normalizedLowerBound = calendar.startOfDay(for: lowerBound)
        guard normalizedEndDate >= normalizedLowerBound else {
            return false
        }

        return hasScheduledDay(
            from: normalizedLowerBound,
            through: normalizedEndDate,
            startDate: startDate,
            schedules: schedules,
            calendar: calendar
        )
    }

    static func failureReason<Schedule: HistoryScheduleVersionLike>(
        endDate: Date?,
        startDate: Date,
        lowerBound: Date,
        schedules: [Schedule],
        ignoresEndDate: Bool = false,
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> EndDateValidationFailureReason? {
        guard !ignoresEndDate else {
            return nil
        }
        guard let endDate else {
            return nil
        }

        let normalizedEndDate = calendar.startOfDay(for: endDate)
        let normalizedToday = calendar.startOfDay(for: today)
        if normalizedEndDate < normalizedToday {
            return .dateInPast
        }

        let normalizedLowerBound = calendar.startOfDay(for: lowerBound)
        guard normalizedEndDate >= normalizedLowerBound else {
            return .noScheduledDay
        }

        return hasScheduledDay(
            from: normalizedLowerBound,
            through: normalizedEndDate,
            startDate: startDate,
            schedules: schedules,
            calendar: calendar
        ) ? nil : .noScheduledDay
    }

    static func hasScheduledDay<Schedule: HistoryScheduleVersionLike>(
        from lowerBound: Date,
        through endDate: Date,
        startDate: Date,
        schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        var cursor = calendar.startOfDay(for: lowerBound)
        let normalizedEndDate = calendar.startOfDay(for: endDate)
        let cappedEndDate = min(
            normalizedEndDate,
            calendar.date(byAdding: .day, value: searchWindowDays, to: cursor)
                .map { calendar.startOfDay(for: $0) } ?? normalizedEndDate
        )

        while cursor <= cappedEndDate {
            if HistoryScheduleApplicability.isScheduled(
                on: cursor,
                startDate: startDate,
                endDate: normalizedEndDate,
                from: schedules,
                calendar: calendar
            ) {
                return true
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return false
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
        in range: ClosedRange<Date>,
        startDate: Date,
        limitingTo scheduleEndDate: Date? = nil,
        schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        var rangeStart = max(calendar.startOfDay(for: range.lowerBound), normalizedStartDate)
        let requestedRangeEnd = calendar.startOfDay(for: range.upperBound)
        let normalizedEndDate = scheduleEndDate
            .map { min(requestedRangeEnd, calendar.startOfDay(for: $0)) }
            ?? requestedRangeEnd
        guard rangeStart <= normalizedEndDate else { return [] }

        var result: Set<Date> = []

        while rangeStart <= normalizedEndDate {
            if isScheduled(on: rangeStart, startDate: startDate, endDate: scheduleEndDate, from: schedules, calendar: calendar) {
                result.insert(rangeStart)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: rangeStart) else {
                break
            }
            rangeStart = calendar.startOfDay(for: next)
        }

        return result
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
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })
        return activeOverdueDay(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            hasPositiveState: { normalizedPositiveDays.contains($0) },
            hasSkippedState: { normalizedSkippedDays.contains($0) },
            now: now,
            calendar: calendar
        )
    }

    static func activeOverdueDay<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        hasPositiveState: (Date) -> Bool,
        hasSkippedState: (Date) -> Bool,
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

        guard
            !hasPositiveState(normalizedLatestDueDay),
            !hasSkippedState(normalizedLatestDueDay)
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
        return isDueScheduledDay(
            normalizedAnchorDay,
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            positiveDays: positiveDays,
            skippedDays: skippedDays,
            now: now,
            calendar: calendar
        ) ? normalizedAnchorDay : nil
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

    static func isDueScheduledDay<Schedule: HistoryScheduleVersionLike>(
        _ day: Date,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })

        return isDueScheduledDay(
            day,
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            hasPositiveState: { normalizedPositiveDays.contains($0) },
            hasSkippedState: { normalizedSkippedDays.contains($0) },
            now: now,
            calendar: calendar
        )
    }

    static func isDueScheduledDay<Schedule: HistoryScheduleVersionLike>(
        _ day: Date,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [Schedule],
        reminderTime: ReminderTime?,
        hasPositiveState: (Date) -> Bool,
        hasSkippedState: (Date) -> Bool,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let normalizedDay = calendar.startOfDay(for: day)
        guard
            HistoryScheduleApplicability.isScheduled(
                on: normalizedDay,
                startDate: startDate,
                endDate: endDate,
                from: schedules,
                calendar: calendar
            )
        else {
            return false
        }

        let dueDate = reminderTime.flatMap {
            calendar.date(
                bySettingHour: $0.hour,
                minute: $0.minute,
                second: 0,
                of: normalizedDay
            )
        } ?? normalizedDay

        return dueDate <= now
            && !hasPositiveState(normalizedDay)
            && !hasSkippedState(normalizedDay)
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
        let normalizedToday = calendar.startOfDay(for: now)
        var finalDueDay = min(normalizedToday, normalizedEndDate ?? normalizedToday)

        if finalDueDay == normalizedToday,
           let reminderTime,
           let todayDueDate = calendar.date(
               bySettingHour: reminderTime.hour,
               minute: reminderTime.minute,
               second: 0,
               of: normalizedToday
           ),
           todayDueDate > now
        {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: normalizedToday) else {
                return nil
            }
            finalDueDay = calendar.startOfDay(for: yesterday)
        }

        guard normalizedStartDate <= finalDueDay else { return nil }

        return ScheduleDateSearchSupport.lastScheduledDay(
            startDate: normalizedStartDate,
            endDate: finalDueDay,
            schedules: schedules,
            calendar: calendar
        )
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

enum ScheduleDateSearchSupport {
    static func lastScheduledDay<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date,
        schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedEndDate = calendar.startOfDay(for: endDate)
        guard normalizedStartDate <= normalizedEndDate else { return nil }

        let sortedSchedules = schedules.sorted { lhs, rhs in
            if lhs.effectiveFrom != rhs.effectiveFrom {
                return lhs.effectiveFrom < rhs.effectiveFrom
            }
            if lhs.version != rhs.version {
                return lhs.version < rhs.version
            }
            return lhs.createdAt < rhs.createdAt
        }
        guard !sortedSchedules.isEmpty else { return nil }

        for index in sortedSchedules.indices.reversed() {
            let schedule = sortedSchedules[index]
            let scheduleEffectiveFrom = calendar.startOfDay(for: schedule.effectiveFrom)
            let segmentStart = max(normalizedStartDate, scheduleEffectiveFrom)
            var segmentEnd = normalizedEndDate

            if let nextIndex = sortedSchedules.index(index, offsetBy: 1, limitedBy: sortedSchedules.endIndex - 1) {
                let nextEffectiveFrom = calendar.startOfDay(for: sortedSchedules[nextIndex].effectiveFrom)
                if let dayBeforeNextSchedule = calendar.date(byAdding: .day, value: -1, to: nextEffectiveFrom) {
                    segmentEnd = min(segmentEnd, calendar.startOfDay(for: dayBeforeNextSchedule))
                }
            }

            guard segmentStart <= segmentEnd else { continue }
            if let candidate = CoreDataHistoryRangeCalculator.lastScheduledDate(
                from: segmentStart,
                through: segmentEnd,
                scheduleRule: schedule.rule,
                useScheduleForHistory: true,
                anchorDate: schedule.effectiveFrom,
                calendar: calendar
            ) {
                return candidate
            }
        }

        return nil
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

        return shouldAutoArchive(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            isFinalized: { finalizedDays.contains($0) },
            calendar: calendar
        )
    }

    static func shouldAutoArchive<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date?,
        schedules: [Schedule],
        isFinalized: (Date) -> Bool,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let normalizedStartDate = calendar.startOfDay(for: startDate)

        if let endDate {
            guard let finalScheduledDay = lastScheduledDay(
                startDate: normalizedStartDate,
                endDate: endDate,
                schedules: schedules,
                calendar: calendar
            ) else {
                return false
            }
            return isFinalized(finalScheduledDay)
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

        return isFinalized(calendar.startOfDay(for: latestSchedule.effectiveFrom))
    }

    static func lastScheduledDay<Schedule: HistoryScheduleVersionLike>(
        startDate: Date,
        endDate: Date,
        schedules: [Schedule],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        ScheduleDateSearchSupport.lastScheduledDay(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            calendar: calendar
        )
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

enum CoreDataHistoryBucketState: Equatable {
    case positive
    case skipped
    case archived

    init?(storageRaw: String) {
        switch storageRaw {
        case "positive":
            self = .positive
        case "skipped":
            self = .skipped
        case "archived":
            self = .archived
        default:
            return nil
        }
    }

    var storageRaw: String {
        switch self {
        case .positive:
            return "positive"
        case .skipped:
            return "skipped"
        case .archived:
            return "archived"
        }
    }
}

struct CoreDataHistoryBucketEntry: Equatable {
    let id: UUID
    let ownerID: UUID
    let localDate: Date
    let state: CoreDataHistoryBucketState
    let createdAt: Date
}

struct CoreDataHistoryBucketDaySets: Equatable {
    var positiveDays: Set<Date> = []
    var skippedDays: Set<Date> = []
    var archivedDays: Set<Date> = []
}

enum CoreDataHistoryRangeCalculator {
    static func count(
        from startDate: Date,
        through endDate: Date,
        scheduleRule: ScheduleRule,
        useScheduleForHistory: Bool,
        anchorDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return 0 }
        guard useScheduleForHistory else {
            return calendar.dateComponents([.day], from: start, to: end).day.map { $0 + 1 } ?? 0
        }

        switch scheduleRule {
        case let .weekly(days):
            return WeekdaySet.orderedDays.reduce(0) { total, entry in
                guard days.contains(entry.1),
                      let first = firstDateMatchingWeekday(entry.1, from: start, through: end, anchorDate: anchorDate, calendar: calendar)
                else {
                    return total
                }
                let daysBetween = calendar.dateComponents([.day], from: first, to: end).day ?? 0
                return total + (daysBetween / 7) + 1
            }
        case let .intervalDays(days):
            guard let first = firstIntervalDate(days: days, from: start, through: end, anchorDate: anchorDate, calendar: calendar) else {
                return 0
            }
            let daysBetween = calendar.dateComponents([.day], from: first, to: end).day ?? 0
            return (daysBetween / days) + 1
        case .oneTime:
            let anchor = calendar.startOfDay(for: anchorDate)
            return (start...end).contains(anchor) ? 1 : 0
        }
    }

    static func firstScheduledDate(
        from startDate: Date,
        through endDate: Date,
        scheduleRule: ScheduleRule,
        useScheduleForHistory: Bool,
        anchorDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return nil }
        guard useScheduleForHistory else { return start }

        switch scheduleRule {
        case let .weekly(days):
            return WeekdaySet.orderedDays
                .filter { days.contains($0.1) }
                .compactMap { firstDateMatchingWeekday($0.1, from: start, through: end, anchorDate: anchorDate, calendar: calendar) }
                .min()
        case let .intervalDays(days):
            return firstIntervalDate(days: days, from: start, through: end, anchorDate: anchorDate, calendar: calendar)
        case .oneTime:
            let anchor = calendar.startOfDay(for: anchorDate)
            return (start...end).contains(anchor) ? anchor : nil
        }
    }

    static func lastScheduledDate(
        from startDate: Date,
        through endDate: Date,
        scheduleRule: ScheduleRule,
        useScheduleForHistory: Bool,
        anchorDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return nil }
        guard useScheduleForHistory else { return end }

        switch scheduleRule {
        case let .weekly(days):
            return WeekdaySet.orderedDays
                .filter { days.contains($0.1) }
                .compactMap { lastDateMatchingWeekday($0.1, from: start, through: end, anchorDate: anchorDate, calendar: calendar) }
                .max()
        case let .intervalDays(days):
            return lastIntervalDate(days: days, from: start, through: end, anchorDate: anchorDate, calendar: calendar)
        case .oneTime:
            let anchor = calendar.startOfDay(for: anchorDate)
            return (start...end).contains(anchor) ? anchor : nil
        }
    }

    private static func firstDateMatchingWeekday(
        _ weekday: WeekdaySet,
        from startDate: Date,
        through endDate: Date,
        anchorDate: Date,
        calendar: Calendar
    ) -> Date? {
        var cursor = max(calendar.startOfDay(for: startDate), calendar.startOfDay(for: anchorDate))
        let end = calendar.startOfDay(for: endDate)

        for _ in 0..<7 {
            guard cursor <= end else { return nil }
            if calendar.weekdaySet(for: cursor) == weekday {
                return cursor
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = calendar.startOfDay(for: next)
        }
        return nil
    }

    private static func lastDateMatchingWeekday(
        _ weekday: WeekdaySet,
        from startDate: Date,
        through endDate: Date,
        anchorDate: Date,
        calendar: Calendar
    ) -> Date? {
        let lowerBound = max(calendar.startOfDay(for: startDate), calendar.startOfDay(for: anchorDate))
        var cursor = calendar.startOfDay(for: endDate)

        for _ in 0..<7 {
            guard cursor >= lowerBound else { return nil }
            if calendar.weekdaySet(for: cursor) == weekday {
                return cursor
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            cursor = calendar.startOfDay(for: previous)
        }
        return nil
    }

    private static func firstIntervalDate(
        days: Int,
        from startDate: Date,
        through endDate: Date,
        anchorDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard ScheduleRule.intervalDaysRange.contains(days) else { return nil }
        let anchor = calendar.startOfDay(for: anchorDate)
        let start = max(calendar.startOfDay(for: startDate), anchor)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return nil }

        let diff = calendar.dateComponents([.day], from: anchor, to: start).day ?? 0
        let remainder = ((diff % days) + days) % days
        let offset = remainder == 0 ? 0 : days - remainder
        guard let first = calendar.date(byAdding: .day, value: offset, to: start).map({ calendar.startOfDay(for: $0) }),
              first <= end
        else {
            return nil
        }
        return first
    }

    private static func lastIntervalDate(
        days: Int,
        from startDate: Date,
        through endDate: Date,
        anchorDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let first = firstIntervalDate(days: days, from: startDate, through: endDate, anchorDate: anchorDate, calendar: calendar) else {
            return nil
        }
        let end = calendar.startOfDay(for: endDate)
        let diff = calendar.dateComponents([.day], from: first, to: end).day ?? 0
        let offset = (diff / days) * days
        return calendar.date(byAdding: .day, value: offset, to: first).map { calendar.startOfDay(for: $0) }
    }
}

struct CoreDataHistoryRangeRecord: Equatable {
    let id: UUID
    let ownerID: UUID
    let startDate: Date
    let endDate: Date
    let state: CoreDataHistoryBucketState
    let useScheduleForHistory: Bool
    let scheduleRule: ScheduleRule
    let anchorDate: Date
    let count: Int
    let createdAt: Date

    func contains(_ day: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        state(on: day, calendar: calendar) != nil
    }

    func state(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> CoreDataHistoryBucketState? {
        let normalizedDay = calendar.startOfDay(for: day)
        guard normalizedDay >= startDate, normalizedDay <= endDate else { return nil }
        guard useScheduleForHistory else { return state }
        return scheduleRule.isScheduled(on: normalizedDay, anchorDate: anchorDate, calendar: calendar) ? state : nil
    }

    func firstDate(for requestedState: CoreDataHistoryBucketState, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard state == requestedState, count > 0 else { return nil }
        return CoreDataHistoryRangeCalculator.firstScheduledDate(
            from: startDate,
            through: endDate,
            scheduleRule: scheduleRule,
            useScheduleForHistory: useScheduleForHistory,
            anchorDate: anchorDate,
            calendar: calendar
        )
    }

    func lastDate(for requestedState: CoreDataHistoryBucketState, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard state == requestedState, count > 0 else { return nil }
        return CoreDataHistoryRangeCalculator.lastScheduledDate(
            from: startDate,
            through: endDate,
            scheduleRule: scheduleRule,
            useScheduleForHistory: useScheduleForHistory,
            anchorDate: anchorDate,
            calendar: calendar
        )
    }
}

struct CoreDataHistoryRangeDraft: Equatable {
    let startDate: Date
    let endDate: Date
    let state: CoreDataHistoryBucketState
    let useScheduleForHistory: Bool
    let scheduleRule: ScheduleRule
    let anchorDate: Date
    let count: Int

    func contains(_ day: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let normalizedDay = calendar.startOfDay(for: day)
        guard normalizedDay >= startDate, normalizedDay <= endDate else { return false }
        guard useScheduleForHistory else { return true }
        return scheduleRule.isScheduled(on: normalizedDay, anchorDate: anchorDate, calendar: calendar)
    }
}

struct CoreDataHistoryBucketSnapshot: Equatable {
    fileprivate struct Masks: Equatable {
        let positive: Int64
        let skipped: Int64
        let archived: Int64
    }

    private let masksByYearMonth: [Int32: Masks]
    private let rangeRecords: [CoreDataHistoryRangeRecord]
    private let legacyStatesByDay: [Date: CoreDataHistoryBucketState]

    let positiveCount: Int
    let skippedCount: Int
    let archivedCount: Int

    fileprivate init(
        masksByYearMonth: [Int32: Masks],
        rangeRecords: [CoreDataHistoryRangeRecord],
        legacyStatesByDay: [Date: CoreDataHistoryBucketState],
        positiveCount: Int,
        skippedCount: Int,
        archivedCount: Int
    ) {
        self.masksByYearMonth = masksByYearMonth
        self.rangeRecords = rangeRecords
        self.legacyStatesByDay = legacyStatesByDay
        self.positiveCount = positiveCount
        self.skippedCount = skippedCount
        self.archivedCount = archivedCount
    }

    func state(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> CoreDataHistoryBucketState? {
        let normalizedDay = calendar.startOfDay(for: day)
        let key = CoreDataHistoryBucketSupport.yearMonthKey(for: normalizedDay, calendar: calendar)
        if
            let masks = masksByYearMonth[key],
            let bit = CoreDataHistoryBucketSupport.bit(for: normalizedDay, calendar: calendar)
        {
            if masks.positive & bit != 0 { return .positive }
            if masks.skipped & bit != 0 { return .skipped }
            if masks.archived & bit != 0 { return .archived }
        }
        if let legacyState = legacyStatesByDay[normalizedDay] {
            return legacyState
        }
        return rangeRecords.first { $0.state(on: normalizedDay, calendar: calendar) != nil }?.state
    }

    func daySets(
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CoreDataHistoryBucketDaySets {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        guard normalizedStart <= normalizedEnd else { return CoreDataHistoryBucketDaySets() }

        var result = CoreDataHistoryBucketDaySets()
        var cursor = normalizedStart
        while cursor <= normalizedEnd {
            switch state(on: cursor, calendar: calendar) {
            case .positive:
                result.positiveDays.insert(cursor)
            case .skipped:
                result.skippedDays.insert(cursor)
            case .archived:
                result.archivedDays.insert(cursor)
            case nil:
                break
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    var earliestPositiveDate: Date? {
        positiveDate(searchForward: true)
    }

    var latestPositiveDate: Date? {
        positiveDate(searchForward: false)
    }

    func positiveStreakSeed(calendar: Calendar = .autoupdatingCurrent) -> StreakEngine.Seed? {
        let positiveRanges = rangeRecords.compactMap { record -> (lastDate: Date, count: Int)? in
            guard let lastDate = record.lastDate(for: .positive, calendar: calendar), record.count > 0 else {
                return nil
            }
            return (lastDate, record.count)
        }
        guard
            let latestRange = positiveRanges.max(by: { $0.lastDate < $1.lastDate }),
            let resumeDate = calendar.date(byAdding: .day, value: 1, to: latestRange.lastDate)
        else {
            return nil
        }

        let longest = positiveRanges.map(\.count).max() ?? 0
        return StreakEngine.Seed(
            resumeDate: calendar.startOfDay(for: resumeDate),
            running: latestRange.count,
            longest: longest
        )
    }

    private func positiveDate(searchForward: Bool) -> Date? {
        let sortedKeys = masksByYearMonth.keys.sorted()
        let orderedKeys = searchForward ? sortedKeys : Array(sortedKeys.reversed())
        var candidate: Date?

        for key in orderedKeys {
            guard let mask = masksByYearMonth[key]?.positive, mask != 0 else { continue }
            let orderedDays: AnySequence<Int> = searchForward ? AnySequence(1...31) : AnySequence((1...31).reversed())
            for day in orderedDays {
                let bit = Int64(1) << Int64(day - 1)
                guard mask & bit != 0 else { continue }
                if let date = CoreDataHistoryBucketSupport.date(yearMonthKey: key, day: day) {
                    candidate = date
                    break
                }
            }
            if candidate != nil { break }
        }

        let legacyPositiveDays = legacyStatesByDay
            .filter { $0.value == .positive }
            .map(\.key)
        let legacyCandidate = searchForward ? legacyPositiveDays.min() : legacyPositiveDays.max()
        let rangePositiveDays = rangeRecords.compactMap {
            searchForward ? $0.firstDate(for: .positive) : $0.lastDate(for: .positive)
        }
        let rangeCandidate = searchForward ? rangePositiveDays.min() : rangePositiveDays.max()

        let candidates = [candidate, legacyCandidate, rangeCandidate].compactMap { $0 }
        return searchForward ? candidates.min() : candidates.max()
    }
}

struct CoreDataHistoryBucketMaskPlan: Equatable {
    let masksByYearMonth: [Int32: Int64]

    static let empty = CoreDataHistoryBucketMaskPlan(masksByYearMonth: [:])

    var isEmpty: Bool {
        masksByYearMonth.isEmpty
    }

    var dayCount: Int {
        masksByYearMonth.values.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    func dates(calendar: Calendar = .autoupdatingCurrent) -> Set<Date> {
        var result = Set<Date>()
        for (yearMonthKey, mask) in masksByYearMonth {
            for day in 1...31 {
                let bit = Int64(1) << Int64(day - 1)
                guard mask & bit != 0,
                      let date = CoreDataHistoryBucketSupport.date(yearMonthKey: yearMonthKey, day: day, calendar: calendar)
                else {
                    continue
                }
                result.insert(date)
            }
        }
        return result
    }

    func contains(_ localDate: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        guard let bit = CoreDataHistoryBucketSupport.bit(for: normalizedDate, calendar: calendar) else {
            return false
        }
        let key = CoreDataHistoryBucketSupport.yearMonthKey(for: normalizedDate, calendar: calendar)
        return (masksByYearMonth[key] ?? 0) & bit != 0
    }
}

struct CoreDataInitialPositiveHistoryPlan: Equatable {
    let coldRange: CoreDataHistoryRangeDraft?
    let editableBucketPlan: CoreDataHistoryBucketMaskPlan

    static let empty = CoreDataInitialPositiveHistoryPlan(
        coldRange: nil,
        editableBucketPlan: .empty
    )

    func contains(_ localDate: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        if editableBucketPlan.contains(localDate, calendar: calendar) {
            return true
        }
        return coldRange?.contains(localDate, calendar: calendar) ?? false
    }
}

enum CoreDataInitialHistoryPlanner {
    static func positiveHistoryPlan(
        startDate: Date,
        endDate: Date?,
        scheduleRule: ScheduleRule,
        useScheduleForHistory: Bool,
        today: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CoreDataInitialPositiveHistoryPlan {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedToday = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: normalizedToday) else {
            return .empty
        }

        let normalizedYesterday = calendar.startOfDay(for: yesterday)
        let normalizedEndDate = endDate.map { calendar.startOfDay(for: $0) }
        let finalDay = normalizedEndDate.map { min(normalizedYesterday, $0) } ?? normalizedYesterday
        guard normalizedStartDate <= finalDay else {
            return .empty
        }

        let editableStart = calendar.date(byAdding: .day, value: -29, to: normalizedToday)
            .map { calendar.startOfDay(for: $0) } ?? normalizedToday
        let coldEnd = calendar.date(byAdding: .day, value: -1, to: editableStart)
            .map { calendar.startOfDay(for: $0) }

        let coldRange: CoreDataHistoryRangeDraft?
        if let coldEnd, normalizedStartDate <= coldEnd {
            let rangeEnd = min(coldEnd, finalDay)
            let count = CoreDataHistoryRangeCalculator.count(
                from: normalizedStartDate,
                through: rangeEnd,
                scheduleRule: scheduleRule,
                useScheduleForHistory: useScheduleForHistory,
                anchorDate: normalizedStartDate,
                calendar: calendar
            )
            coldRange = count > 0 ? CoreDataHistoryRangeDraft(
                startDate: normalizedStartDate,
                endDate: rangeEnd,
                state: .positive,
                useScheduleForHistory: useScheduleForHistory,
                scheduleRule: scheduleRule,
                anchorDate: normalizedStartDate,
                count: count
            ) : nil
        } else {
            coldRange = nil
        }

        let editablePlan: CoreDataHistoryBucketMaskPlan
        let editablePlanStart = max(normalizedStartDate, editableStart)
        if editablePlanStart <= finalDay {
            editablePlan = CoreDataInitialHistoryBucketPlanner.plan(
                from: editablePlanStart,
                through: finalDay,
                scheduleRule: scheduleRule,
                anchorDate: normalizedStartDate,
                useScheduleForHistory: useScheduleForHistory,
                calendar: calendar
            )
        } else {
            editablePlan = .empty
        }

        return CoreDataInitialPositiveHistoryPlan(
            coldRange: coldRange,
            editableBucketPlan: editablePlan
        )
    }
}

enum CoreDataInitialHistoryBucketPlanner {
    static func positiveHistoryPlan(
        startDate: Date,
        endDate: Date?,
        scheduleRule: ScheduleRule,
        useScheduleForHistory: Bool,
        today: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CoreDataHistoryBucketMaskPlan {
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedToday = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: normalizedToday) else {
            return .empty
        }

        let normalizedEndDate = endDate.map { calendar.startOfDay(for: $0) }
        let finalDay = normalizedEndDate.map { min(calendar.startOfDay(for: yesterday), $0) } ?? calendar.startOfDay(for: yesterday)
        guard normalizedStartDate <= finalDay else {
            return .empty
        }

        return plan(
            from: normalizedStartDate,
            through: finalDay,
            scheduleRule: scheduleRule,
            anchorDate: normalizedStartDate,
            useScheduleForHistory: useScheduleForHistory,
            calendar: calendar
        )
    }

    static func plan(
        from startDate: Date,
        through endDate: Date,
        scheduleRule: ScheduleRule,
        anchorDate: Date,
        useScheduleForHistory: Bool,
        calendar: Calendar
    ) -> CoreDataHistoryBucketMaskPlan {
        guard var monthStart = firstDayOfMonth(for: startDate, calendar: calendar) else {
            return .empty
        }

        var masks: [Int32: Int64] = [:]
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedEndDate = calendar.startOfDay(for: endDate)

        while monthStart <= normalizedEndDate {
            guard
                let monthEnd = endOfMonth(for: monthStart, calendar: calendar),
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else {
                break
            }

            let rangeStart = max(normalizedStartDate, monthStart)
            let rangeEnd = min(normalizedEndDate, monthEnd)

            if rangeStart <= rangeEnd {
                let mask = monthMask(
                    from: rangeStart,
                    through: rangeEnd,
                    scheduleRule: scheduleRule,
                    anchorDate: anchorDate,
                    useScheduleForHistory: useScheduleForHistory,
                    calendar: calendar
                )

                if mask != 0 {
                    masks[CoreDataHistoryBucketSupport.yearMonthKey(for: monthStart, calendar: calendar)] = mask
                }
            }

            monthStart = calendar.startOfDay(for: nextMonth)
        }

        return CoreDataHistoryBucketMaskPlan(masksByYearMonth: masks)
    }

    private static func monthMask(
        from startDate: Date,
        through endDate: Date,
        scheduleRule: ScheduleRule,
        anchorDate: Date,
        useScheduleForHistory: Bool,
        calendar: Calendar
    ) -> Int64 {
        let startDay = calendar.component(.day, from: startDate)
        let endDay = calendar.component(.day, from: endDate)
        guard startDay <= endDay else { return 0 }

        if !useScheduleForHistory {
            return contiguousMask(from: startDay, through: endDay)
        }

        var mask: Int64 = 0
        let components = calendar.dateComponents([.year, .month], from: startDate)

        for day in startDay...endDay {
            guard let localDate = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day)) else {
                continue
            }

            let normalizedDate = calendar.startOfDay(for: localDate)
            if scheduleRule.isScheduled(on: normalizedDate, anchorDate: anchorDate, calendar: calendar),
               let bit = CoreDataHistoryBucketSupport.bit(for: normalizedDate, calendar: calendar) {
                mask |= bit
            }
        }

        return mask
    }

    private static func contiguousMask(from startDay: Int, through endDay: Int) -> Int64 {
        guard (1...31).contains(startDay), (1...31).contains(endDay), startDay <= endDay else {
            return 0
        }

        let width = endDay - startDay + 1
        let mask = (Int64(1) << Int64(width)) - 1
        return mask << Int64(startDay - 1)
    }

    private static func firstDayOfMonth(for date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1))
            .map { calendar.startOfDay(for: $0) }
    }

    private static func endOfMonth(for monthStart: Date, calendar: Calendar) -> Date? {
        guard
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
            let end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: nextMonth))
        else {
            return nil
        }
        return calendar.startOfDay(for: end)
    }
}

enum CoreDataHistoryRangeSupport {
    private struct DateSpan {
        let start: Date
        let end: Date
    }

    static func records(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        ownerKey: String,
        ownerID: UUID,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CoreDataHistoryRangeRecord] {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        return rows
            .compactMap { record(from: $0, ownerKey: ownerKey, ownerID: ownerID, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func validatedRecords(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        ownerKey: String,
        area: String,
        invalidMessage: String,
        report: inout IntegrityReportBuilder,
        ownerID: UUID,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CoreDataHistoryRangeRecord]? {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        var records: [CoreDataHistoryRangeRecord] = []

        for row in rows {
            guard isValidRange(row, ownerKey: ownerKey, calendar: calendar),
                  let record = record(from: row, ownerKey: ownerKey, ownerID: ownerID, calendar: calendar)
            else {
                report.append(
                    area: area,
                    entityName: row.entityName,
                    object: row,
                    message: invalidMessage
                )
                return nil
            }
            records.append(record)
        }

        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.createdAt < rhs.createdAt
        }

        for pair in zip(sortedRecords, sortedRecords.dropFirst()) where pair.0.endDate >= pair.1.startDate {
            report.append(
                area: area,
                entityName: ownerObject.entityName,
                object: ownerObject,
                message: "History ranges overlap."
            )
            return nil
        }

        return sortedRecords
    }

    @discardableResult
    static func insertRange(
        owner: NSManagedObject,
        ownerID: UUID,
        draft: CoreDataHistoryRangeDraft?,
        rangeEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) throws -> Bool {
        guard let draft, draft.count > 0 else { return false }

        insertRangeRow(
            owner: owner,
            ownerID: ownerID,
            draft: draft,
            rangeEntityName: rangeEntityName,
            ownerKey: ownerKey,
            ownerRelationshipKey: ownerRelationshipKey,
            in: context,
            createdAt: now,
            updatedAt: now
        )
        return true
    }

    @discardableResult
    static func insertCalendarDayRanges(
        owner: NSManagedObject,
        ownerID: UUID,
        startDate: Date,
        endDate: Date,
        state: CoreDataHistoryBucketState,
        excludedDays: Set<Date>,
        rangeEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> Int {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        guard normalizedStart <= normalizedEnd else { return 0 }

        let existingRangeSpans = records(
            from: owner,
            relationshipKey: "historyRanges",
            ownerKey: ownerKey,
            ownerID: ownerID,
            calendar: calendar
        ).map { DateSpan(start: $0.startDate, end: $0.endDate) }

        let excludedSpans = excludedDays
            .map { calendar.startOfDay(for: $0) }
            .filter { $0 >= normalizedStart && $0 <= normalizedEnd }
            .map { DateSpan(start: $0, end: $0) }
            + existingRangeSpans

        var insertedCount = 0
        for segment in availableSegments(from: normalizedStart, through: normalizedEnd, excluding: excludedSpans, calendar: calendar) {
            let count = CoreDataHistoryRangeCalculator.count(
                from: segment.start,
                through: segment.end,
                scheduleRule: .weekly(.daily),
                useScheduleForHistory: false,
                anchorDate: segment.start,
                calendar: calendar
            )
            let draft = CoreDataHistoryRangeDraft(
                startDate: segment.start,
                endDate: segment.end,
                state: state,
                useScheduleForHistory: false,
                scheduleRule: .weekly(.daily),
                anchorDate: segment.start,
                count: count
            )
            if try insertRange(
                owner: owner,
                ownerID: ownerID,
                draft: draft,
                rangeEntityName: rangeEntityName,
                ownerKey: ownerKey,
                ownerRelationshipKey: ownerRelationshipKey,
                in: context,
                now: now
            ) {
                insertedCount += 1
            }
        }
        return insertedCount
    }

    @discardableResult
    static func removeDates(
        owner: NSManagedObject,
        ownerID: UUID,
        dates: Set<Date>,
        rangeEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> Bool {
        let normalizedDates = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !normalizedDates.isEmpty else { return false }

        let rows = (owner.mutableSetValue(forKey: "historyRanges").allObjects as? [NSManagedObject]) ?? []
        var didChange = false

        for row in rows {
            guard let record = record(from: row, ownerKey: ownerKey, ownerID: ownerID, calendar: calendar) else { continue }
            let datesInsideRecord = normalizedDates.filter { $0 >= record.startDate && $0 <= record.endDate }
            guard !datesInsideRecord.isEmpty else { continue }

            context.delete(row)
            didChange = true

            let excludedSpans = datesInsideRecord.map { DateSpan(start: $0, end: $0) }
            for segment in availableSegments(from: record.startDate, through: record.endDate, excluding: excludedSpans, calendar: calendar) {
                let count = CoreDataHistoryRangeCalculator.count(
                    from: segment.start,
                    through: segment.end,
                    scheduleRule: record.scheduleRule,
                    useScheduleForHistory: record.useScheduleForHistory,
                    anchorDate: record.anchorDate,
                    calendar: calendar
                )
                guard count > 0 else { continue }
                let draft = CoreDataHistoryRangeDraft(
                    startDate: segment.start,
                    endDate: segment.end,
                    state: record.state,
                    useScheduleForHistory: record.useScheduleForHistory,
                    scheduleRule: record.scheduleRule,
                    anchorDate: record.anchorDate,
                    count: count
                )
                insertRangeRow(
                    owner: owner,
                    ownerID: ownerID,
                    draft: draft,
                    rangeEntityName: rangeEntityName,
                    ownerKey: ownerKey,
                    ownerRelationshipKey: ownerRelationshipKey,
                    in: context,
                    createdAt: record.createdAt,
                    updatedAt: now
                )
            }
        }

        return didChange
    }

    private static func insertRangeRow(
        owner: NSManagedObject,
        ownerID: UUID,
        draft: CoreDataHistoryRangeDraft,
        rangeEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        in context: NSManagedObjectContext,
        createdAt: Date,
        updatedAt: Date
    ) {
        let row = NSEntityDescription.insertNewObject(forEntityName: rangeEntityName, into: context)
        row.setValue(UUID(), forKey: "id")
        row.setValue(ownerID, forKey: ownerKey)
        row.setValue(draft.startDate, forKey: "startDate")
        row.setValue(draft.endDate, forKey: "endDate")
        row.setValue(draft.state.storageRaw, forKey: "stateRaw")
        row.setValue(draft.useScheduleForHistory, forKey: "useScheduleForHistory")
        row.setValue(draft.scheduleRule.kind.rawValue, forKey: "scheduleKindRaw")
        row.setValue(Int16(draft.scheduleRule.storageWeekdayMask), forKey: "weekdayMask")
        row.setValue(Int16(draft.scheduleRule.storageIntervalDays), forKey: "intervalDays")
        row.setValue(draft.anchorDate, forKey: "anchorDate")
        row.setValue(Int32(draft.count), forKey: "count")
        row.setValue(createdAt, forKey: "createdAt")
        row.setValue(updatedAt, forKey: "updatedAt")
        row.setValue(owner, forKey: ownerRelationshipKey)
    }

    static func state(
        ownerID: UUID,
        localDate: Date,
        rangeEntityName: String,
        ownerKey: String,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> CoreDataHistoryBucketState? {
        let normalizedDate = calendar.startOfDay(for: localDate)
        let request = NSFetchRequest<NSManagedObject>(entityName: rangeEntityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", ownerKey, ownerID as CVarArg),
            NSPredicate(format: "startDate <= %@", normalizedDate as CVarArg),
            NSPredicate(format: "endDate >= %@", normalizedDate as CVarArg),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        return try context.fetch(request)
            .compactMap { row in
                record(from: row, ownerKey: ownerKey, ownerID: ownerID, calendar: calendar)?
                    .state(on: normalizedDate, calendar: calendar)
            }
            .first
    }

    static func isValidPayload(
        startDate: Date,
        endDate: Date,
        stateRaw: String,
        useScheduleForHistory: Bool,
        scheduleKindRaw: String,
        weekdayMask: Int,
        intervalDays: Int,
        anchorDate: Date,
        count: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        let normalizedAnchor = calendar.startOfDay(for: anchorDate)
        guard normalizedStart <= normalizedEnd,
              CoreDataHistoryBucketState(storageRaw: stateRaw) != nil,
              count >= 0,
              let rule = ScheduleRule.make(
                kindRaw: scheduleKindRaw,
                weekdayMask: weekdayMask,
                intervalDays: intervalDays,
                effectiveFrom: normalizedAnchor,
                calendar: calendar
              )
        else {
            return false
        }

        let expectedCount = CoreDataHistoryRangeCalculator.count(
            from: normalizedStart,
            through: normalizedEnd,
            scheduleRule: rule,
            useScheduleForHistory: useScheduleForHistory,
            anchorDate: normalizedAnchor,
            calendar: calendar
        )
        return count == expectedCount
    }

    private static func record(
        from row: NSManagedObject,
        ownerKey: String,
        ownerID fallbackOwnerID: UUID,
        calendar: Calendar
    ) -> CoreDataHistoryRangeRecord? {
        guard
            let id = row.uuidValue(forKey: "id"),
            let startDate = row.dateValue(forKey: "startDate"),
            let endDate = row.dateValue(forKey: "endDate"),
            let stateRaw = row.stringValue(forKey: "stateRaw"),
            let state = CoreDataHistoryBucketState(storageRaw: stateRaw),
            let scheduleKindRaw = row.stringValue(forKey: "scheduleKindRaw"),
            let anchorDate = row.dateValue(forKey: "anchorDate"),
            let createdAt = row.dateValue(forKey: "createdAt"),
            let rule = ScheduleRule.make(
                kindRaw: scheduleKindRaw,
                weekdayMask: Int(row.int16Value(forKey: "weekdayMask")),
                intervalDays: Int(row.int16Value(forKey: "intervalDays", default: Int16(ScheduleRule.defaultIntervalDays))),
                effectiveFrom: anchorDate,
                calendar: calendar
            )
        else {
            return nil
        }

        return CoreDataHistoryRangeRecord(
            id: id,
            ownerID: row.uuidValue(forKey: ownerKey) ?? fallbackOwnerID,
            startDate: calendar.startOfDay(for: startDate),
            endDate: calendar.startOfDay(for: endDate),
            state: state,
            useScheduleForHistory: row.boolValue(forKey: "useScheduleForHistory"),
            scheduleRule: rule,
            anchorDate: calendar.startOfDay(for: anchorDate),
            count: Int(row.int32Value(forKey: "count")),
            createdAt: createdAt
        )
    }

    private static func isValidRange(
        _ row: NSManagedObject,
        ownerKey: String,
        calendar: Calendar
    ) -> Bool {
        guard
            row.uuidValue(forKey: "id") != nil,
            row.uuidValue(forKey: ownerKey) != nil,
            let startDate = row.dateValue(forKey: "startDate"),
            let endDate = row.dateValue(forKey: "endDate"),
            let stateRaw = row.stringValue(forKey: "stateRaw"),
            let scheduleKindRaw = row.stringValue(forKey: "scheduleKindRaw"),
            let anchorDate = row.dateValue(forKey: "anchorDate"),
            row.dateValue(forKey: "createdAt") != nil,
            row.dateValue(forKey: "updatedAt") != nil
        else {
            return false
        }

        return isValidPayload(
            startDate: startDate,
            endDate: endDate,
            stateRaw: stateRaw,
            useScheduleForHistory: row.boolValue(forKey: "useScheduleForHistory"),
            scheduleKindRaw: scheduleKindRaw,
            weekdayMask: Int(row.int16Value(forKey: "weekdayMask")),
            intervalDays: Int(row.int16Value(forKey: "intervalDays", default: Int16(ScheduleRule.defaultIntervalDays))),
            anchorDate: anchorDate,
            count: Int(row.int32Value(forKey: "count")),
            calendar: calendar
        )
    }

    private static func availableSegments(
        from startDate: Date,
        through endDate: Date,
        excluding excludedSpans: [DateSpan],
        calendar: Calendar
    ) -> [DateSpan] {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        guard normalizedStart <= normalizedEnd else { return [] }

        let sortedSpans = excludedSpans
            .map {
                DateSpan(
                    start: calendar.startOfDay(for: $0.start),
                    end: calendar.startOfDay(for: $0.end)
                )
            }
            .filter { $0.end >= normalizedStart && $0.start <= normalizedEnd }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.end < $1.end
            }

        var segments: [DateSpan] = []
        var cursor = normalizedStart

        for span in sortedSpans {
            let clippedStart = max(span.start, normalizedStart)
            let clippedEnd = min(span.end, normalizedEnd)
            guard clippedEnd >= cursor else { continue }

            if clippedStart > cursor,
               let segmentEnd = calendar.date(byAdding: .day, value: -1, to: clippedStart) {
                segments.append(DateSpan(start: cursor, end: calendar.startOfDay(for: segmentEnd)))
            }

            guard let nextCursor = calendar.date(byAdding: .day, value: 1, to: max(cursor, clippedEnd)) else {
                return segments
            }
            cursor = calendar.startOfDay(for: nextCursor)
            if cursor > normalizedEnd { return segments }
        }

        if cursor <= normalizedEnd {
            segments.append(DateSpan(start: cursor, end: normalizedEnd))
        }

        return segments
    }
}

enum CoreDataHistoryBucketSupport {
    static func yearMonthKey(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int32 {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return Int32(year * 100 + month)
    }

    static func date(
        yearMonthKey: Int32,
        day: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let year = Int(yearMonthKey / 100)
        let month = Int(yearMonthKey % 100)
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.startOfDay(for: $0) }
    }

    static func bit(
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int64? {
        let day = calendar.component(.day, from: date)
        guard (1...31).contains(day) else { return nil }
        return Int64(1) << Int64(day - 1)
    }

    static func entries(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        ownerID: UUID,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CoreDataHistoryBucketEntry] {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        return rows.flatMap { entries(from: $0, ownerID: ownerID, calendar: calendar) }
    }

    static func validatedEntries(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        area: String,
        invalidMessage: String,
        report: inout IntegrityReportBuilder,
        ownerID: UUID,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CoreDataHistoryBucketEntry]? {
        let rows = (ownerObject.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        var models: [CoreDataHistoryBucketEntry] = []

        for row in rows {
            guard isValidBucket(row) else {
                report.append(
                    area: area,
                    entityName: row.entityName,
                    object: row,
                    message: invalidMessage
                )
                return nil
            }

            models.append(contentsOf: entries(from: row, ownerID: ownerID, calendar: calendar))
        }

        return models
    }

    static func snapshot(
        from ownerObject: NSManagedObject,
        bucketRelationshipKey: String,
        rangeRelationshipKey: String? = nil,
        rangeOwnerKey: String? = nil,
        ownerID: UUID? = nil,
        legacyRelationshipKey: String,
        legacySourceToState: (String) -> CoreDataHistoryBucketState?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CoreDataHistoryBucketSnapshot {
        let bucketRows = (ownerObject.mutableSetValue(forKey: bucketRelationshipKey).allObjects as? [NSManagedObject]) ?? []
        let legacyRows = (ownerObject.mutableSetValue(forKey: legacyRelationshipKey).allObjects as? [NSManagedObject]) ?? []
        let rangeRecords: [CoreDataHistoryRangeRecord]
        if let rangeRelationshipKey, let rangeOwnerKey, let ownerID {
            rangeRecords = CoreDataHistoryRangeSupport.records(
                from: ownerObject,
                relationshipKey: rangeRelationshipKey,
                ownerKey: rangeOwnerKey,
                ownerID: ownerID,
                calendar: calendar
            )
        } else {
            rangeRecords = []
        }
        return makeSnapshot(
            bucketRows: bucketRows.filter(isValidBucket),
            rangeRecords: rangeRecords,
            legacyRows: legacyRows,
            legacySourceToState: legacySourceToState,
            calendar: calendar
        )
    }

    static func validatedSnapshot(
        from ownerObject: NSManagedObject,
        bucketRelationshipKey: String,
        rangeRelationshipKey: String? = nil,
        rangeOwnerKey: String? = nil,
        ownerID: UUID? = nil,
        legacyRelationshipKey: String,
        area: String,
        invalidBucketMessage: String,
        invalidRangeMessage: String = "History range row is missing required fields or has invalid schedule/count.",
        invalidLegacyMessage: String,
        report: inout IntegrityReportBuilder,
        legacySourceToState: (String) -> CoreDataHistoryBucketState?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CoreDataHistoryBucketSnapshot? {
        let bucketRows = (ownerObject.mutableSetValue(forKey: bucketRelationshipKey).allObjects as? [NSManagedObject]) ?? []
        let legacyRows = (ownerObject.mutableSetValue(forKey: legacyRelationshipKey).allObjects as? [NSManagedObject]) ?? []
        let rangeRecords: [CoreDataHistoryRangeRecord]
        if let rangeRelationshipKey, let rangeOwnerKey, let ownerID {
            guard let validatedRanges = CoreDataHistoryRangeSupport.validatedRecords(
                from: ownerObject,
                relationshipKey: rangeRelationshipKey,
                ownerKey: rangeOwnerKey,
                area: area,
                invalidMessage: invalidRangeMessage,
                report: &report,
                ownerID: ownerID,
                calendar: calendar
            ) else {
                return nil
            }
            rangeRecords = validatedRanges
        } else {
            rangeRecords = []
        }

        for row in bucketRows where !isValidBucket(row) {
            report.append(
                area: area,
                entityName: row.entityName,
                object: row,
                message: invalidBucketMessage
            )
            return nil
        }

        for row in legacyRows {
            guard
                row.uuidValue(forKey: "id") != nil,
                row.dateValue(forKey: "localDate") != nil,
                let sourceRaw = row.stringValue(forKey: "sourceRaw"),
                legacySourceToState(sourceRaw) != nil,
                row.dateValue(forKey: "createdAt") != nil
            else {
                report.append(
                    area: area,
                    entityName: row.entityName,
                    object: row,
                    message: invalidLegacyMessage
                )
                return nil
            }
        }

        return makeSnapshot(
            bucketRows: bucketRows,
            rangeRecords: rangeRecords,
            legacyRows: legacyRows,
            legacySourceToState: legacySourceToState,
            calendar: calendar
        )
    }

    static func state(
        ownerID: UUID,
        localDate: Date,
        bucketEntityName: String,
        ownerKey: String,
        legacyEntityName: String,
        rangeEntityName: String? = nil,
        legacySourceToState: (String) -> CoreDataHistoryBucketState?,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> CoreDataHistoryBucketState? {
        let normalizedDate = calendar.startOfDay(for: localDate)
        if
            let bucket = try fetchBucket(
                entityName: bucketEntityName,
                ownerKey: ownerKey,
                ownerID: ownerID,
                yearMonthKey: yearMonthKey(for: normalizedDate, calendar: calendar),
                in: context
            ),
            let state = state(in: bucket, localDate: normalizedDate, calendar: calendar)
        {
            return state
        }

        if let legacyState = try legacyState(
            ownerID: ownerID,
            localDate: normalizedDate,
            ownerKey: ownerKey,
            legacyEntityName: legacyEntityName,
            legacySourceToState: legacySourceToState,
            in: context
        ) {
            return legacyState
        }

        if let rangeEntityName {
            return try CoreDataHistoryRangeSupport.state(
                ownerID: ownerID,
                localDate: normalizedDate,
                rangeEntityName: rangeEntityName,
                ownerKey: ownerKey,
                in: context,
                calendar: calendar
            )
        }

        return nil
    }

    @discardableResult
    static func setState(
        owner: NSManagedObject,
        ownerID: UUID,
        localDate: Date,
        state desiredState: CoreDataHistoryBucketState,
        bucketEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        legacyEntityName: String,
        rangeEntityName: String? = nil,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        let bucket = try fetchOrCreateBucket(
            owner: owner,
            ownerID: ownerID,
            localDate: normalizedDate,
            bucketEntityName: bucketEntityName,
            ownerKey: ownerKey,
            ownerRelationshipKey: ownerRelationshipKey,
            in: context,
            calendar: calendar,
            now: now
        )
        let previousState = state(in: bucket, localDate: normalizedDate, calendar: calendar)

        clearBit(for: normalizedDate, in: bucket, calendar: calendar)
        setBit(for: normalizedDate, state: desiredState, in: bucket, calendar: calendar)
        bucket.setValue(now, forKey: "updatedAt")
        recomputeCounts(in: bucket)

        let deletedLegacyRows = try deleteLegacyRows(
            ownerID: ownerID,
            localDate: normalizedDate,
            ownerKey: ownerKey,
            legacyEntityName: legacyEntityName,
            in: context
        )

        let didTrimRanges: Bool
        if let rangeEntityName {
            didTrimRanges = try CoreDataHistoryRangeSupport.removeDates(
                owner: owner,
                ownerID: ownerID,
                dates: [normalizedDate],
                rangeEntityName: rangeEntityName,
                ownerKey: ownerKey,
                ownerRelationshipKey: ownerRelationshipKey,
                in: context,
                calendar: calendar,
                now: now
            )
        } else {
            didTrimRanges = false
        }

        return previousState != desiredState || deletedLegacyRows || didTrimRanges
    }

    @discardableResult
    static func setStates(
        owner: NSManagedObject,
        ownerID: UUID,
        plan: CoreDataHistoryBucketMaskPlan,
        state desiredState: CoreDataHistoryBucketState,
        bucketEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        legacyEntityName: String,
        rangeEntityName: String? = nil,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date(),
        shouldDeleteLegacyRows: Bool = true
    ) throws -> Bool {
        var didChange = false

        for (yearMonthKey, rawMask) in plan.masksByYearMonth where rawMask != 0 {
            let mask = rawMask & validBitsMask
            guard mask != 0 else { continue }

            let bucket = try fetchOrCreateBucket(
                owner: owner,
                ownerID: ownerID,
                yearMonthKey: yearMonthKey,
                bucketEntityName: bucketEntityName,
                ownerKey: ownerKey,
                ownerRelationshipKey: ownerRelationshipKey,
                in: context,
                now: now
            )

            let oldPositiveMask = bucket.int64Value(forKey: "positiveMask")
            let oldSkippedMask = bucket.int64Value(forKey: "skippedMask")
            let oldArchivedMask = bucket.int64Value(forKey: "archivedMask")

            var positiveMask = oldPositiveMask & ~mask
            var skippedMask = oldSkippedMask & ~mask
            var archivedMask = oldArchivedMask & ~mask

            switch desiredState {
            case .positive:
                positiveMask |= mask
            case .skipped:
                skippedMask |= mask
            case .archived:
                archivedMask |= mask
            }

            if positiveMask != oldPositiveMask || skippedMask != oldSkippedMask || archivedMask != oldArchivedMask {
                didChange = true
                bucket.setValue(positiveMask, forKey: "positiveMask")
                bucket.setValue(skippedMask, forKey: "skippedMask")
                bucket.setValue(archivedMask, forKey: "archivedMask")
                bucket.setValue(now, forKey: "updatedAt")
                recomputeCounts(in: bucket)
            }

            if shouldDeleteLegacyRows {
                didChange = try deleteLegacyRows(
                    ownerID: ownerID,
                    yearMonthKey: yearMonthKey,
                    mask: mask,
                    ownerKey: ownerKey,
                    legacyEntityName: legacyEntityName,
                    in: context,
                    calendar: calendar
                ) || didChange
            }
        }

        if let rangeEntityName {
            didChange = try CoreDataHistoryRangeSupport.removeDates(
                owner: owner,
                ownerID: ownerID,
                dates: plan.dates(calendar: calendar),
                rangeEntityName: rangeEntityName,
                ownerKey: ownerKey,
                ownerRelationshipKey: ownerRelationshipKey,
                in: context,
                calendar: calendar,
                now: now
            ) || didChange
        }

        return didChange
    }

    @discardableResult
    static func clearState(
        owner: NSManagedObject? = nil,
        ownerID: UUID,
        localDate: Date,
        bucketEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String? = nil,
        legacyEntityName: String,
        rangeEntityName: String? = nil,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        var didChange = false

        if
            let bucket = try fetchBucket(
                entityName: bucketEntityName,
                ownerKey: ownerKey,
                ownerID: ownerID,
                yearMonthKey: yearMonthKey(for: normalizedDate, calendar: calendar),
                in: context
            ),
            state(in: bucket, localDate: normalizedDate, calendar: calendar) != nil
        {
            clearBit(for: normalizedDate, in: bucket, calendar: calendar)
            bucket.setValue(now, forKey: "updatedAt")
            recomputeCounts(in: bucket)
            didChange = true
        }

        let deletedLegacyRows = try deleteLegacyRows(
            ownerID: ownerID,
            localDate: normalizedDate,
            ownerKey: ownerKey,
            legacyEntityName: legacyEntityName,
            in: context
        )

        let didTrimRanges: Bool
        if let owner, let ownerRelationshipKey, let rangeEntityName {
            didTrimRanges = try CoreDataHistoryRangeSupport.removeDates(
                owner: owner,
                ownerID: ownerID,
                dates: [normalizedDate],
                rangeEntityName: rangeEntityName,
                ownerKey: ownerKey,
                ownerRelationshipKey: ownerRelationshipKey,
                in: context,
                calendar: calendar,
                now: now
            )
        } else {
            didTrimRanges = false
        }

        return didChange || deletedLegacyRows || didTrimRanges
    }

    static func migrateLegacyRows(
        legacyEntityName: String,
        ownerEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        bucketEntityName: String,
        legacySourceToState: (String) -> CoreDataHistoryBucketState?,
        in context: NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: legacyEntityName)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let rows = try context.fetch(request)
        guard !rows.isEmpty else { return false }

        let ownerIDs = Set(rows.compactMap { $0.uuidValue(forKey: ownerKey) })
        let owners = try fetchOwners(entityName: ownerEntityName, ids: ownerIDs, in: context)

        for row in rows {
            guard
                let ownerID = row.uuidValue(forKey: ownerKey),
                let owner = owners[ownerID],
                let localDate = row.dateValue(forKey: "localDate"),
                let sourceRaw = row.stringValue(forKey: "sourceRaw"),
                let state = legacySourceToState(sourceRaw)
            else {
                context.delete(row)
                continue
            }

            _ = try setState(
                owner: owner,
                ownerID: ownerID,
                localDate: localDate,
                state: state,
                bucketEntityName: bucketEntityName,
                ownerKey: ownerKey,
                ownerRelationshipKey: ownerRelationshipKey,
                legacyEntityName: legacyEntityName,
                in: context,
                calendar: calendar,
                now: row.dateValue(forKey: "createdAt") ?? now
            )
        }

        return true
    }

    private static func makeSnapshot(
        bucketRows: [NSManagedObject],
        rangeRecords: [CoreDataHistoryRangeRecord],
        legacyRows: [NSManagedObject],
        legacySourceToState: (String) -> CoreDataHistoryBucketState?,
        calendar: Calendar
    ) -> CoreDataHistoryBucketSnapshot {
        var masksByYearMonth: [Int32: CoreDataHistoryBucketSnapshot.Masks] = [:]

        for row in bucketRows {
            let key = row.int32Value(forKey: "yearMonthKey")
            let incoming = CoreDataHistoryBucketSnapshot.Masks(
                positive: row.int64Value(forKey: "positiveMask") & validBitsMask,
                skipped: row.int64Value(forKey: "skippedMask") & validBitsMask,
                archived: row.int64Value(forKey: "archivedMask") & validBitsMask
            )

            if let existing = masksByYearMonth[key] {
                masksByYearMonth[key] = CoreDataHistoryBucketSnapshot.Masks(
                    positive: existing.positive | incoming.positive,
                    skipped: existing.skipped | incoming.skipped,
                    archived: existing.archived | incoming.archived
                )
            } else {
                masksByYearMonth[key] = incoming
            }
        }

        var legacyStatesByDay: [Date: (state: CoreDataHistoryBucketState, createdAt: Date)] = [:]

        for row in legacyRows {
            guard
                let localDate = row.dateValue(forKey: "localDate"),
                let sourceRaw = row.stringValue(forKey: "sourceRaw"),
                let state = legacySourceToState(sourceRaw),
                let createdAt = row.dateValue(forKey: "createdAt")
            else {
                continue
            }

            let normalizedDate = calendar.startOfDay(for: localDate)
            guard bucketState(on: normalizedDate, masksByYearMonth: masksByYearMonth, calendar: calendar) == nil else {
                continue
            }

            if let existing = legacyStatesByDay[normalizedDate], existing.createdAt >= createdAt {
                continue
            }
            legacyStatesByDay[normalizedDate] = (state, createdAt)
        }

        let legacyStates = legacyStatesByDay.mapValues(\.state)
        let positiveCount = masksByYearMonth.values.reduce(0) { $0 + $1.positive.nonzeroBitCount }
            + legacyStates.values.filter { $0 == .positive }.count
            + rangeRecords.filter { $0.state == .positive }.reduce(0) { $0 + $1.count }
        let skippedCount = masksByYearMonth.values.reduce(0) { $0 + $1.skipped.nonzeroBitCount }
            + legacyStates.values.filter { $0 == .skipped }.count
            + rangeRecords.filter { $0.state == .skipped }.reduce(0) { $0 + $1.count }
        let archivedCount = masksByYearMonth.values.reduce(0) { $0 + $1.archived.nonzeroBitCount }
            + legacyStates.values.filter { $0 == .archived }.count
            + rangeRecords.filter { $0.state == .archived }.reduce(0) { $0 + $1.count }

        return CoreDataHistoryBucketSnapshot(
            masksByYearMonth: masksByYearMonth,
            rangeRecords: rangeRecords,
            legacyStatesByDay: legacyStates,
            positiveCount: positiveCount,
            skippedCount: skippedCount,
            archivedCount: archivedCount
        )
    }

    private static func bucketState(
        on localDate: Date,
        masksByYearMonth: [Int32: CoreDataHistoryBucketSnapshot.Masks],
        calendar: Calendar
    ) -> CoreDataHistoryBucketState? {
        let normalizedDate = calendar.startOfDay(for: localDate)
        guard
            let masks = masksByYearMonth[yearMonthKey(for: normalizedDate, calendar: calendar)],
            let bit = bit(for: normalizedDate, calendar: calendar)
        else {
            return nil
        }

        if masks.positive & bit != 0 { return .positive }
        if masks.skipped & bit != 0 { return .skipped }
        if masks.archived & bit != 0 { return .archived }
        return nil
    }

    private static func entries(
        from bucket: NSManagedObject,
        ownerID: UUID,
        calendar: Calendar
    ) -> [CoreDataHistoryBucketEntry] {
        guard
            let id = bucket.uuidValue(forKey: "id"),
            let createdAt = bucket.dateValue(forKey: "createdAt")
        else {
            return []
        }

        let yearMonthKey = bucket.int32Value(forKey: "yearMonthKey")
        let positiveMask = bucket.int64Value(forKey: "positiveMask")
        let skippedMask = bucket.int64Value(forKey: "skippedMask")
        let archivedMask = bucket.int64Value(forKey: "archivedMask")
        var entries: [CoreDataHistoryBucketEntry] = []

        for day in 1...31 {
            let bit = Int64(1) << Int64(day - 1)
            let state: CoreDataHistoryBucketState?
            if positiveMask & bit != 0 {
                state = .positive
            } else if skippedMask & bit != 0 {
                state = .skipped
            } else if archivedMask & bit != 0 {
                state = .archived
            } else {
                state = nil
            }

            guard
                let state,
                let localDate = date(yearMonthKey: yearMonthKey, day: day, calendar: calendar)
            else {
                continue
            }

            entries.append(
                CoreDataHistoryBucketEntry(
                    id: id,
                    ownerID: ownerID,
                    localDate: localDate,
                    state: state,
                    createdAt: createdAt
                )
            )
        }

        return entries
    }

    nonisolated private static func isValidBucket(_ bucket: NSManagedObject) -> Bool {
        guard
            bucket.uuidValue(forKey: "id") != nil,
            bucket.dateValue(forKey: "createdAt") != nil,
            bucket.dateValue(forKey: "updatedAt") != nil
        else {
            return false
        }

        let positiveMask = bucket.int64Value(forKey: "positiveMask")
        let skippedMask = bucket.int64Value(forKey: "skippedMask")
        let archivedMask = bucket.int64Value(forKey: "archivedMask")
        guard
            positiveMask >= 0,
            skippedMask >= 0,
            archivedMask >= 0,
            positiveMask & ~validBitsMask == 0,
            skippedMask & ~validBitsMask == 0,
            archivedMask & ~validBitsMask == 0,
            positiveMask & skippedMask == 0,
            positiveMask & archivedMask == 0,
            skippedMask & archivedMask == 0
        else {
            return false
        }

        return bucket.int32Value(forKey: "positiveCount") == Int32(positiveMask.nonzeroBitCount)
            && bucket.int32Value(forKey: "skippedCount") == Int32(skippedMask.nonzeroBitCount)
            && bucket.int32Value(forKey: "archivedCount") == Int32(archivedMask.nonzeroBitCount)
    }

    nonisolated private static var validBitsMask: Int64 {
        Int64((UInt64(1) << UInt64(31)) - UInt64(1))
    }

    private static func state(
        in bucket: NSManagedObject,
        localDate: Date,
        calendar: Calendar
    ) -> CoreDataHistoryBucketState? {
        guard let bit = bit(for: localDate, calendar: calendar) else { return nil }
        if bucket.int64Value(forKey: "positiveMask") & bit != 0 { return .positive }
        if bucket.int64Value(forKey: "skippedMask") & bit != 0 { return .skipped }
        if bucket.int64Value(forKey: "archivedMask") & bit != 0 { return .archived }
        return nil
    }

    private static func fetchOrCreateBucket(
        owner: NSManagedObject,
        ownerID: UUID,
        localDate: Date,
        bucketEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        in context: NSManagedObjectContext,
        calendar: Calendar,
        now: Date
    ) throws -> NSManagedObject {
        try fetchOrCreateBucket(
            owner: owner,
            ownerID: ownerID,
            yearMonthKey: yearMonthKey(for: localDate, calendar: calendar),
            bucketEntityName: bucketEntityName,
            ownerKey: ownerKey,
            ownerRelationshipKey: ownerRelationshipKey,
            in: context,
            now: now
        )
    }

    private static func fetchOrCreateBucket(
        owner: NSManagedObject,
        ownerID: UUID,
        yearMonthKey key: Int32,
        bucketEntityName: String,
        ownerKey: String,
        ownerRelationshipKey: String,
        in context: NSManagedObjectContext,
        now: Date
    ) throws -> NSManagedObject {
        if let existing = try fetchBucket(
            entityName: bucketEntityName,
            ownerKey: ownerKey,
            ownerID: ownerID,
            yearMonthKey: key,
            in: context
        ) {
            return existing
        }

        let bucket = NSEntityDescription.insertNewObject(forEntityName: bucketEntityName, into: context)
        bucket.setValue(UUID(), forKey: "id")
        bucket.setValue(ownerID, forKey: ownerKey)
        bucket.setValue(key, forKey: "yearMonthKey")
        bucket.setValue(Int64(0), forKey: "positiveMask")
        bucket.setValue(Int64(0), forKey: "skippedMask")
        bucket.setValue(Int64(0), forKey: "archivedMask")
        bucket.setValue(Int32(0), forKey: "positiveCount")
        bucket.setValue(Int32(0), forKey: "skippedCount")
        bucket.setValue(Int32(0), forKey: "archivedCount")
        bucket.setValue(now, forKey: "createdAt")
        bucket.setValue(now, forKey: "updatedAt")
        bucket.setValue(owner, forKey: ownerRelationshipKey)
        return bucket
    }

    private static func fetchBucket(
        entityName: String,
        ownerKey: String,
        ownerID: UUID,
        yearMonthKey: Int32,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "\(ownerKey) == %@", ownerID as CVarArg),
            NSPredicate(format: "yearMonthKey == %d", yearMonthKey),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func fetchOwners(
        entityName: String,
        ids: Set<UUID>,
        in context: NSManagedObjectContext
    ) throws -> [UUID: NSManagedObject] {
        guard !ids.isEmpty else { return [:] }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        return Dictionary(uniqueKeysWithValues: try context.fetch(request).compactMap { object in
            guard let id = object.uuidValue(forKey: "id") else { return nil }
            return (id, object)
        })
    }

    private static func legacyState(
        ownerID: UUID,
        localDate: Date,
        ownerKey: String,
        legacyEntityName: String,
        legacySourceToState: (String) -> CoreDataHistoryBucketState?,
        in context: NSManagedObjectContext
    ) throws -> CoreDataHistoryBucketState? {
        let request = NSFetchRequest<NSManagedObject>(entityName: legacyEntityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "\(ownerKey) == %@", ownerID as CVarArg),
            NSPredicate(format: "localDate == %@", localDate as CVarArg),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request).compactMap { row in
            row.stringValue(forKey: "sourceRaw").flatMap(legacySourceToState)
        }.first
    }

    @discardableResult
    private static func deleteLegacyRows(
        ownerID: UUID,
        localDate: Date,
        ownerKey: String,
        legacyEntityName: String,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let rows = try CoreDataFetchSupport.fetchHistoryObjects(
            entityName: legacyEntityName,
            ownerKey: ownerKey,
            ownerID: ownerID,
            localDate: localDate,
            in: context
        )
        rows.forEach(context.delete)
        return !rows.isEmpty
    }

    @discardableResult
    private static func deleteLegacyRows(
        ownerID: UUID,
        yearMonthKey: Int32,
        mask: Int64,
        ownerKey: String,
        legacyEntityName: String,
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) throws -> Bool {
        var didDelete = false

        for day in 1...31 {
            let bit = Int64(1) << Int64(day - 1)
            guard mask & bit != 0, let localDate = date(yearMonthKey: yearMonthKey, day: day, calendar: calendar) else {
                continue
            }

            didDelete = try deleteLegacyRows(
                ownerID: ownerID,
                localDate: localDate,
                ownerKey: ownerKey,
                legacyEntityName: legacyEntityName,
                in: context
            ) || didDelete
        }

        return didDelete
    }

    private static func clearBit(
        for localDate: Date,
        in bucket: NSManagedObject,
        calendar: Calendar
    ) {
        guard let bit = bit(for: localDate, calendar: calendar) else { return }
        bucket.setValue(bucket.int64Value(forKey: "positiveMask") & ~bit, forKey: "positiveMask")
        bucket.setValue(bucket.int64Value(forKey: "skippedMask") & ~bit, forKey: "skippedMask")
        bucket.setValue(bucket.int64Value(forKey: "archivedMask") & ~bit, forKey: "archivedMask")
    }

    private static func setBit(
        for localDate: Date,
        state: CoreDataHistoryBucketState,
        in bucket: NSManagedObject,
        calendar: Calendar
    ) {
        guard let bit = bit(for: localDate, calendar: calendar) else { return }
        switch state {
        case .positive:
            bucket.setValue(bucket.int64Value(forKey: "positiveMask") | bit, forKey: "positiveMask")
        case .skipped:
            bucket.setValue(bucket.int64Value(forKey: "skippedMask") | bit, forKey: "skippedMask")
        case .archived:
            bucket.setValue(bucket.int64Value(forKey: "archivedMask") | bit, forKey: "archivedMask")
        }
    }

    private static func recomputeCounts(in bucket: NSManagedObject) {
        bucket.setValue(Int32(bucket.int64Value(forKey: "positiveMask").nonzeroBitCount), forKey: "positiveCount")
        bucket.setValue(Int32(bucket.int64Value(forKey: "skippedMask").nonzeroBitCount), forKey: "skippedCount")
        bucket.setValue(Int32(bucket.int64Value(forKey: "archivedMask").nonzeroBitCount), forKey: "archivedCount")
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

    nonisolated func int64Value(forKey key: String, default defaultValue: Int64 = 0) -> Int64 {
        value(forKey: key) as? Int64 ?? defaultValue
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
