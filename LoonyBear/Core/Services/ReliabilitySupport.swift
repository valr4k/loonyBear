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
