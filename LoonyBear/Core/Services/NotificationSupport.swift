import CoreData
import Foundation
import UserNotifications

extension Notification.Name {
    static let habitStoreDidChange = Notification.Name("habit_store_did_change")
    static let pillStoreDidChange = Notification.Name("pill_store_did_change")
    static let openMyHabitsTab = Notification.Name("open_my_habits_tab")
    static let openMyPillsTab = Notification.Name("open_my_pills_tab")
}

enum NotificationMutationOutcome {
    case mutated
    case noChange
    case failed(Error)

    func merging(_ other: NotificationMutationOutcome) -> NotificationMutationOutcome {
        switch (self, other) {
        case (.failed, _):
            return self
        case (_, .failed):
            return other
        case (.mutated, _), (_, .mutated):
            return .mutated
        case (.noChange, .noChange):
            return .noChange
        }
    }
}

private final class NotificationRescheduleCoordinator {
    static let shared = NotificationRescheduleCoordinator()

    private struct State {
        var isRunning = false
        var needsRerun = false
        var pendingOperation: ((@escaping () -> Void) -> Void)?
        var completions: [() -> Void] = []
    }

    private let queue = DispatchQueue(label: "LoonyBear.NotificationRescheduleCoordinator")
    private var states: [String: State] = [:]

    func enqueue(
        key: String,
        completion: (() -> Void)?,
        operation: @escaping (@escaping () -> Void) -> Void
    ) {
        queue.async {
            var state = self.states[key] ?? State()
            if let completion {
                state.completions.append(completion)
            }

            if state.isRunning {
                state.needsRerun = true
                state.pendingOperation = operation
                self.states[key] = state
                return
            }

            state.isRunning = true
            self.states[key] = state
            self.startOperation(for: key, operation: operation)
        }
    }

    private func startOperation(
        for key: String,
        operation: @escaping (@escaping () -> Void) -> Void
    ) {
        operation { [weak self] in
            self?.queue.async {
                self?.finishOperation(for: key, operation: operation)
            }
        }
    }

    private func finishOperation(
        for key: String,
        operation: @escaping (@escaping () -> Void) -> Void
    ) {
        guard var state = states[key] else { return }

        if state.needsRerun {
            state.needsRerun = false
            let nextOperation = state.pendingOperation ?? operation
            state.pendingOperation = nil
            states[key] = state
            startOperation(for: key, operation: nextOperation)
            return
        }

        let completions = state.completions
        states.removeValue(forKey: key)

        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            completions.forEach { $0() }
        }
    }
}

struct NotificationStoreContext {
    let readContext: NSManagedObjectContext
    let makeWriteContext: () -> NSManagedObjectContext

    func performRead<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>?
        readContext.performAndWait {
            do {
                result = .success(try work(readContext))
            } catch {
                readContext.rollback()
                result = .failure(error)
            }
        }

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw DataIntegrityError(
                operation: "notification.performRead",
                report: DataIntegrityReport(issues: [])
            )
        }
    }

    func performWrite<T>(_ work: (NSManagedObjectContext) throws -> T, refreshReadContext: Bool = true) -> Result<T, Error> {
        let context = makeWriteContext()
        var result: Result<T, Error>?

        context.performAndWait {
            do {
                result = .success(try work(context))
            } catch {
                context.rollback()
                result = .failure(error)
            }
        }

        switch result {
        case .success(let value):
            if refreshReadContext {
                self.refreshReadContext()
            }
            return .success(value)
        case .failure(let error):
            return .failure(error)
        case .none:
            return .failure(
                DataIntegrityError(
                    operation: "notification.performWrite",
                    report: DataIntegrityReport(issues: [])
                )
            )
        }
    }

    func refreshReadContext() {
        readContext.performAndWait {
            readContext.refreshAllObjects()
        }
    }
}

enum LocalNotificationSupport {
    static func ensureAuthorizationIfNeeded(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }

    static func cleanupStaleDeliveredNotifications(
        center: UNUserNotificationCenter,
        calendar: Calendar,
        today: Date? = nil
    ) {
        let normalizedToday = calendar.startOfDay(for: today ?? Date())
        center.getDeliveredNotifications { notifications in
            let staleIdentifiers = notifications.compactMap { notification -> String? in
                let notificationDay = calendar.startOfDay(for: notification.date)
                return notificationDay < normalizedToday ? notification.request.identifier : nil
            }
            center.removeDeliveredNotifications(withIdentifiers: staleIdentifiers)
        }
    }

    static func removeDeliveredAggregatedNotifications(
        center: UNUserNotificationCenter,
        calendar: Calendar,
        type: String,
        on localDate: Date
    ) {
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                guard notification.request.content.userInfo["type"] as? String == type else {
                    return nil
                }

                let deliveredDay = calendar.startOfDay(for: notification.date)
                return deliveredDay == normalizedDay ? notification.request.identifier : nil
            }

            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    static func removePendingNotifications(
        center: UNUserNotificationCenter,
        prefix: String,
        completion: @escaping () -> Void
    ) {
        removePendingNotifications(
            center: center,
            matching: { $0.identifier.hasPrefix(prefix) },
            completion: completion
        )
    }

    static func removePendingNotifications(
        center: UNUserNotificationCenter,
        matching predicate: @escaping (UNNotificationRequest) -> Bool,
        completion: @escaping () -> Void
    ) {
        removePendingNotifications(
            center: center,
            matching: predicate,
            attemptsRemaining: 10,
            completion: completion
        )
    }

    private static func removePendingNotifications(
        center: UNUserNotificationCenter,
        matching predicate: @escaping (UNNotificationRequest) -> Bool,
        attemptsRemaining: Int,
        completion: @escaping () -> Void
    ) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter(predicate)
                .map(\.identifier)

            guard !identifiers.isEmpty else {
                completion()
                return
            }

            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.getPendingNotificationRequests { remainingRequests in
                let hasRemainingMatches = remainingRequests.contains(where: predicate)
                guard hasRemainingMatches, attemptsRemaining > 0 else {
                    completion()
                    return
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                    removePendingNotifications(
                        center: center,
                        matching: predicate,
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                }
            }
        }
    }

    static func timestampString(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d%02d%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    static func localDateIdentifier(for localDate: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: localDate))
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func parseLocalDateIdentifier(_ identifier: String, calendar: Calendar) -> Date? {
        guard identifier.count == 8 else { return nil }
        guard let year = Int(identifier.prefix(4)),
              let month = Int(identifier.dropFirst(4).prefix(2)),
              let day = Int(identifier.suffix(2)) else {
            return nil
        }

        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }

    static func deliveredNotificationLogicalDay(
        userInfo: [AnyHashable: Any],
        deliveryDate: Date,
        calendar: Calendar
    ) -> Date {
        guard let identifier = userInfo["localDate"] as? String,
              let parsedDate = parseLocalDateIdentifier(identifier, calendar: calendar) else {
            return calendar.startOfDay(for: deliveryDate)
        }

        return parsedDate
    }
}

enum NotificationResponseSupport {
    static func handleDefaultTapRouting(
        type: String,
        actionIdentifier: String,
        acceptedTypes: Set<String>,
        notificationName: Notification.Name
    ) -> Bool {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return false }
        guard acceptedTypes.contains(type) else { return false }

        let postSignal = {
            NotificationCenter.default.post(name: notificationName, object: nil)
        }
        if Thread.isMainThread {
            postSignal()
        } else {
            DispatchQueue.main.async(execute: postSignal)
        }
        return true
    }

    static func localDate(
        from userInfo: [AnyHashable: Any],
        fallbackDate: Date,
        calendar: Calendar
    ) -> Date {
        guard let identifier = userInfo["localDate"] as? String,
              let parsedDate = LocalNotificationSupport.parseLocalDateIdentifier(identifier, calendar: calendar) else {
            return calendar.startOfDay(for: fallbackDate)
        }

        return parsedDate
    }
}

enum NotificationCleanupSupport {
    private static let deliveredRemovalAttempts = 8
    private static let deliveredRemovalMinimumPasses = 2
    private static let deliveredRemovalRetryDelay: TimeInterval = 0.08

    struct DeliveredNotificationInfo {
        let identifier: String
        let userInfo: [AnyHashable: Any]
        let deliveryDate: Date
    }

    static func removeDeliveredNotifications(
        center: UNUserNotificationCenter,
        prefix: String
    ) {
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(prefix) }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    static func removeDeliveredNotifications(
        center: UNUserNotificationCenter,
        prefix: String,
        on localDate: Date,
        calendar: Calendar,
        including notificationIdentifier: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        removeDeliveredNotifications(
            center: center,
            prefix: prefix,
            on: localDate,
            calendar: calendar,
            including: notificationIdentifier,
            attemptsRemaining: deliveredRemovalAttempts,
            completedPasses: 0,
            completion: completion
        )
    }

    private static func removeDeliveredNotifications(
        center: UNUserNotificationCenter,
        prefix: String,
        on localDate: Date,
        calendar: Calendar,
        including notificationIdentifier: String?,
        attemptsRemaining: Int,
        completedPasses: Int,
        completion: (() -> Void)?
    ) {
        center.getDeliveredNotifications { notifications in
            let deliveredNotifications = deliveredNotificationInfos(from: notifications)
            let identifiers = deliveredNotificationIdentifiersToRemove(
                from: deliveredNotifications,
                prefix: prefix,
                on: localDate,
                calendar: calendar,
                including: notificationIdentifier
            )
            let matchingDeliveredIdentifiers = deliveredNotificationIdentifiersToRemove(
                from: deliveredNotifications,
                prefix: prefix,
                on: localDate,
                calendar: calendar
            )

            center.removeDeliveredNotifications(withIdentifiers: identifiers)

            let needsMinimumRetry = notificationIdentifier != nil &&
                completedPasses + 1 < deliveredRemovalMinimumPasses

            guard attemptsRemaining > 0, (!matchingDeliveredIdentifiers.isEmpty || needsMinimumRetry) else {
                completion?()
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + deliveredRemovalRetryDelay) {
                center.getDeliveredNotifications { remainingNotifications in
                    let remainingIdentifiers = deliveredNotificationIdentifiersToRemove(
                        from: deliveredNotificationInfos(from: remainingNotifications),
                        prefix: prefix,
                        on: localDate,
                        calendar: calendar
                    )

                    guard needsMinimumRetry || !remainingIdentifiers.isEmpty else {
                        completion?()
                        return
                    }

                    if attemptsRemaining == 1, !remainingIdentifiers.isEmpty {
                        ReliabilityLog.error(
                            "notification.delivered.cleanup still has \(remainingIdentifiers.count) item(s)"
                        )
                    }

                    removeDeliveredNotifications(
                        center: center,
                        prefix: prefix,
                        on: localDate,
                        calendar: calendar,
                        including: notificationIdentifier,
                        attemptsRemaining: attemptsRemaining - 1,
                        completedPasses: completedPasses + 1,
                        completion: completion
                    )
                }
            }
        }
    }

    static func deliveredNotificationIdentifiersToRemove(
        from notifications: [DeliveredNotificationInfo],
        prefix: String,
        on localDate: Date,
        calendar: Calendar,
        including notificationIdentifier: String? = nil
    ) -> [String] {
        let normalizedDay = calendar.startOfDay(for: localDate)
        var identifiers = Set<String>()

        for notification in notifications where notification.identifier.hasPrefix(prefix) {
            let deliveredDay = LocalNotificationSupport.deliveredNotificationLogicalDay(
                userInfo: notification.userInfo,
                deliveryDate: notification.deliveryDate,
                calendar: calendar
            )
            if deliveredDay == normalizedDay {
                identifiers.insert(notification.identifier)
            }
        }

        if let notificationIdentifier, notificationIdentifier.hasPrefix(prefix) {
            identifiers.insert(notificationIdentifier)
        }

        return Array(identifiers)
    }

    private static func deliveredNotificationInfos(
        from notifications: [UNNotification]
    ) -> [DeliveredNotificationInfo] {
        notifications.map {
            DeliveredNotificationInfo(
                identifier: $0.request.identifier,
                userInfo: $0.request.content.userInfo,
                deliveryDate: $0.date
            )
        }
    }

    static func removePendingNotifications(
        center: UNUserNotificationCenter,
        prefix: String,
        on localDate: Date,
        calendar: Calendar
    ) {
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getPendingNotificationRequests { requests in
            let identifiers = requests.compactMap { request -> String? in
                guard request.identifier.hasPrefix(prefix) else { return nil }
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
                guard let triggerDate = trigger.nextTriggerDate() else { return nil }

                let triggerDay = calendar.startOfDay(for: triggerDate)
                return triggerDay == normalizedDay ? request.identifier : nil
            }

            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
}

enum NotificationRescheduleSupport {
    private static let coordinator = NotificationRescheduleCoordinator.shared

    static func rescheduleAll(
        center: UNUserNotificationCenter,
        storeContext: NotificationStoreContext,
        logName: String,
        now: @escaping () -> Date,
        removeDeliveredAggregatedNotifications: @escaping (Date) -> Void,
        removePendingNotifications: @escaping (@escaping () -> Void) -> Void,
        makePendingRequests: @escaping () throws -> [UNNotificationRequest],
        completion: (() -> Void)? = nil
    ) {
        coordinator.enqueue(key: logName, completion: completion) { finish in
            performReschedule(
                center: center,
                storeContext: storeContext,
                logName: logName,
                now: now,
                removeDeliveredAggregatedNotifications: removeDeliveredAggregatedNotifications,
                removePendingNotifications: removePendingNotifications,
                makePendingRequests: makePendingRequests,
                completion: finish
            )
        }
    }

    private static func performReschedule(
        center: UNUserNotificationCenter,
        storeContext: NotificationStoreContext,
        logName: String,
        now: @escaping () -> Date,
        removeDeliveredAggregatedNotifications: @escaping (Date) -> Void,
        removePendingNotifications: @escaping (@escaping () -> Void) -> Void,
        makePendingRequests: @escaping () throws -> [UNNotificationRequest],
        completion: @escaping () -> Void
    ) {
        ReliabilityLog.info("\(logName) started")
        removeDeliveredAggregatedNotifications(now())
        storeContext.refreshReadContext()

        do {
            let requests = try makePendingRequests()
            removePendingNotifications {
                guard !requests.isEmpty else {
                    ReliabilityLog.info("\(logName) finished with 0 request(s)")
                    completion()
                    return
                }

                let group = DispatchGroup()
                for request in requests {
                    group.enter()
                    center.add(request) { error in
                        if let error {
                            ReliabilityLog.error(
                                "\(logName) request \(request.identifier) failed: \(error.localizedDescription)"
                            )
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    ReliabilityLog.info("\(logName) finished with \(requests.count) request(s)")
                    completion()
                }
            }
        } catch let error as DataIntegrityError {
            ReliabilityLog.error("\(logName) failed: \(error.localizedDescription)")
            completion()
        } catch {
            ReliabilityLog.error("\(logName) failed: \(error.localizedDescription)")
            completion()
        }
    }
}

enum NotificationConfigurationSupport {
    static func fetchConfigurations<Configuration>(
        entityName: String,
        operation: String,
        context: NSManagedObjectContext,
        build: (NSManagedObject, inout IntegrityReportBuilder) -> Configuration?
    ) throws -> [Configuration] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let objects = try context.fetch(request)
        var report = IntegrityReportBuilder()
        var configurations: [Configuration] = []

        for object in objects {
            if let configuration = build(object, &report) {
                configurations.append(configuration)
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: operation)
        }

        return configurations
    }

    static func loadLatestScheduleRule(
        for object: NSManagedObject,
        relationshipKey: String,
        rowLabel: String,
        invalidMaskMessage: String,
        report: inout IntegrityReportBuilder
    ) -> ScheduleRule? {
        let schedules = (object.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        let validatedSchedules = schedules.compactMap { schedule -> (Date, Int32, Date, ScheduleRule)? in
            guard
                let effectiveFrom = schedule.dateValue(forKey: "effectiveFrom"),
                let createdAt = schedule.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: "notification",
                    entityName: schedule.entityName,
                    object: schedule,
                    message: "\(rowLabel) row is missing required fields."
                )
                return nil
            }

            guard let rule = CoreDataScheduleSupport.rule(from: schedule) else {
                report.append(
                    area: "notification",
                    entityName: schedule.entityName,
                    object: schedule,
                    message: invalidMaskMessage
                )
                return nil
            }

            return (
                effectiveFrom,
                schedule.int32Value(forKey: "version", default: 1),
                createdAt,
                rule
            )
        }

        guard validatedSchedules.count == schedules.count else { return nil }
        guard let latest = validatedSchedules.max(by: {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 < $1.2
        }) else {
            return .weekly(WeekdaySet(rawValue: 0))
        }

        return latest.3
    }

    static func loadHistoryEntries<Source: RawRepresentable>(
        for object: NSManagedObject,
        relationshipKey: String,
        invalidEntryMessage: String,
        calendar: Calendar,
        report: inout IntegrityReportBuilder
    ) -> [(Date, Source)]? where Source.RawValue == String {
        let rows = (object.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        var entries: [(Date, Source)] = []

        for row in rows {
            guard
                let localDate = row.dateValue(forKey: "localDate"),
                let sourceRaw = row.stringValue(forKey: "sourceRaw"),
                let source = Source(rawValue: sourceRaw)
            else {
                report.append(
                    area: "notification",
                    entityName: row.entityName,
                    object: row,
                    message: invalidEntryMessage
                )
                return nil
            }

            entries.append((calendar.startOfDay(for: localDate), source))
        }

        return entries
    }
}
