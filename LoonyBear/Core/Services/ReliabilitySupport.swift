import CoreData
import Foundation
import OSLog

struct DataIntegrityIssue: Equatable, Sendable {
    let area: String
    let entityName: String
    let objectIdentifier: String
    let message: String

    nonisolated static func == (lhs: DataIntegrityIssue, rhs: DataIntegrityIssue) -> Bool {
        lhs.area == rhs.area &&
        lhs.entityName == rhs.entityName &&
        lhs.objectIdentifier == rhs.objectIdentifier &&
        lhs.message == rhs.message
    }
}

struct DataIntegrityReport: Equatable, Sendable {
    let issues: [DataIntegrityIssue]

    var isEmpty: Bool {
        issues.isEmpty
    }

    var summary: String {
        "\(issues.count) corrupted record(s) detected."
    }

    nonisolated static func == (lhs: DataIntegrityReport, rhs: DataIntegrityReport) -> Bool {
        lhs.issues == rhs.issues
    }
}

struct DataIntegrityError: LocalizedError, Equatable, Sendable {
    let operation: String
    let report: DataIntegrityReport

    var errorDescription: String? {
        "Data integrity problem during \(operation). \(report.summary)"
    }

    nonisolated static func == (lhs: DataIntegrityError, rhs: DataIntegrityError) -> Bool {
        lhs.operation == rhs.operation && lhs.report == rhs.report
    }
}

enum ReliabilityLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LoonyBear",
        category: "reliability"
    )

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

enum PerformanceLog {
    @discardableResult
    static func measure<T>(
        _ name: String,
        metadata: @autoclosure () -> String = "",
        operation: () throws -> T
    ) rethrows -> T {
        #if DEBUG
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            let formattedElapsed = String(format: "%.1f", elapsed)
            let resolvedMetadata = metadata()
            let suffix = resolvedMetadata.isEmpty ? "" : " \(resolvedMetadata)"
            ReliabilityLog.info("perf.\(name) \(formattedElapsed)ms\(suffix)")
        }
        #endif

        return try operation()
    }

    static func event(_ name: String, metadata: @autoclosure () -> String = "") {
        #if DEBUG
        let resolvedMetadata = metadata()
        let suffix = resolvedMetadata.isEmpty ? "" : " \(resolvedMetadata)"
        ReliabilityLog.info("perf.\(name)\(suffix)")
        #endif
    }

    @discardableResult
    static func measure<T>(
        _ name: String,
        metadata: @autoclosure () -> String = "",
        operation: () async throws -> T
    ) async rethrows -> T {
        #if DEBUG
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            let formattedElapsed = String(format: "%.1f", elapsed)
            let resolvedMetadata = metadata()
            let suffix = resolvedMetadata.isEmpty ? "" : " \(resolvedMetadata)"
            ReliabilityLog.info("perf.\(name) \(formattedElapsed)ms\(suffix)")
        }
        #endif

        return try await operation()
    }
}

struct IntegrityReportBuilder {
    private(set) var issues: [DataIntegrityIssue] = []

    var hasIssues: Bool {
        !issues.isEmpty
    }

    mutating func append(
        area: String,
        entityName: String,
        object: NSManagedObject,
        message: String
    ) {
        issues.append(
            DataIntegrityIssue(
                area: area,
                entityName: entityName,
                objectIdentifier: object.objectID.uriRepresentation().absoluteString,
                message: message
            )
        )
    }

    mutating func append(
        area: String,
        entityName: String,
        objectIdentifier: String,
        message: String
    ) {
        issues.append(
            DataIntegrityIssue(
                area: area,
                entityName: entityName,
                objectIdentifier: objectIdentifier,
                message: message
            )
        )
    }

    func makeError(operation: String) -> DataIntegrityError {
        DataIntegrityError(operation: operation, report: DataIntegrityReport(issues: issues))
    }

    mutating func append(report: DataIntegrityReport) {
        issues.append(contentsOf: report.issues)
    }
}

enum AppStartupHealthCheck {
    static func run(
        makeContext: @escaping () -> NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let context = makeContext()
        var thrownError: Error?

        context.performAndWait {
            do {
                try run(on: context, calendar: calendar)
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
    }

    private static func run(
        on context: NSManagedObjectContext,
        calendar: Calendar
    ) throws {
        var report = IntegrityReportBuilder()

        scanInvalidLegacyHistoryRows(
            entityName: "HabitCompletion",
            ownerKey: "habitID",
            area: "startup.habitHistory",
            sourceToState: habitBucketState(from:),
            context: context,
            report: &report
        )
        scanInvalidLegacyHistoryRows(
            entityName: "PillIntake",
            ownerKey: "pillID",
            area: "startup.pillHistory",
            sourceToState: pillBucketState(from:),
            context: context,
            report: &report
        )

        if report.hasIssues {
            let error = report.makeError(operation: "app.startup.healthCheck")
            ReliabilityLog.error("app.startup.healthCheck failed: \(error.localizedDescription)")
            throw error
        }

        try migrateLegacyHistoryRowsIfNeeded(context: context, calendar: calendar)

        validateHabitRows(context: context, calendar: calendar, report: &report)
        validatePillRows(context: context, calendar: calendar, report: &report)

        scanDuplicateHistoryRows(
            entityName: "HabitCompletion",
            ownerKey: "habitID",
            area: "startup.habitHistory",
            context: context,
            calendar: calendar,
            report: &report
        )
        scanDuplicateHistoryRows(
            entityName: "PillIntake",
            ownerKey: "pillID",
            area: "startup.pillHistory",
            context: context,
            calendar: calendar,
            report: &report
        )
        scanDuplicateHistoryBucketRows(
            entityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            area: "startup.habitHistoryBuckets",
            context: context,
            report: &report
        )
        scanDuplicateHistoryBucketRows(
            entityName: "PillHistoryBucket",
            ownerKey: "pillID",
            area: "startup.pillHistoryBuckets",
            context: context,
            report: &report
        )

        if report.hasIssues {
            let error = report.makeError(operation: "app.startup.healthCheck")
            ReliabilityLog.error("app.startup.healthCheck failed: \(error.localizedDescription)")
            throw error
        }

        ReliabilityLog.info("app.startup.healthCheck passed")
    }

    private static func scanInvalidLegacyHistoryRows(
        entityName: String,
        ownerKey: String,
        area: String,
        sourceToState: (String) -> CoreDataHistoryBucketState?,
        context: NSManagedObjectContext,
        report: inout IntegrityReportBuilder
    ) {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)

        do {
            for row in try context.fetch(request) {
                guard
                    row.uuidValue(forKey: ownerKey) != nil,
                    row.dateValue(forKey: "localDate") != nil,
                    let sourceRaw = row.stringValue(forKey: "sourceRaw"),
                    sourceToState(sourceRaw) != nil
                else {
                    report.append(
                        area: area,
                        entityName: entityName,
                        object: row,
                        message: "History row has invalid sourceRaw or missing required fields."
                    )
                    continue
                }
            }
        } catch {
            report.append(
                area: area,
                entityName: entityName,
                objectIdentifier: "fetch",
                message: "Unable to fetch legacy history rows: \(error.localizedDescription)"
            )
        }
    }

    private static func migrateLegacyHistoryRowsIfNeeded(
        context: NSManagedObjectContext,
        calendar: Calendar
    ) throws {
        let migratedHabitRows = try CoreDataHistoryBucketSupport.migrateLegacyRows(
            legacyEntityName: "HabitCompletion",
            ownerEntityName: "Habit",
            ownerKey: "habitID",
            ownerRelationshipKey: "habit",
            bucketEntityName: "HabitHistoryBucket",
            legacySourceToState: habitBucketState(from:),
            in: context,
            calendar: calendar
        )
        let migratedPillRows = try CoreDataHistoryBucketSupport.migrateLegacyRows(
            legacyEntityName: "PillIntake",
            ownerEntityName: "Pill",
            ownerKey: "pillID",
            ownerRelationshipKey: "pill",
            bucketEntityName: "PillHistoryBucket",
            legacySourceToState: pillBucketState(from:),
            in: context,
            calendar: calendar
        )

        if migratedHabitRows || migratedPillRows {
            try context.save()
            ReliabilityLog.info("app.startup.historyBucketMigration migrated legacy daily history")
        }
    }

    private static func validateHabitRows(
        context: NSManagedObjectContext,
        calendar: Calendar,
        report: inout IntegrityReportBuilder
    ) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")

        do {
            for object in try context.fetch(request) {
                guard
                    let habitID = object.uuidValue(forKey: "id"),
                    let typeRaw = object.stringValue(forKey: "typeRaw"),
                    HabitType(rawValue: typeRaw) != nil,
                    object.stringValue(forKey: "name") != nil,
                    object.dateValue(forKey: "startDate") != nil,
                    let historyModeRaw = object.stringValue(forKey: "historyModeRaw"),
                    HabitHistoryMode(rawValue: historyModeRaw) != nil
                else {
                    report.append(
                        area: "startup.habits",
                        entityName: object.entityName,
                        object: object,
                        message: "Habit row is missing required fields or contains invalid enum values."
                    )
                    continue
                }

                let reminderEnabled = object.boolValue(forKey: "reminderEnabled")
                let reminderTime = ReminderValidation.validatedReminderTime(
                    from: object,
                    reminderEnabled: reminderEnabled,
                    area: "startup.habits",
                    report: &report
                )
                guard !reminderEnabled || reminderTime != nil else {
                    continue
                }

                guard NotificationConfigurationSupport.loadLatestScheduleRule(
                    for: object,
                    relationshipKey: "scheduleVersions",
                    rowLabel: "Habit schedule",
                    invalidMaskMessage: "Habit reminder configuration contains invalid weekdayMask.",
                    report: &report
                ) != nil else {
                    continue
                }

                _ = NotificationConfigurationSupport.loadHistoryEntries(
                    for: object,
                    relationshipKey: "completions",
                    invalidEntryMessage: "Habit completion row is missing required fields or has invalid sourceRaw.",
                    calendar: calendar,
                    report: &report
                ) as [(Date, CompletionSource)]?

                _ = CoreDataHistoryBucketSupport.validatedEntries(
                    from: object,
                    relationshipKey: "historyBuckets",
                    area: "startup.habitHistoryBuckets",
                    invalidMessage: "Habit history bucket row is missing required fields or has overlapping masks.",
                    report: &report,
                    ownerID: habitID,
                    calendar: calendar
                )

                _ = CoreDataHistoryRangeSupport.validatedRecords(
                    from: object,
                    relationshipKey: "historyRanges",
                    ownerKey: "habitID",
                    area: "startup.habitHistoryRanges",
                    invalidMessage: "Habit history range row is missing required fields or has invalid schedule/count.",
                    report: &report,
                    ownerID: habitID,
                    calendar: calendar
                )
            }
        } catch {
            report.append(
                area: "startup.habits",
                entityName: "Habit",
                objectIdentifier: "Habit",
                message: "Failed to scan habit rows: \(error.localizedDescription)"
            )
        }
    }

    private static func validatePillRows(
        context: NSManagedObjectContext,
        calendar: Calendar,
        report: inout IntegrityReportBuilder
    ) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")

        do {
            for object in try context.fetch(request) {
                guard
                    let pillID = object.uuidValue(forKey: "id"),
                    object.stringValue(forKey: "name") != nil,
                    object.stringValue(forKey: "dosage") != nil,
                    object.dateValue(forKey: "startDate") != nil,
                    let historyModeRaw = object.stringValue(forKey: "historyModeRaw"),
                    PillHistoryMode(rawValue: historyModeRaw) != nil
                else {
                    report.append(
                        area: "startup.pills",
                        entityName: object.entityName,
                        object: object,
                        message: "Pill row is missing required fields or contains invalid enum values."
                    )
                    continue
                }

                let reminderEnabled = object.boolValue(forKey: "reminderEnabled")
                let reminderTime = ReminderValidation.validatedReminderTime(
                    from: object,
                    reminderEnabled: reminderEnabled,
                    area: "startup.pills",
                    report: &report
                )
                guard !reminderEnabled || reminderTime != nil else {
                    continue
                }

                guard NotificationConfigurationSupport.loadLatestScheduleRule(
                    for: object,
                    relationshipKey: "scheduleVersions",
                    rowLabel: "Pill schedule",
                    invalidMaskMessage: "Pill reminder configuration contains invalid weekdayMask.",
                    report: &report
                ) != nil else {
                    continue
                }

                _ = NotificationConfigurationSupport.loadHistoryEntries(
                    for: object,
                    relationshipKey: "intakes",
                    invalidEntryMessage: "Pill intake row is missing required fields or has invalid sourceRaw.",
                    calendar: calendar,
                    report: &report
                ) as [(Date, PillCompletionSource)]?

                _ = CoreDataHistoryBucketSupport.validatedEntries(
                    from: object,
                    relationshipKey: "historyBuckets",
                    area: "startup.pillHistoryBuckets",
                    invalidMessage: "Pill history bucket row is missing required fields or has overlapping masks.",
                    report: &report,
                    ownerID: pillID,
                    calendar: calendar
                )

                _ = CoreDataHistoryRangeSupport.validatedRecords(
                    from: object,
                    relationshipKey: "historyRanges",
                    ownerKey: "pillID",
                    area: "startup.pillHistoryRanges",
                    invalidMessage: "Pill history range row is missing required fields or has invalid schedule/count.",
                    report: &report,
                    ownerID: pillID,
                    calendar: calendar
                )
            }
        } catch {
            report.append(
                area: "startup.pills",
                entityName: "Pill",
                objectIdentifier: "Pill",
                message: "Failed to scan pill rows: \(error.localizedDescription)"
            )
        }
    }

    private static func scanDuplicateHistoryRows(
        entityName: String,
        ownerKey: String,
        area: String,
        context: NSManagedObjectContext,
        calendar: Calendar,
        report: inout IntegrityReportBuilder
    ) {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)

        do {
            let objects = try context.fetch(request)
            let groupedObjects = Dictionary(grouping: objects) { object -> String in
                let ownerIdentifier = object.uuidValue(forKey: ownerKey)?.uuidString ?? "missing-owner"
                let localDate = object.dateValue(forKey: "localDate")
                    .map { calendar.startOfDay(for: $0).formatted(.iso8601.year().month().day()) }
                    ?? "missing-date"
                return "\(ownerIdentifier)|\(localDate)"
            }

            for (groupKey, duplicates) in groupedObjects where duplicates.count > 1 {
                for duplicate in duplicates.dropFirst() {
                    report.append(
                        area: area,
                        entityName: duplicate.entityName,
                        object: duplicate,
                        message: "Duplicate history row detected for \(groupKey)."
                    )
                }
            }
        } catch {
            report.append(
                area: area,
                entityName: entityName,
                objectIdentifier: entityName,
                message: "Failed to scan history rows: \(error.localizedDescription)"
            )
        }
    }

    private static func scanDuplicateHistoryBucketRows(
        entityName: String,
        ownerKey: String,
        area: String,
        context: NSManagedObjectContext,
        report: inout IntegrityReportBuilder
    ) {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)

        do {
            let objects = try context.fetch(request)
            let groupedObjects = Dictionary(grouping: objects) { object -> String in
                let ownerIdentifier = object.uuidValue(forKey: ownerKey)?.uuidString ?? "missing-owner"
                return "\(ownerIdentifier)|\(object.int32Value(forKey: "yearMonthKey"))"
            }

            for (groupKey, duplicates) in groupedObjects where duplicates.count > 1 {
                for duplicate in duplicates.dropFirst() {
                    report.append(
                        area: area,
                        entityName: duplicate.entityName,
                        object: duplicate,
                        message: "Duplicate history bucket row detected for \(groupKey)."
                    )
                }
            }
        } catch {
            report.append(
                area: area,
                entityName: entityName,
                objectIdentifier: entityName,
                message: "Failed to scan history bucket rows: \(error.localizedDescription)"
            )
        }
    }

    private nonisolated static func habitBucketState(from sourceRaw: String) -> CoreDataHistoryBucketState? {
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

    private nonisolated static func pillBucketState(from sourceRaw: String) -> CoreDataHistoryBucketState? {
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
}

@MainActor
final class AppStartupHealthCheckCoordinator {
    private enum State {
        case idle
        case running
        case finished
    }

    private var state: State = .idle
    private let operation: () throws -> Void

    init(operation: @escaping () throws -> Void) {
        self.operation = operation
    }

    func runIfNeeded() async {
        guard state == .idle else { return }
        state = .running
        defer {
            state = .finished
        }

        do {
            let operation = self.operation
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try operation()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch let error as DataIntegrityError {
            ReliabilityLog.error(
                "app.startup.healthCheck reported integrity issues and launch will continue: \(error.localizedDescription)"
            )
        } catch {
            ReliabilityLog.error(
                "app.startup.healthCheck failed after launch: \(error.localizedDescription)"
            )
        }
    }
}

enum ReminderValidation {
    static func validatedReminderTime(
        from object: NSManagedObject,
        reminderEnabled: Bool,
        area: String,
        report: inout IntegrityReportBuilder,
        hourKey: String = "reminderHour",
        minuteKey: String = "reminderMinute"
    ) -> ReminderTime? {
        guard reminderEnabled else { return nil }

        guard let hourValue = object.value(forKey: hourKey) as? Int16 else {
            report.append(
                area: area,
                entityName: object.entityName,
                object: object,
                message: "\(hourKey) is required when reminderEnabled is true."
            )
            return nil
        }

        guard let minuteValue = object.value(forKey: minuteKey) as? Int16 else {
            report.append(
                area: area,
                entityName: object.entityName,
                object: object,
                message: "\(minuteKey) is required when reminderEnabled is true."
            )
            return nil
        }

        let hour = Int(hourValue)
        let minute = Int(minuteValue)

        guard (0...23).contains(hour) else {
            report.append(
                area: area,
                entityName: object.entityName,
                object: object,
                message: "\(hourKey) must be in 0...23."
            )
            return nil
        }

        guard (0...59).contains(minute) else {
            report.append(
                area: area,
                entityName: object.entityName,
                object: object,
                message: "\(minuteKey) must be in 0...59."
            )
            return nil
        }

        return ReminderTime(hour: hour, minute: minute)
    }
}

enum WeekdayValidation {
    private static let validMask = WeekdaySet.daily.rawValue

    static func isValidMask(_ rawValue: Int) -> Bool {
        rawValue >= 0 && (rawValue & ~validMask) == 0
    }
}
