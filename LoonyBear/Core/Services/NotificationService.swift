import CoreData
import Foundation
import UIKit
import UserNotifications

private enum NotificationServiceError: Error {
    case habitNotFound
}

final class NotificationService {
    private let categoryIdentifier = "habit.reminder"
    private let summaryCategoryIdentifier = "habit.reminder.summary"
    private let completeActionIdentifier = "habit.complete"
    private let skipActionIdentifier = "habit.skip"
    private let schedulingWindowDays = 2
    private let aggregationThreshold = 3
    private let storeContext: NotificationStoreContext
    private let center = UNUserNotificationCenter.current()

    private var calendar: Calendar {
        .autoupdatingCurrent
    }

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext
    ) {
        storeContext = NotificationStoreContext(
            readContext: context,
            makeWriteContext: makeWriteContext
        )
    }

    func ensureAuthorizationIfNeeded() async -> Bool {
        await LocalNotificationSupport.ensureAuthorizationIfNeeded(center: center)
    }

    func prepareReminderNotifications(forHabitID habitID: UUID) async {
        if await ensureAuthorizationIfNeeded() {
            rescheduleAllNotifications()
        }
    }

    func notificationCategories() -> [UNNotificationCategory] {
        let completeAction = UNNotificationAction(
            identifier: completeActionIdentifier,
            title: "Mark as Completed",
            options: []
        )
        let skipAction = UNNotificationAction(
            identifier: skipActionIdentifier,
            title: "Mark as Skipped",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [completeAction, skipAction],
            intentIdentifiers: [],
            options: []
        )

        let summaryCategory = UNNotificationCategory(
            identifier: summaryCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        return [category, summaryCategory]
    }

    func rescheduleNotifications(forHabitID habitID: UUID) {
        rescheduleAllNotifications()
    }

    func rescheduleAllNotifications() {
        ReliabilityLog.info("notification.habit.reschedule started")
        removeDeliveredAggregatedNotifications(on: Date())
        storeContext.refreshReadContext()
        do {
            let requests = try makePendingNotificationRequests()
            removePendingHabitNotifications {
                for request in requests {
                    self.center.add(request) { error in
                        if let error {
                            ReliabilityLog.error(
                                "notification.habit.reschedule request \(request.identifier) failed: \(error.localizedDescription)"
                            )
                        }
                    }
                }
                ReliabilityLog.info("notification.habit.reschedule finished with \(requests.count) request(s)")
            }
        } catch let error as DataIntegrityError {
            ReliabilityLog.error("notification.habit.reschedule failed: \(error.localizedDescription)")
        } catch {
            ReliabilityLog.error("notification.habit.reschedule failed: \(error.localizedDescription)")
        }
    }

    func removePendingNotification(forHabitID habitID: UUID, on localDate: Date) {
        let prefix = notificationIdentifierPrefix(for: habitID)
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getPendingNotificationRequests { requests in
            let identifiers = requests.compactMap { request -> String? in
                guard request.identifier.hasPrefix(prefix) else { return nil }
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
                guard let triggerDate = trigger.nextTriggerDate() else { return nil }

                let triggerDay = self.calendar.startOfDay(for: triggerDate)
                return triggerDay == normalizedDay ? request.identifier : nil
            }

            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func removeNotifications(forHabitID habitID: UUID) {
        rescheduleAllNotifications()
        removeDeliveredNotifications(forHabitID: habitID)
    }

    func removeDeliveredNotifications(forHabitID habitID: UUID) {
        let prefix = notificationIdentifierPrefix(for: habitID)
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(prefix) }
            self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    func removeDeliveredNotifications(forHabitID habitID: UUID, on localDate: Date) {
        let prefix = notificationIdentifierPrefix(for: habitID)
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                guard notification.request.identifier.hasPrefix(prefix) else {
                    return nil
                }

                let deliveredDay = self.calendar.startOfDay(for: notification.date)
                return deliveredDay == normalizedDay ? notification.request.identifier : nil
            }

            self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    func removeDeliveredAggregatedNotifications(on localDate: Date) {
        LocalNotificationSupport.removeDeliveredAggregatedNotifications(
            center: center,
            calendar: calendar,
            type: "aggregated",
            on: localDate
        )
    }

    func handleAppDidBecomeActive() {
        rescheduleAllNotifications()
        cleanupStaleDeliveredNotifications()
    }

    @discardableResult
    func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard
            let type = response.notification.request.content.userInfo["type"] as? String
        else {
            return false
        }

        return handleNotificationResponse(
            type: type,
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier,
            notificationDate: response.notification.date
        )
    }

    @discardableResult
    func handleNotificationResponse(
        type: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        notificationDate: Date
    ) -> Bool {
        if handleDefaultTapRouting(type: type, actionIdentifier: actionIdentifier) {
            return true
        }

        guard
            let habitIDString = userInfo["habitID"] as? String,
            let habitID = UUID(uuidString: habitIDString)
        else {
            return true
        }

        let deliveryDay = localDate(from: userInfo, fallbackDate: notificationDate)
        let didMutateStore: Bool
        switch actionIdentifier {
        case completeActionIdentifier:
            didMutateStore = createCompletionIfNeeded(for: habitID, on: deliveryDay, source: .notification)
        case skipActionIdentifier:
            didMutateStore = createSkippedCompletionIfNeeded(for: habitID, on: deliveryDay)
        default:
            return true
        }

        removeDeliveredNotifications(forHabitID: habitID, on: deliveryDay)
        if didMutateStore {
            rescheduleAllNotifications()
        }
        return true
    }

    @discardableResult
    func handleDefaultTapRouting(type: String, actionIdentifier: String) -> Bool {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return false }
        guard type == "aggregated" || type == "individual" else { return false }

        let postSignal = {
            NotificationCenter.default.post(name: .openMyHabitsTab, object: nil)
        }
        if Thread.isMainThread {
            postSignal()
        } else {
            DispatchQueue.main.async(execute: postSignal)
        }
        return true
    }

    private func cleanupStaleDeliveredNotifications() {
        LocalNotificationSupport.cleanupStaleDeliveredNotifications(center: center, calendar: calendar)
    }

    private func localDate(from userInfo: [AnyHashable: Any], fallbackDate: Date) -> Date {
        guard let identifier = userInfo["localDate"] as? String,
              let parsedDate = LocalNotificationSupport.parseLocalDateIdentifier(identifier, calendar: calendar) else {
            return calendar.startOfDay(for: fallbackDate)
        }

        return parsedDate
    }

    private func reminderCandidates(for reminder: HabitReminderConfiguration) -> [ScheduledHabitReminderCandidate] {
        guard reminder.reminderEnabled, let reminderTime = reminder.reminderTime else { return [] }
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let normalizedStartDate = calendar.startOfDay(for: reminder.startDate)

        return (0 ..< schedulingWindowDays).compactMap { offset in
            guard let localDay = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }

            let normalizedDay = calendar.startOfDay(for: localDay)
            guard normalizedDay >= normalizedStartDate else { return nil }
            guard reminder.scheduleDays.contains(calendar.weekdaySet(for: normalizedDay)) else { return nil }
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

            return ScheduledHabitReminderCandidate(
                habitID: reminder.id,
                habitName: reminder.name,
                localDate: normalizedDay,
                scheduledDateTime: scheduledDateTime
            )
        }
    }

    private func notificationRequests(
        for candidates: [ScheduledHabitReminderCandidate],
        habits: [HabitReminderConfiguration],
        pills: [PillReminderConfiguration]
    ) -> [UNNotificationRequest] {
        guard let firstCandidate = candidates.first else { return [] }
        let projectedBadgeCount = ProjectedBadgeCountCalculator.projectedOverdueCount(
            at: firstCandidate.scheduledDateTime,
            habits: habits,
            pills: pills,
            calendar: calendar
        )

        if candidates.count < aggregationThreshold {
            return candidates.map { makeIndividualNotificationRequest(for: $0, projectedBadgeCount: projectedBadgeCount) }
        }

        return [
            makeAggregatedNotificationRequest(
                for: candidates,
                scheduledDateTime: firstCandidate.scheduledDateTime,
                projectedBadgeCount: projectedBadgeCount
            ),
        ]
    }

    func makePendingNotificationRequests() throws -> [UNNotificationRequest] {
        let habits = try storeContext.performRead(fetchHabitReminderConfigurations)
        let pills = try storeContext.performRead(fetchPillReminderConfigurations)
        let candidates = habits.flatMap(reminderCandidates(for:))
        let groupedCandidates = Dictionary(grouping: candidates, by: \.scheduledDateTime)

        return groupedCandidates.values.flatMap { group in
            notificationRequests(for: group, habits: habits, pills: pills)
        }
    }

    private func loadHabit(id: UUID) throws -> HabitReminderConfiguration {
        try storeContext.performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let object = try context.fetch(request).first else {
                throw NotificationServiceError.habitNotFound
            }

            var report = IntegrityReportBuilder()
            guard let configuration = makeReminderConfiguration(from: object, report: &report) else {
                throw report.makeError(operation: "notification.loadHabit")
            }

            if report.hasIssues {
                throw report.makeError(operation: "notification.loadHabit")
            }

            return configuration
        }
    }

    private func fetchHabitReminderConfigurations(context: NSManagedObjectContext) throws -> [HabitReminderConfiguration] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        let objects = try context.fetch(request)
        var report = IntegrityReportBuilder()
        var configurations: [HabitReminderConfiguration] = []

        for object in objects {
            if let configuration = makeReminderConfiguration(from: object, report: &report) {
                configurations.append(configuration)
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: "notification.fetchHabitReminderConfigurations")
        }

        return configurations
    }

    private func fetchPillReminderConfigurations(context: NSManagedObjectContext) throws -> [PillReminderConfiguration] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        let objects = try context.fetch(request)
        var report = IntegrityReportBuilder()
        var configurations: [PillReminderConfiguration] = []

        for object in objects {
            if let configuration = makePillReminderConfiguration(from: object, report: &report) {
                configurations.append(configuration)
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: "notification.fetchPillReminderConfigurations")
        }

        return configurations
    }

    private func makeReminderConfiguration(
        from object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> HabitReminderConfiguration? {
        guard
            let id = object.uuidValue(forKey: "id"),
            let name = object.stringValue(forKey: "name"),
            let startDate = object.dateValue(forKey: "startDate")
        else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Habit reminder row is missing required fields."
            )
            return nil
        }

        guard let scheduleDays = loadHabitScheduleDays(for: object, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Habit reminder configuration failed because schedule rows are corrupted."
            )
            return nil
        }

        let reminderEnabled = object.boolValue(forKey: "reminderEnabled")
        let reminderTime = ReminderValidation.validatedReminderTime(
            from: object,
            reminderEnabled: reminderEnabled,
            area: "notification",
            report: &report
        )
        guard !reminderEnabled || reminderTime != nil else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Habit reminder configuration failed because reminder fields are corrupted."
            )
            return nil
        }
        guard let completionEntries = loadHabitCompletionEntries(for: object, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Habit reminder configuration failed because completion rows are corrupted."
            )
            return nil
        }
        let completedDays = Set(completionEntries.compactMap { $0.1.countsAsCompletion ? $0.0 : nil })
        let skippedDays = Set(completionEntries.compactMap { !$0.1.countsAsCompletion ? $0.0 : nil })

        return HabitReminderConfiguration(
            id: id,
            name: name,
            startDate: startDate,
            scheduleDays: scheduleDays,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            completedDays: completedDays,
            skippedDays: skippedDays
        )
    }

    private func makePillReminderConfiguration(
        from object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> PillReminderConfiguration? {
        guard
            let id = object.uuidValue(forKey: "id"),
            let name = object.stringValue(forKey: "name"),
            let dosage = object.stringValue(forKey: "dosage"),
            let startDate = object.dateValue(forKey: "startDate")
        else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Pill reminder row is missing required fields."
            )
            return nil
        }

        let reminderEnabled = object.boolValue(forKey: "reminderEnabled")
        let reminderTime = ReminderValidation.validatedReminderTime(
            from: object,
            reminderEnabled: reminderEnabled,
            area: "notification",
            report: &report
        )
        guard !reminderEnabled || reminderTime != nil else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Pill reminder configuration failed because reminder fields are corrupted."
            )
            return nil
        }
        guard let scheduleDays = loadPillScheduleDays(for: object, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Pill reminder configuration failed because schedule rows are corrupted."
            )
            return nil
        }
        guard let intakeEntries = loadPillIntakeEntries(for: object, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Pill reminder configuration failed because intake rows are corrupted."
            )
            return nil
        }
        let takenDays = Set(intakeEntries.compactMap { $0.1.countsAsIntake ? $0.0 : nil })
        let skippedDays = Set(intakeEntries.compactMap { !$0.1.countsAsIntake ? $0.0 : nil })

        return PillReminderConfiguration(
            id: id,
            name: name,
            dosage: dosage,
            startDate: startDate,
            scheduleDays: scheduleDays,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            takenDays: takenDays,
            skippedDays: skippedDays
        )
    }

    private func loadHabitScheduleDays(
        for object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> WeekdaySet? {
        let schedules = (object.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        let validatedSchedules = schedules.compactMap { schedule -> (Date, Int32, Date, Int)? in
            guard
                let effectiveFrom = schedule.dateValue(forKey: "effectiveFrom"),
                let createdAt = schedule.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: "notification",
                    entityName: schedule.entityName,
                    object: schedule,
                    message: "Habit schedule row is missing required fields."
                )
                return nil
            }

            return (
                effectiveFrom,
                schedule.int32Value(forKey: "version", default: 1),
                createdAt,
                Int(schedule.int16Value(forKey: "weekdayMask"))
            )
        }

        guard validatedSchedules.count == schedules.count else { return nil }
        guard let latest = validatedSchedules.max(by: {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 < $1.2
        }) else {
            return WeekdaySet(rawValue: 0)
        }
        guard WeekdayValidation.isValidMask(latest.3) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Habit reminder configuration contains invalid weekdayMask."
            )
            return nil
        }
        return WeekdaySet(rawValue: latest.3)
    }

    private func loadPillScheduleDays(
        for object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> WeekdaySet? {
        let schedules = (object.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        let validatedSchedules = schedules.compactMap { schedule -> (Date, Int32, Date, Int)? in
            guard
                let effectiveFrom = schedule.dateValue(forKey: "effectiveFrom"),
                let createdAt = schedule.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: "notification",
                    entityName: schedule.entityName,
                    object: schedule,
                    message: "Pill schedule row is missing required fields."
                )
                return nil
            }

            return (
                effectiveFrom,
                schedule.int32Value(forKey: "version", default: 1),
                createdAt,
                Int(schedule.int16Value(forKey: "weekdayMask"))
            )
        }

        guard validatedSchedules.count == schedules.count else { return nil }
        guard let latest = validatedSchedules.max(by: {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 < $1.2
        }) else {
            return WeekdaySet(rawValue: 0)
        }
        guard WeekdayValidation.isValidMask(latest.3) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Pill reminder configuration contains invalid weekdayMask."
            )
            return nil
        }
        return WeekdaySet(rawValue: latest.3)
    }

    private func loadHabitCompletionEntries(
        for object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> [(Date, CompletionSource)]? {
        let completions = (object.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
        var entries: [(Date, CompletionSource)] = []

        for completion in completions {
            guard
                let localDate = completion.dateValue(forKey: "localDate"),
                let sourceRaw = completion.stringValue(forKey: "sourceRaw"),
                let source = CompletionSource(rawValue: sourceRaw)
            else {
                report.append(
                    area: "notification",
                    entityName: completion.entityName,
                    object: completion,
                    message: "Habit completion row is missing required fields or has invalid sourceRaw."
                )
                return nil
            }

            entries.append((calendar.startOfDay(for: localDate), source))
        }

        return entries
    }

    private func loadPillIntakeEntries(
        for object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> [(Date, PillCompletionSource)]? {
        let intakes = (object.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
        var entries: [(Date, PillCompletionSource)] = []

        for intake in intakes {
            guard
                let localDate = intake.dateValue(forKey: "localDate"),
                let sourceRaw = intake.stringValue(forKey: "sourceRaw"),
                let source = PillCompletionSource(rawValue: sourceRaw)
            else {
                report.append(
                    area: "notification",
                    entityName: intake.entityName,
                    object: intake,
                    message: "Pill intake row is missing required fields or has invalid sourceRaw."
                )
                return nil
            }

            entries.append((calendar.startOfDay(for: localDate), source))
        }

        return entries
    }

    @discardableResult
    private func createCompletionIfNeeded(for habitID: UUID, on localDate: Date, source: CompletionSource) -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let didCreate = storeContext.performWrite({ context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "habitID == %@", habitID as CVarArg),
                NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
            ])
            fetchRequest.fetchLimit = 1

            if let existing = try context.fetch(fetchRequest).first {
                guard
                    let sourceRaw = existing.value(forKey: "sourceRaw") as? String,
                    let existingSource = CompletionSource(rawValue: sourceRaw)
                else {
                    return false
                }

                if existingSource == .skipped {
                    existing.setValue(source.rawValue, forKey: "sourceRaw")
                    existing.setValue(Date(), forKey: "createdAt")
                    try context.save()
                    return true
                }

                return false
            }

            let habitRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            habitRequest.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
            habitRequest.fetchLimit = 1

            guard let habit = try context.fetch(habitRequest).first else {
                return false
            }

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(habitID, forKey: "habitID")
            completion.setValue(normalizedDate, forKey: "localDate")
            completion.setValue(source.rawValue, forKey: "sourceRaw")
            completion.setValue(Date(), forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")

            try context.save()
            return true
        }, refreshReadContext: false)

        if didCreate == true {
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else { return }
                NotificationCenter.default.post(name: .habitStoreDidChange, object: nil)
            }
            return true
        }

        return false
    }

    @discardableResult
    private func createSkippedCompletionIfNeeded(for habitID: UUID, on localDate: Date) -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let didCreate = storeContext.performWrite({ context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "habitID == %@", habitID as CVarArg),
                NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
            ])
            fetchRequest.fetchLimit = 1

            if let existing = try context.fetch(fetchRequest).first {
                guard
                    let sourceRaw = existing.value(forKey: "sourceRaw") as? String,
                    let existingSource = CompletionSource(rawValue: sourceRaw),
                    existingSource == .skipped
                else {
                    return false
                }

                return false
            }

            let habitRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            habitRequest.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
            habitRequest.fetchLimit = 1

            guard let habit = try context.fetch(habitRequest).first else {
                return false
            }

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(habitID, forKey: "habitID")
            completion.setValue(normalizedDate, forKey: "localDate")
            completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
            completion.setValue(Date(), forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")

            try context.save()
            return true
        }, refreshReadContext: false)

        if didCreate == true {
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else { return }
                NotificationCenter.default.post(name: .habitStoreDidChange, object: nil)
            }
            return true
        }

        return false
    }

    private func removePendingHabitNotifications(completion: @escaping () -> Void) {
        LocalNotificationSupport.removePendingNotifications(center: center, prefix: "habit_", completion: completion)
    }

    private func notificationIdentifierPrefix(for habitID: UUID) -> String {
        "habit_\(habitID.uuidString.lowercased())_"
    }

    private func notificationIdentifier(for habitID: UUID, scheduledDateTime: Date) -> String {
        "\(notificationIdentifierPrefix(for: habitID))\(timestampString(for: scheduledDateTime))"
    }

    private func aggregatedNotificationIdentifier(for scheduledDateTime: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDateTime)
        return String(
            format: "habit_summary_%04d%02d%02d_%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private func localDateIdentifier(for localDate: Date) -> String {
        LocalNotificationSupport.localDateIdentifier(for: localDate, calendar: calendar)
    }

    private func timestampString(for date: Date) -> String {
        LocalNotificationSupport.timestampString(for: date, calendar: calendar)
    }

    private func makeIndividualNotificationRequest(
        for candidate: ScheduledHabitReminderCandidate,
        projectedBadgeCount: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.habitName
        content.body = "Check in today."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.badge = NSNumber(value: projectedBadgeCount)
        content.userInfo = [
            "type": "individual",
            "habitID": candidate.habitID.uuidString,
            "localDate": localDateIdentifier(for: candidate.localDate),
        ]

        let triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: candidate.scheduledDateTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        return UNNotificationRequest(
            identifier: notificationIdentifier(for: candidate.habitID, scheduledDateTime: candidate.scheduledDateTime),
            content: content,
            trigger: trigger
        )
    }

    private func makeAggregatedNotificationRequest(
        for candidates: [ScheduledHabitReminderCandidate],
        scheduledDateTime: Date,
        projectedBadgeCount: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Habits"
        content.body = "You have \(candidates.count) habits to check in today."
        content.sound = .default
        content.categoryIdentifier = summaryCategoryIdentifier
        content.badge = NSNumber(value: projectedBadgeCount)
        content.userInfo = [
            "type": "aggregated",
            "habitCount": candidates.count,
            "localDate": localDateIdentifier(for: scheduledDateTime),
        ]

        let triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: scheduledDateTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        return UNNotificationRequest(
            identifier: aggregatedNotificationIdentifier(for: scheduledDateTime),
            content: content,
            trigger: trigger
        )
    }
}

struct HabitReminderConfiguration {
    let id: UUID
    let name: String
    let startDate: Date
    let scheduleDays: WeekdaySet
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let completedDays: Set<Date>
    let skippedDays: Set<Date>
}

private struct ScheduledHabitReminderCandidate {
    let habitID: UUID
    let habitName: String
    let localDate: Date
    let scheduledDateTime: Date
}
