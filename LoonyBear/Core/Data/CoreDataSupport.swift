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
        calendar: Calendar = .current
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
        calendar: Calendar = .current
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
        calendar: Calendar = .current
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
            return .skipped
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
        calendar: Calendar = .current
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

protocol HistoryScheduleVersionLike {
    var weekdays: WeekdaySet { get }
    var effectiveFrom: Date { get }
    var createdAt: Date { get }
    var version: Int { get }
}

extension HabitScheduleVersion: HistoryScheduleVersionLike {}
extension PillScheduleVersion: HistoryScheduleVersionLike {}

enum HistoryScheduleApplicability {
    static func pastEditableDays(
        in editableDays: Set<Date>,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<Date> {
        let normalizedToday = calendar.startOfDay(for: today)
        return Set(editableDays.map { calendar.startOfDay(for: $0) }.filter { $0 < normalizedToday })
    }

    static func pastScheduledEditableDays<Schedule: HistoryScheduleVersionLike>(
        in editableDays: Set<Date>,
        schedules: [Schedule],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<Date> {
        let pastEditableDays = pastEditableDays(in: editableDays, today: today, calendar: calendar)
        return Set(pastEditableDays.filter { day in
            guard let weekdays = effectiveWeekdays(on: day, from: schedules, calendar: calendar) else {
                return false
            }
            return weekdays.contains(calendar.weekdaySet(for: day))
        })
    }

    static func pastRequiredEditableDays<Schedule: HistoryScheduleVersionLike>(
        in editableDays: Set<Date>,
        schedules: [Schedule],
        historyMode: HabitHistoryMode,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<Date> {
        switch historyMode {
        case .scheduleBased:
            return pastScheduledEditableDays(
                in: editableDays,
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

    static func effectiveWeekdays<Schedule: HistoryScheduleVersionLike>(
        on day: Date,
        from schedules: [Schedule],
        calendar: Calendar = .current
    ) -> WeekdaySet? {
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
            .last { calendar.startOfDay(for: $0.effectiveFrom) <= normalizedDay }?
            .weekdays
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
}

extension NSManagedObject {
    var entityName: String {
        entity.name ?? "UnknownEntity"
    }

    func uuidValue(forKey key: String) -> UUID? {
        value(forKey: key) as? UUID
    }

    func stringValue(forKey key: String) -> String? {
        value(forKey: key) as? String
    }

    func dateValue(forKey key: String) -> Date? {
        value(forKey: key) as? Date
    }

    func boolValue(forKey key: String, default defaultValue: Bool = false) -> Bool {
        value(forKey: key) as? Bool ?? defaultValue
    }

    func int16Value(forKey key: String) -> Int {
        Int(value(forKey: key) as? Int16 ?? 0)
    }

    func int32Value(forKey key: String, default defaultValue: Int32 = 0) -> Int32 {
        value(forKey: key) as? Int32 ?? defaultValue
    }
}

extension Calendar {
    func weekdaySet(for date: Date) -> WeekdaySet {
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
