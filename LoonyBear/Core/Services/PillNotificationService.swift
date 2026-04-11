import CoreData
import Foundation
import UIKit
import UserNotifications

final class PillNotificationService {
    private let categoryIdentifier = "pill.reminder"
    private let summaryCategoryIdentifier = "pill.reminder.summary"
    private let takeActionIdentifier = "pill.take"
    private let skipActionIdentifier = "pill.skip"
    private let remindLaterActionIdentifier = "pill.remind_later"
    private let aggregationThreshold = 3
    private let schedulingWindowDays = 2
    private let remindLaterInterval: TimeInterval = 10 * 60
    private let storeContext: NotificationStoreContext
    private let center = UNUserNotificationCenter.current()
    private let prefix = "pill_"

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

    func prepareReminderNotifications(forPillID pillID: UUID) async {
        if await ensureAuthorizationIfNeeded() {
            rescheduleAllNotifications()
        }
    }

    func notificationCategories() -> [UNNotificationCategory] {
        let takeAction = UNNotificationAction(
            identifier: takeActionIdentifier,
            title: "Mark as Taken",
            options: []
        )
        let skipAction = UNNotificationAction(
            identifier: skipActionIdentifier,
            title: "Mark as Skipped",
            options: []
        )
        let remindLaterAction = UNNotificationAction(
            identifier: remindLaterActionIdentifier,
            title: "Remind me in 10 mins",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [takeAction, skipAction, remindLaterAction],
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

    func rescheduleNotifications(forPillID pillID: UUID) {
        rescheduleAllNotifications()
    }

    func rescheduleAllNotifications() {
        ReliabilityLog.info("notification.pill.reschedule started")
        removeDeliveredAggregatedNotifications(on: Date())
        storeContext.refreshReadContext()
        do {
            let requests = try makePendingNotificationRequests()
            removePendingPillNotifications {
                for request in requests {
                    self.center.add(request) { error in
                        if let error {
                            ReliabilityLog.error(
                                "notification.pill.reschedule request \(request.identifier) failed: \(error.localizedDescription)"
                            )
                        }
                    }
                }
                ReliabilityLog.info("notification.pill.reschedule finished with \(requests.count) request(s)")
            }
        } catch let error as DataIntegrityError {
            ReliabilityLog.error("notification.pill.reschedule failed: \(error.localizedDescription)")
        } catch {
            ReliabilityLog.error("notification.pill.reschedule failed: \(error.localizedDescription)")
        }
    }

    func removeNotifications(forPillID pillID: UUID) {
        rescheduleAllNotifications()
        removeDeliveredNotifications(forPillID: pillID)
    }

    func removeDeliveredNotifications(forPillID pillID: UUID) {
        let pillPrefix = notificationIdentifierPrefix(for: pillID)
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(pillPrefix) }
            self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    func removeDeliveredNotifications(forPillID pillID: UUID, on localDate: Date) {
        let pillPrefix = notificationIdentifierPrefix(for: pillID)
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                guard notification.request.identifier.hasPrefix(pillPrefix) else {
                    return nil
                }

                let deliveredDay = self.calendar.startOfDay(for: notification.date)
                return deliveredDay == normalizedDay ? notification.request.identifier : nil
            }

            self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    func handleAppDidBecomeActive() {
        rescheduleAllNotifications()
        cleanupStaleDeliveredNotifications()
    }

    @discardableResult
    func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard let type = response.notification.request.content.userInfo["type"] as? String else {
            return false
        }

        return handleNotificationResponse(
            type: type,
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier,
            notificationDate: response.notification.date,
            fallbackTitle: response.notification.request.content.title,
            fallbackBody: response.notification.request.content.body
        )
    }

    @discardableResult
    func handleNotificationResponse(
        type: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        notificationDate: Date,
        fallbackTitle: String? = nil,
        fallbackBody: String? = nil
    ) -> Bool {
        if handleDefaultTapRouting(type: type, actionIdentifier: actionIdentifier) {
            return true
        }

        guard type == "pill" else { return false }

        guard
            let pillIDString = userInfo["pillID"] as? String,
            let pillID = UUID(uuidString: pillIDString)
        else {
            return true
        }

        let deliveryDay = localDate(from: userInfo, fallbackDate: notificationDate)
        let didMutateStore: Bool
        switch actionIdentifier {
        case takeActionIdentifier:
            didMutateStore = createIntakeIfNeeded(for: pillID, on: deliveryDay, source: .notification)
        case skipActionIdentifier:
            didMutateStore = createSkippedIntakeIfNeeded(for: pillID, on: deliveryDay)
        case remindLaterActionIdentifier:
            removeDeliveredNotifications(forPillID: pillID, on: deliveryDay)
            scheduleRemindLaterNotification(
                for: pillID,
                on: deliveryDay,
                fallbackTitle: fallbackTitle,
                fallbackBody: fallbackBody
            )
            return true
        default:
            return true
        }

        removeDeliveredNotifications(forPillID: pillID, on: deliveryDay)
        if didMutateStore {
            rescheduleAllNotifications()
        }
        return true
    }

    @discardableResult
    func handleDefaultTapRouting(type: String, actionIdentifier: String) -> Bool {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return false }
        guard type == "pill_aggregated" || type == "pill" else { return false }

        let postSignal = {
            NotificationCenter.default.post(name: .openMyPillsTab, object: nil)
        }
        if Thread.isMainThread {
            postSignal()
        } else {
            DispatchQueue.main.async(execute: postSignal)
        }
        return true
    }

    private func removeDeliveredAggregatedNotifications(on localDate: Date) {
        LocalNotificationSupport.removeDeliveredAggregatedNotifications(
            center: center,
            calendar: calendar,
            type: "pill_aggregated",
            on: localDate
        )
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

    private func scheduleRemindLaterNotification(
        for pillID: UUID,
        on localDate: Date,
        fallbackTitle: String?,
        fallbackBody: String?
    ) {
        let content = makeRemindLaterContent(
            for: pillID,
            on: localDate,
            fallbackTitle: fallbackTitle,
            fallbackBody: fallbackBody
        )
        let remindDate = Date().addingTimeInterval(remindLaterInterval)
        let triggerDate = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: remindDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(
            identifier: remindLaterNotificationIdentifier(for: pillID, scheduledDateTime: remindDate),
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error {
                ReliabilityLog.error(
                    "notification.pill.remindLater request \(request.identifier) failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func makeRemindLaterContent(
        for pillID: UUID,
        on localDate: Date,
        fallbackTitle: String?,
        fallbackBody: String?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let fallbackDetails: (String, String)?
        do {
            fallbackDetails = try storeContext.performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
            request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
            request.fetchLimit = 1
            guard let pill = try context.fetch(request).first else {
                return nil
            }

            guard
                let name = pill.stringValue(forKey: "name"),
                let dosage = pill.stringValue(forKey: "dosage")
            else {
                return nil
            }

            return (name, "Take \(dosage).")
            }
        } catch {
            fallbackDetails = nil
        }

        content.title = fallbackTitle ?? fallbackDetails?.0 ?? "Pill reminder"
        content.body = fallbackBody ?? fallbackDetails?.1 ?? "Time to take your pill."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            "type": "pill",
            "pillID": pillID.uuidString,
            "localDate": LocalNotificationSupport.localDateIdentifier(for: localDate, calendar: calendar),
        ]
        return content
    }

    func makePendingNotificationRequests() throws -> [UNNotificationRequest] {
        let pills = try storeContext.performRead(fetchReminderConfigurations)
        let habits = try storeContext.performRead(fetchHabitReminderConfigurations)
        let candidates = pills.flatMap(reminderCandidates(for:))
        let groupedCandidates = Dictionary(grouping: candidates, by: \.scheduledDateTime)

        return groupedCandidates.values.flatMap { group in
            notificationRequests(for: group, habits: habits, pills: pills)
        }
    }

    private func fetchReminderConfigurations(context: NSManagedObjectContext) throws -> [PillReminderConfiguration] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        let pills = try context.fetch(request)
        var report = IntegrityReportBuilder()
        var configurations: [PillReminderConfiguration] = []

        for object in pills {
            if let configuration = makeReminderConfiguration(from: object, report: &report) {
                configurations.append(configuration)
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: "notification.fetchPillReminderConfigurations")
        }

        return configurations
    }

    private func fetchHabitReminderConfigurations(context: NSManagedObjectContext) throws -> [HabitReminderConfiguration] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        let habits = try context.fetch(request)
        var report = IntegrityReportBuilder()
        var configurations: [HabitReminderConfiguration] = []

        for object in habits {
            if let configuration = makeHabitReminderConfiguration(from: object, report: &report) {
                configurations.append(configuration)
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: "notification.fetchHabitReminderConfigurations")
        }

        return configurations
    }

    private func makeReminderConfiguration(
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

    private func reminderCandidates(for reminder: PillReminderConfiguration) -> [ScheduledPillReminderCandidate] {
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

            return ScheduledPillReminderCandidate(
                pillID: reminder.id,
                pillName: reminder.name,
                dosage: reminder.dosage,
                localDate: normalizedDay,
                scheduledDateTime: scheduledDateTime
            )
        }
    }

    private func notificationRequests(
        for candidates: [ScheduledPillReminderCandidate],
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

    private func makeIndividualNotificationRequest(
        for candidate: ScheduledPillReminderCandidate,
        projectedBadgeCount: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.pillName
        content.body = "Take \(candidate.dosage)."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.badge = NSNumber(value: projectedBadgeCount)
        content.userInfo = [
            "type": "pill",
            "pillID": candidate.pillID.uuidString,
            "localDate": LocalNotificationSupport.localDateIdentifier(for: candidate.localDate, calendar: calendar),
        ]

        let triggerDate = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.scheduledDateTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        return UNNotificationRequest(
            identifier: notificationIdentifier(for: candidate.pillID, scheduledDateTime: candidate.scheduledDateTime),
            content: content,
            trigger: trigger
        )
    }

    private func makeAggregatedNotificationRequest(
        for candidates: [ScheduledPillReminderCandidate],
        scheduledDateTime: Date,
        projectedBadgeCount: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Pills"
        content.body = "You have \(candidates.count) pills to take."
        content.sound = .default
        content.categoryIdentifier = summaryCategoryIdentifier
        content.badge = NSNumber(value: projectedBadgeCount)
        content.userInfo = [
            "type": "pill_aggregated",
            "count": candidates.count,
            "localDate": LocalNotificationSupport.localDateIdentifier(for: scheduledDateTime, calendar: calendar),
        ]

        let triggerDate = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDateTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        return UNNotificationRequest(
            identifier: aggregatedNotificationIdentifier(for: scheduledDateTime),
            content: content,
            trigger: trigger
        )
    }

    private func makeHabitReminderConfiguration(
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

    private func notificationIdentifierPrefix(for pillID: UUID) -> String {
        "\(prefix)\(pillID.uuidString.lowercased())_"
    }

    private func notificationIdentifier(for pillID: UUID, scheduledDateTime: Date) -> String {
        "\(notificationIdentifierPrefix(for: pillID))\(timestampString(for: scheduledDateTime))"
    }

    private func aggregatedNotificationIdentifier(for scheduledDateTime: Date) -> String {
        "\(prefix)summary_\(timestampString(for: scheduledDateTime))"
    }

    private func remindLaterNotificationIdentifier(for pillID: UUID, scheduledDateTime: Date) -> String {
        "\(notificationIdentifierPrefix(for: pillID))remindlater_\(timestampString(for: scheduledDateTime))"
    }

    private func timestampString(for date: Date) -> String {
        LocalNotificationSupport.timestampString(for: date, calendar: calendar)
    }

    @discardableResult
    private func createIntakeIfNeeded(for pillID: UUID, on localDate: Date, source: PillCompletionSource) -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let didCreate = storeContext.performWrite { context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "pillID == %@", pillID as CVarArg),
                NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
            ])
            fetchRequest.fetchLimit = 1

            if let existing = try context.fetch(fetchRequest).first {
                guard
                    let sourceRaw = existing.value(forKey: "sourceRaw") as? String,
                    let existingSource = PillCompletionSource(rawValue: sourceRaw)
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

            let pillRequest = NSFetchRequest<NSManagedObject>(entityName: "Pill")
            pillRequest.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
            pillRequest.fetchLimit = 1

            guard let pill = try context.fetch(pillRequest).first else {
                return false
            }

            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(pillID, forKey: "pillID")
            intake.setValue(normalizedDate, forKey: "localDate")
            intake.setValue(source.rawValue, forKey: "sourceRaw")
            intake.setValue(Date(), forKey: "createdAt")
            intake.setValue(pill, forKey: "pill")

            try context.save()
            return true
        }

        if didCreate == true {
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else { return }
                NotificationCenter.default.post(name: .pillStoreDidChange, object: nil)
            }
            return true
        }

        return false
    }

    @discardableResult
    private func createSkippedIntakeIfNeeded(for pillID: UUID, on localDate: Date) -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let didCreate = storeContext.performWrite { context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "pillID == %@", pillID as CVarArg),
                NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
            ])
            fetchRequest.fetchLimit = 1

            if let existing = try context.fetch(fetchRequest).first {
                guard
                    let sourceRaw = existing.value(forKey: "sourceRaw") as? String,
                    let existingSource = PillCompletionSource(rawValue: sourceRaw),
                    existingSource == .skipped
                else {
                    return false
                }

                return false
            }

            let pillRequest = NSFetchRequest<NSManagedObject>(entityName: "Pill")
            pillRequest.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
            pillRequest.fetchLimit = 1

            guard let pill = try context.fetch(pillRequest).first else {
                return false
            }

            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(pillID, forKey: "pillID")
            intake.setValue(normalizedDate, forKey: "localDate")
            intake.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
            intake.setValue(Date(), forKey: "createdAt")
            intake.setValue(pill, forKey: "pill")

            try context.save()
            return true
        }

        if didCreate == true {
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else { return }
                NotificationCenter.default.post(name: .pillStoreDidChange, object: nil)
            }
            return true
        }

        return false
    }

    private func removePendingPillNotifications(completion: @escaping () -> Void) {
        LocalNotificationSupport.removePendingNotifications(center: center, prefix: prefix, completion: completion)
    }
}

struct PillReminderConfiguration {
    let id: UUID
    let name: String
    let dosage: String
    let startDate: Date
    let scheduleDays: WeekdaySet
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let takenDays: Set<Date>
    let skippedDays: Set<Date>
}

private struct ScheduledPillReminderCandidate {
    let pillID: UUID
    let pillName: String
    let dosage: String
    let localDate: Date
    let scheduledDateTime: Date
}
