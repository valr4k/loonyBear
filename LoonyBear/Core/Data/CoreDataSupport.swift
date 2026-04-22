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

enum HistoryMonthWindow {
    static func months(
        containing dates: Set<Date>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let months = Set(
            dates.compactMap { date in
                calendar.date(from: calendar.dateComponents([.year, .month], from: date))
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
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: normalizedStart)) ?? normalizedStart
        let lastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: normalizedEnd)) ?? normalizedEnd

        while cursor <= lastMonth {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return months
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
        return earliest ... normalizedToday
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
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        let normalizedToday = calendar.startOfDay(for: today)
        return Set(editableDays.map { calendar.startOfDay(for: $0) }.filter { $0 < normalizedToday })
    }

    static func pastScheduledEditableDays<Schedule: HistoryScheduleVersionLike>(
        in editableDays: Set<Date>,
        schedules: [Schedule],
        today: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
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
        calendar: Calendar = .autoupdatingCurrent
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
        calendar: Calendar = .autoupdatingCurrent
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

    static func isNewerSchedule<Schedule: HistoryScheduleVersionLike>(_ lhs: Schedule, _ rhs: Schedule) -> Bool {
        if lhs.effectiveFrom != rhs.effectiveFrom {
            return lhs.effectiveFrom > rhs.effectiveFrom
        }
        if lhs.version != rhs.version {
            return lhs.version > rhs.version
        }
        return lhs.createdAt > rhs.createdAt
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
        makeModel: (UUID, Int, Date, Date, Int) -> Model
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

            return makeModel(
                id,
                row.int16Value(forKey: "weekdayMask"),
                effectiveFrom,
                createdAt,
                Int(row.int32Value(forKey: "version", default: 1))
            )
        }
    }

    static func validatedScheduleModels<Model>(
        from ownerObject: NSManagedObject,
        relationshipKey: String,
        area: String,
        missingFieldsMessage: String,
        invalidMaskMessage: String,
        report: inout IntegrityReportBuilder,
        makeModel: (UUID, Int, Date, Date, Int) -> Model
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

            let weekdayMask = row.int16Value(forKey: "weekdayMask")
            guard WeekdayValidation.isValidMask(weekdayMask) else {
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
                    weekdayMask,
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
