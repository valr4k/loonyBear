import CoreData
import Foundation

@testable import LoonyBear

enum TestSupport {
    static func makeDate(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func makeSchedule(
        habitID: UUID,
        weekdays: WeekdaySet,
        effectiveFrom: Date,
        version: Int
    ) -> HabitScheduleVersion {
        HabitScheduleVersion(
            id: UUID(),
            habitID: habitID,
            weekdays: weekdays,
            effectiveFrom: effectiveFrom,
            createdAt: effectiveFrom,
            version: version
        )
    }

    static func makeSchedule(
        habitID: UUID,
        rule: ScheduleRule,
        effectiveFrom: Date,
        version: Int
    ) -> HabitScheduleVersion {
        HabitScheduleVersion(
            id: UUID(),
            habitID: habitID,
            rule: rule,
            effectiveFrom: effectiveFrom,
            createdAt: effectiveFrom,
            version: version
        )
    }

    static func makeCompletion(
        habitID: UUID,
        localDate: Date,
        source: CompletionSource = .manualEdit
    ) -> HabitCompletion {
        HabitCompletion(
            id: UUID(),
            habitID: habitID,
            localDate: localDate,
            source: source,
            createdAt: localDate
        )
    }

    static func habitBucketState(
        habitID: UUID,
        localDate: Date,
        context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> CoreDataHistoryBucketState? {
        try CoreDataHistoryBucketSupport.state(
            ownerID: habitID,
            localDate: localDate,
            bucketEntityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            legacyEntityName: "HabitCompletion",
            legacySourceToState: habitSourceToBucketState,
            in: context,
            calendar: calendar
        )
    }

    static func pillBucketState(
        pillID: UUID,
        localDate: Date,
        context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> CoreDataHistoryBucketState? {
        try CoreDataHistoryBucketSupport.state(
            ownerID: pillID,
            localDate: localDate,
            bucketEntityName: "PillHistoryBucket",
            ownerKey: "pillID",
            legacyEntityName: "PillIntake",
            legacySourceToState: pillSourceToBucketState,
            in: context,
            calendar: calendar
        )
    }

    @discardableResult
    static func clearHabitHistoryState(
        habitID: UUID,
        localDate: Date,
        context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> Bool {
        try CoreDataHistoryBucketSupport.clearState(
            ownerID: habitID,
            localDate: localDate,
            bucketEntityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            legacyEntityName: "HabitCompletion",
            in: context,
            calendar: calendar
        )
    }

    @discardableResult
    static func clearPillHistoryState(
        pillID: UUID,
        localDate: Date,
        context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> Bool {
        try CoreDataHistoryBucketSupport.clearState(
            ownerID: pillID,
            localDate: localDate,
            bucketEntityName: "PillHistoryBucket",
            ownerKey: "pillID",
            legacyEntityName: "PillIntake",
            in: context,
            calendar: calendar
        )
    }

    static func legacyHabitCompletionCount(
        habitID: UUID,
        localDate: Date? = nil,
        context: NSManagedObjectContext
    ) throws -> Int {
        try legacyHistoryCount(
            entityName: "HabitCompletion",
            ownerKey: "habitID",
            ownerID: habitID,
            localDate: localDate,
            context: context
        )
    }

    static func legacyPillIntakeCount(
        pillID: UUID,
        localDate: Date? = nil,
        context: NSManagedObjectContext
    ) throws -> Int {
        try legacyHistoryCount(
            entityName: "PillIntake",
            ownerKey: "pillID",
            ownerID: pillID,
            localDate: localDate,
            context: context
        )
    }

    static func habitHistoryBucketCount(
        habitID: UUID,
        context: NSManagedObjectContext
    ) throws -> Int {
        try historyRowCount(
            entityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            ownerID: habitID,
            context: context
        )
    }

    static func habitHistoryRangeCount(
        habitID: UUID,
        state: CoreDataHistoryBucketState? = nil,
        context: NSManagedObjectContext
    ) throws -> Int {
        try historyRowCount(
            entityName: "HabitHistoryRange",
            ownerKey: "habitID",
            ownerID: habitID,
            state: state,
            context: context
        )
    }

    static func pillHistoryBucketCount(
        pillID: UUID,
        context: NSManagedObjectContext
    ) throws -> Int {
        try historyRowCount(
            entityName: "PillHistoryBucket",
            ownerKey: "pillID",
            ownerID: pillID,
            context: context
        )
    }

    static func pillHistoryRangeCount(
        pillID: UUID,
        state: CoreDataHistoryBucketState? = nil,
        context: NSManagedObjectContext
    ) throws -> Int {
        try historyRowCount(
            entityName: "PillHistoryRange",
            ownerKey: "pillID",
            ownerID: pillID,
            state: state,
            context: context
        )
    }

    private static func habitSourceToBucketState(_ sourceRaw: String) -> CoreDataHistoryBucketState? {
        guard let source = CompletionSource(rawValue: sourceRaw) else { return nil }
        switch source {
        case .swipe, .manualEdit, .notification, .restore, .autoFill:
            return .positive
        case .skipped:
            return .skipped
        case .archived:
            return .archived
        }
    }

    private static func pillSourceToBucketState(_ sourceRaw: String) -> CoreDataHistoryBucketState? {
        guard let source = PillCompletionSource(rawValue: sourceRaw) else { return nil }
        switch source {
        case .swipe, .manualEdit, .notification, .restore:
            return .positive
        case .skipped:
            return .skipped
        case .archived:
            return .archived
        }
    }

    private static func legacyHistoryCount(
        entityName: String,
        ownerKey: String,
        ownerID: UUID,
        localDate: Date?,
        context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        var predicates = [NSPredicate(format: "%K == %@", ownerKey, ownerID as CVarArg)]
        if let localDate {
            predicates.append(NSPredicate(format: "localDate == %@", localDate as CVarArg))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try context.count(for: request)
    }

    private static func historyRowCount(
        entityName: String,
        ownerKey: String,
        ownerID: UUID,
        state: CoreDataHistoryBucketState? = nil,
        context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        var predicates = [NSPredicate(format: "%K == %@", ownerKey, ownerID as CVarArg)]
        if let state {
            predicates.append(NSPredicate(format: "stateRaw == %@", state.storageRaw))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try context.count(for: request)
    }
}
