import CoreData
import Foundation
import UIKit
import UserNotifications

private enum PillNotificationMutationError: LocalizedError {
    case invalidStoredIntakeSource

    var errorDescription: String? {
        switch self {
        case .invalidStoredIntakeSource:
            return "Stored pill intake source is invalid."
        }
    }
}

final class PillNotificationService {
    private enum NotificationActionDayState {
        case current
        case inactive
        case failed
    }

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
    private let calendar: Calendar
    private let clock: AppClock
    private let overdueAnchorStore: OverdueAnchorStore

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        clock: AppClock? = nil,
        overdueAnchorStore: OverdueAnchorStore? = nil
    ) {
        let resolvedClock = clock ?? AppClock(calendar: calendar)
        self.calendar = resolvedClock.calendar
        self.clock = resolvedClock
        self.overdueAnchorStore = overdueAnchorStore ?? UserDefaultsOverdueAnchorStore.shared
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
        center.getPendingNotificationRequests { requests in
            guard !requests.contains(where: { $0.identifier.hasPrefix("pill_summary_") }) else {
                self.rescheduleAllNotifications()
                return
            }

            let requestsToAdd: [UNNotificationRequest]
            do {
                requestsToAdd = try self.makePendingNotificationRequests(forPillID: pillID)
            } catch {
                ReliabilityLog.error("notification.pill.reschedule.item failed: \(error.localizedDescription)")
                return
            }

            self.removePendingRegularNotifications(forPillID: pillID) {
                self.addPendingNotificationRequests(
                    requestsToAdd,
                    logName: "notification.pill.reschedule.item"
                )
            }
        }
    }

    func rescheduleAllNotifications() {
        rescheduleAllNotifications(completion: nil)
    }

    func rescheduleAllNotifications(completion: (() -> Void)?) {
        NotificationRescheduleSupport.rescheduleAll(
            center: center,
            storeContext: storeContext,
            logName: "notification.pill.reschedule",
            now: clock.now,
            removeDeliveredAggregatedNotifications: removeDeliveredAggregatedNotifications(on:),
            removePendingNotifications: removePendingRegularPillNotifications(completion:),
            makePendingRequests: makePendingNotificationRequests,
            completion: completion
        )
    }

    func removePendingNotification(forPillID pillID: UUID, on localDate: Date) {
        NotificationCleanupSupport.removePendingNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: pillID),
            on: localDate,
            calendar: calendar
        )
    }

    func removeNotifications(forPillID pillID: UUID) {
        overdueAnchorStore.clearAnchorDay(for: .pill, id: pillID)
        removePendingNotifications(forPillID: pillID) {
            self.removeDeliveredNotifications(forPillID: pillID)
            self.rescheduleAllNotifications()
        }
    }

    func removeDeliveredNotifications(forPillID pillID: UUID) {
        NotificationCleanupSupport.removeDeliveredNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: pillID)
        )
    }

    func removeDeliveredNotifications(
        forPillID pillID: UUID,
        on localDate: Date,
        notificationIdentifier: String? = nil
    ) {
        NotificationCleanupSupport.removeDeliveredNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: pillID),
            on: localDate,
            calendar: calendar,
            including: notificationIdentifier
        )
    }

    func removeDeliveredNotifications(
        forPillID pillID: UUID,
        on localDate: Date,
        notificationIdentifier: String? = nil,
        completion: @escaping () -> Void
    ) {
        NotificationCleanupSupport.removeDeliveredNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: pillID),
            on: localDate,
            calendar: calendar,
            including: notificationIdentifier,
            completion: completion
        )
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
            notificationIdentifier: response.notification.request.identifier,
            fallbackTitle: response.notification.request.content.title,
            fallbackBody: response.notification.request.content.body
        )
    }

    func handleNotificationResponse(
        _ response: UNNotificationResponse,
        completion: @escaping (Bool) -> Void
    ) {
        guard let type = response.notification.request.content.userInfo["type"] as? String else {
            completion(false)
            return
        }

        handleNotificationResponse(
            type: type,
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier,
            notificationDate: response.notification.date,
            notificationIdentifier: response.notification.request.identifier,
            fallbackTitle: response.notification.request.content.title,
            fallbackBody: response.notification.request.content.body,
            completion: completion
        )
    }

    @discardableResult
    func handleNotificationResponse(
        type: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        notificationDate: Date,
        notificationIdentifier: String? = nil,
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
        switch notificationActionDayState(for: pillID, deliveryDay: deliveryDay) {
        case .current:
            break
        case .inactive:
            removeDeliveredNotifications(
                forPillID: pillID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            )
            removeSnoozedNotifications(forPillID: pillID, on: deliveryDay)
            return true
        case .failed:
            return true
        }

        if actionIdentifier == remindLaterActionIdentifier {
            removeDeliveredNotifications(
                forPillID: pillID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            )
            removeSnoozedNotifications(forPillID: pillID, on: deliveryDay) {
                self.scheduleRemindLaterNotification(
                    for: pillID,
                    on: deliveryDay,
                    fallbackTitle: fallbackTitle,
                    fallbackBody: fallbackBody
                )
            }
            return true
        }

        let actionOutcome: NotificationMutationOutcome
        switch actionIdentifier {
        case takeActionIdentifier:
            actionOutcome = createIntakeIfNeeded(for: pillID, on: deliveryDay, source: .notification)
        case skipActionIdentifier:
            actionOutcome = createSkippedIntakeIfNeeded(for: pillID, on: deliveryDay)
        default:
            return true
        }

        guard case .failed = actionOutcome else {
            clearOverdueAnchorIfNeeded(for: pillID, on: deliveryDay)
            removeDeliveredNotifications(
                forPillID: pillID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            )
            removeSnoozedNotifications(forPillID: pillID, on: deliveryDay) {
                if case .mutated = actionOutcome {
                    self.rescheduleAllNotifications()
                }
            }
            return true
        }

        return true
    }

    func handleNotificationResponse(
        type: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        notificationDate: Date,
        notificationIdentifier: String? = nil,
        fallbackTitle: String? = nil,
        fallbackBody: String? = nil,
        onCleanupFinished: (() -> Void)? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        if handleDefaultTapRouting(type: type, actionIdentifier: actionIdentifier) {
            completion(true)
            return
        }

        guard type == "pill" else {
            completion(false)
            return
        }

        guard
            let pillIDString = userInfo["pillID"] as? String,
            let pillID = UUID(uuidString: pillIDString)
        else {
            completion(true)
            return
        }

        let deliveryDay = localDate(from: userInfo, fallbackDate: notificationDate)
        switch notificationActionDayState(for: pillID, deliveryDay: deliveryDay) {
        case .current:
            break
        case .inactive:
            removeDeliveredNotifications(
                forPillID: pillID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            ) {
                self.removeSnoozedNotifications(forPillID: pillID, on: deliveryDay) {
                    onCleanupFinished?()
                    completion(true)
                }
            }
            return
        case .failed:
            completion(true)
            return
        }

        if actionIdentifier == remindLaterActionIdentifier {
            removeDeliveredNotifications(
                forPillID: pillID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            ) {
                self.removeSnoozedNotifications(forPillID: pillID, on: deliveryDay) {
                    onCleanupFinished?()
                    self.scheduleRemindLaterNotification(
                        for: pillID,
                        on: deliveryDay,
                        fallbackTitle: fallbackTitle,
                        fallbackBody: fallbackBody
                    ) {
                        completion(true)
                    }
                }
            }
            return
        }

        let actionOutcome: NotificationMutationOutcome
        switch actionIdentifier {
        case takeActionIdentifier:
            actionOutcome = createIntakeIfNeeded(for: pillID, on: deliveryDay, source: .notification)
        case skipActionIdentifier:
            actionOutcome = createSkippedIntakeIfNeeded(for: pillID, on: deliveryDay)
        default:
            completion(true)
            return
        }

        guard case .failed = actionOutcome else {
            clearOverdueAnchorIfNeeded(for: pillID, on: deliveryDay)
            removeDeliveredNotifications(
                forPillID: pillID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            ) {
                self.removeSnoozedNotifications(forPillID: pillID, on: deliveryDay) {
                    onCleanupFinished?()
                    if case .mutated = actionOutcome {
                        self.rescheduleAllNotifications()
                    }
                    completion(true)
                }
            }
            return
        }

        completion(true)
    }

    private func notificationActionDayState(for pillID: UUID, deliveryDay: Date) -> NotificationActionDayState {
        let normalizedDeliveryDay = calendar.startOfDay(for: deliveryDay)

        do {
            let isCurrent = try storeContext.performRead { context in
                let pillRequest = NSFetchRequest<NSManagedObject>(entityName: "Pill")
                pillRequest.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
                pillRequest.fetchLimit = 1

                guard let pill = try context.fetch(pillRequest).first else {
                    return false
                }

                var report = IntegrityReportBuilder()
                guard
                    let startDate = pill.dateValue(forKey: "startDate"),
                    let schedules = loadPillSchedules(for: pill, pillID: pillID, report: &report),
                    let intakeEntries = loadPillIntakeEntries(for: pill, report: &report)
                else {
                    throw report.makeError(operation: "notification.pill.action.currentDay")
                }

                let reminderEnabled = pill.boolValue(forKey: "reminderEnabled")
                let reminderTime = ReminderValidation.validatedReminderTime(
                    from: pill,
                    reminderEnabled: reminderEnabled,
                    area: "notification.pill.action.currentDay",
                    report: &report
                )
                guard !reminderEnabled || reminderTime != nil else {
                    throw report.makeError(operation: "notification.pill.action.currentDay")
                }

                let takenDays = Set(intakeEntries.compactMap { $0.1.countsAsIntake ? $0.0 : nil })
                let skippedDays = Set(intakeEntries.compactMap { !$0.1.countsAsIntake ? $0.0 : nil })
                let activeOverdueDay = ScheduledOverdueState.activeOverdueDay(
                    startDate: startDate,
                    schedules: schedules,
                    reminderTime: reminderTime,
                    positiveDays: takenDays,
                    skippedDays: skippedDays,
                    now: clock.now(),
                    calendar: calendar
                )

                return activeOverdueDay.map { calendar.startOfDay(for: $0) == normalizedDeliveryDay } ?? false
            }
            return isCurrent ? .current : .inactive
        } catch {
            ReliabilityLog.error("notification.pill.action.currentDay failed: \(error.localizedDescription)")
            return .failed
        }
    }

    private func insertSkippedIntakeIfNeeded(
        for pill: NSManagedObject,
        pillID: UUID,
        on localDate: Date,
        context: NSManagedObjectContext
    ) throws -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
        ])
        fetchRequest.fetchLimit = 1

        if try context.fetch(fetchRequest).first != nil {
            return false
        }

        let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
        intake.setValue(UUID(), forKey: "id")
        intake.setValue(pillID, forKey: "pillID")
        intake.setValue(normalizedDate, forKey: "localDate")
        intake.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
        intake.setValue(clock.now(), forKey: "createdAt")
        intake.setValue(pill, forKey: "pill")
        return true
    }

    private func loadPillSchedules(
        for pillObject: NSManagedObject,
        pillID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [PillScheduleVersion]? {
        CoreDataRelationshipLoadingSupport.validatedScheduleModels(
            from: pillObject,
            relationshipKey: "scheduleVersions",
            area: "notification.action.catchUp",
            missingFieldsMessage: "Pill schedule row is missing required fields.",
            invalidMaskMessage: "Pill schedule row contains invalid weekdayMask.",
            report: &report
        ) { scheduleID, weekdayMask, effectiveFrom, createdAt, version in
            PillScheduleVersion(
                id: scheduleID,
                pillID: pillID,
                weekdays: WeekdaySet(rawValue: weekdayMask),
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func postPillStoreDidChangeIfActive() {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else { return }
            NotificationCenter.default.post(name: .pillStoreDidChange, object: nil)
        }
    }

    @discardableResult
    func handleDefaultTapRouting(type: String, actionIdentifier: String) -> Bool {
        NotificationResponseSupport.handleDefaultTapRouting(
            type: type,
            actionIdentifier: actionIdentifier,
            acceptedTypes: ["pill_aggregated", "pill"],
            notificationName: .openMyPillsTab
        )
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
        LocalNotificationSupport.cleanupStaleDeliveredNotifications(
            center: center,
            calendar: calendar,
            today: clock.now()
        )
    }

    private func localDate(from userInfo: [AnyHashable: Any], fallbackDate: Date) -> Date {
        NotificationResponseSupport.localDate(
            from: userInfo,
            fallbackDate: fallbackDate,
            calendar: calendar
        )
    }

    private func scheduleRemindLaterNotification(
        for pillID: UUID,
        on localDate: Date,
        fallbackTitle: String?,
        fallbackBody: String?,
        completion: (() -> Void)? = nil
    ) {
        let content = makeRemindLaterContent(
            for: pillID,
            on: localDate,
            fallbackTitle: fallbackTitle,
            fallbackBody: fallbackBody
        )
        let remindDate = clock.now().addingTimeInterval(remindLaterInterval)
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
            completion?()
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

        content.title = fallbackDetails?.0 ?? fallbackTitle ?? "Pill reminder"
        content.body = fallbackDetails?.1 ?? fallbackBody ?? "Time to take your pill."
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
        let candidates = ReminderPlanningSupport.pillCandidates(
            reminders: pills,
            now: clock.now(),
            schedulingWindowDays: schedulingWindowDays,
            calendar: calendar
        )
        recordPendingOverdueAnchors(from: candidates)
        let deliveries = ReminderPlanningSupport.pillDeliveries(
            candidates: candidates,
            habits: habits,
            pills: pills,
            aggregationThreshold: aggregationThreshold,
            calendar: calendar
        )

        return deliveries.map(makeNotificationRequest(for:))
    }

    private func recordPendingOverdueAnchors(from candidates: [PillNotificationCandidate]) {
        let candidateDaysByPillID = Dictionary(grouping: candidates, by: \.pillID)
            .mapValues { candidates in
                Set(candidates.map { calendar.startOfDay(for: $0.localDate) })
            }
        let today = calendar.startOfDay(for: clock.now())

        for (pillID, candidateDays) in candidateDaysByPillID {
            guard let earliestCandidateDay = candidateDays.sorted().first else { continue }
            if let currentAnchor = overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar) {
                if currentAnchor <= today {
                    continue
                }
                if candidateDays.contains(currentAnchor), currentAnchor <= earliestCandidateDay {
                    continue
                }
            }
            overdueAnchorStore.setAnchorDay(earliestCandidateDay, for: .pill, id: pillID, calendar: calendar)
        }
    }

    private func clearOverdueAnchorIfNeeded(for pillID: UUID, on day: Date) {
        guard
            let anchorDay = overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar),
            anchorDay == calendar.startOfDay(for: day)
        else {
            return
        }
        overdueAnchorStore.clearAnchorDay(for: .pill, id: pillID)
    }

    private func fetchReminderConfigurations(context: NSManagedObjectContext) throws -> [PillReminderConfiguration] {
        try NotificationConfigurationSupport.fetchConfigurations(
            entityName: "Pill",
            operation: "notification.fetchPillReminderConfigurations",
            context: context,
            build: makeReminderConfiguration(from:report:)
        )
    }

    private func fetchHabitReminderConfigurations(context: NSManagedObjectContext) throws -> [HabitReminderConfiguration] {
        try NotificationConfigurationSupport.fetchConfigurations(
            entityName: "Habit",
            operation: "notification.fetchHabitReminderConfigurations",
            context: context,
            build: makeHabitReminderConfiguration(from:report:)
        )
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
        guard let scheduleHistory = loadPillSchedules(for: object, pillID: id, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Pill reminder configuration failed because schedule rows are corrupted."
            )
            return nil
        }
        let scheduleDays = latestScheduleDays(from: scheduleHistory)
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
            scheduleHistory: scheduleHistory,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            takenDays: takenDays,
            skippedDays: skippedDays
        )
    }

    private func makeNotificationRequest(for delivery: PillNotificationDeliveryPlan) -> UNNotificationRequest {
        switch delivery {
        case .individual(let candidate, let projectedBadgeCount):
            makeIndividualNotificationRequest(for: candidate, projectedBadgeCount: projectedBadgeCount)
        case .aggregated(let candidates, let scheduledDateTime, let projectedBadgeCount):
            makeAggregatedNotificationRequest(
                for: candidates,
                scheduledDateTime: scheduledDateTime,
                projectedBadgeCount: projectedBadgeCount
            )
        }
    }

    private func makeIndividualNotificationRequest(
        for candidate: PillNotificationCandidate,
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
        for candidates: [PillNotificationCandidate],
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

        guard let scheduleHistory = loadHabitSchedules(for: object, habitID: id, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Habit reminder configuration failed because schedule rows are corrupted."
            )
            return nil
        }
        let scheduleDays = latestScheduleDays(from: scheduleHistory)

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
            scheduleHistory: scheduleHistory,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            completedDays: completedDays,
            skippedDays: skippedDays
        )
    }

    private func latestScheduleDays<Schedule: HistoryScheduleVersionLike>(from schedules: [Schedule]) -> WeekdaySet {
        schedules.sorted { lhs, rhs in
            if lhs.effectiveFrom != rhs.effectiveFrom {
                return lhs.effectiveFrom > rhs.effectiveFrom
            }
            if lhs.version != rhs.version {
                return lhs.version > rhs.version
            }
            return lhs.createdAt > rhs.createdAt
        }.first?.weekdays ?? WeekdaySet(rawValue: 0)
    }

    private func loadHabitSchedules(
        for object: NSManagedObject,
        habitID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [HabitScheduleVersion]? {
        CoreDataRelationshipLoadingSupport.validatedScheduleModels(
            from: object,
            relationshipKey: "scheduleVersions",
            area: "notification",
            missingFieldsMessage: "Habit schedule row is missing required fields.",
            invalidMaskMessage: "Habit schedule row contains invalid weekdayMask.",
            report: &report
        ) { scheduleID, weekdayMask, effectiveFrom, createdAt, version in
            HabitScheduleVersion(
                id: scheduleID,
                habitID: habitID,
                weekdays: WeekdaySet(rawValue: weekdayMask),
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func loadHabitCompletionEntries(
        for object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> [(Date, CompletionSource)]? {
        NotificationConfigurationSupport.loadHistoryEntries(
            for: object,
            relationshipKey: "completions",
            invalidEntryMessage: "Habit completion row is missing required fields or has invalid sourceRaw.",
            calendar: calendar,
            report: &report
        )
    }

    private func loadPillIntakeEntries(
        for object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> [(Date, PillCompletionSource)]? {
        NotificationConfigurationSupport.loadHistoryEntries(
            for: object,
            relationshipKey: "intakes",
            invalidEntryMessage: "Pill intake row is missing required fields or has invalid sourceRaw.",
            calendar: calendar,
            report: &report
        )
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

    private func isRegularPillReminderIdentifier(_ identifier: String) -> Bool {
        guard identifier.hasPrefix(prefix) else { return false }
        return !isSnoozedPillReminderIdentifier(identifier)
    }

    private func isSnoozedPillReminderIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(prefix) && identifier.contains("_remindlater_")
    }

    private func timestampString(for date: Date) -> String {
        LocalNotificationSupport.timestampString(for: date, calendar: calendar)
    }

    @discardableResult
    private func createIntakeIfNeeded(
        for pillID: UUID,
        on localDate: Date,
        source: PillCompletionSource
    ) -> NotificationMutationOutcome {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let mutationResult = storeContext.performWrite { context in
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
                    throw PillNotificationMutationError.invalidStoredIntakeSource
                }

                if existingSource == .skipped {
                    existing.setValue(source.rawValue, forKey: "sourceRaw")
                    existing.setValue(clock.now(), forKey: "createdAt")
                    try context.save()
                    return NotificationMutationOutcome.mutated
                }

                return NotificationMutationOutcome.noChange
            }

            let pillRequest = NSFetchRequest<NSManagedObject>(entityName: "Pill")
            pillRequest.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
            pillRequest.fetchLimit = 1

            guard let pill = try context.fetch(pillRequest).first else {
                return NotificationMutationOutcome.noChange
            }

            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(pillID, forKey: "pillID")
            intake.setValue(normalizedDate, forKey: "localDate")
            intake.setValue(source.rawValue, forKey: "sourceRaw")
            intake.setValue(clock.now(), forKey: "createdAt")
            intake.setValue(pill, forKey: "pill")

            try context.save()
            return .mutated
        }

        switch mutationResult {
        case .success(let outcome):
            if case .mutated = outcome {
                DispatchQueue.main.async {
                    guard UIApplication.shared.applicationState == .active else { return }
                    NotificationCenter.default.post(name: .pillStoreDidChange, object: nil)
                }
            }
            return outcome
        case .failure(let error):
            ReliabilityLog.error("notification.pill.action.store write failed: \(error.localizedDescription)")
            return .failed(error)
        }
    }

    @discardableResult
    private func createSkippedIntakeIfNeeded(for pillID: UUID, on localDate: Date) -> NotificationMutationOutcome {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let mutationResult = storeContext.performWrite { context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "pillID == %@", pillID as CVarArg),
                NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
            ])
            fetchRequest.fetchLimit = 1

            if let existing = try context.fetch(fetchRequest).first {
                guard
                    let sourceRaw = existing.value(forKey: "sourceRaw") as? String,
                    PillCompletionSource(rawValue: sourceRaw) != nil
                else {
                    throw PillNotificationMutationError.invalidStoredIntakeSource
                }

                return NotificationMutationOutcome.noChange
            }

            let pillRequest = NSFetchRequest<NSManagedObject>(entityName: "Pill")
            pillRequest.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
            pillRequest.fetchLimit = 1

            guard let pill = try context.fetch(pillRequest).first else {
                return NotificationMutationOutcome.noChange
            }

            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(pillID, forKey: "pillID")
            intake.setValue(normalizedDate, forKey: "localDate")
            intake.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
            intake.setValue(clock.now(), forKey: "createdAt")
            intake.setValue(pill, forKey: "pill")

            try context.save()
            return .mutated
        }

        switch mutationResult {
        case .success(let outcome):
            if case .mutated = outcome {
                DispatchQueue.main.async {
                    guard UIApplication.shared.applicationState == .active else { return }
                    NotificationCenter.default.post(name: .pillStoreDidChange, object: nil)
                }
            }
            return outcome
        case .failure(let error):
            ReliabilityLog.error("notification.pill.action.store write failed: \(error.localizedDescription)")
            return .failed(error)
        }
    }

    func removeSnoozedNotifications(
        forPillID pillID: UUID,
        on localDate: Date,
        completion: @escaping () -> Void = {}
    ) {
        let normalizedDate = calendar.startOfDay(for: localDate)
        LocalNotificationSupport.removePendingNotifications(center: center, matching: { request in
            guard self.isSnoozedPillReminderIdentifier(request.identifier) else { return false }
            guard request.identifier.hasPrefix(self.notificationIdentifierPrefix(for: pillID)) else { return false }
            guard
                let localDateIdentifier = request.content.userInfo["localDate"] as? String,
                let requestLocalDate = LocalNotificationSupport.parseLocalDateIdentifier(
                    localDateIdentifier,
                    calendar: self.calendar
                )
            else {
                return false
            }
            return requestLocalDate == normalizedDate
        }, completion: completion)
    }

    private func removePendingNotifications(forPillID pillID: UUID, completion: @escaping () -> Void) {
        let pillPrefix = notificationIdentifierPrefix(for: pillID)
        LocalNotificationSupport.removePendingNotifications(center: center, matching: { request in
            request.identifier.hasPrefix(pillPrefix)
        }, completion: completion)
    }

    private func removePendingRegularNotifications(forPillID pillID: UUID, completion: @escaping () -> Void) {
        let pillPrefix = notificationIdentifierPrefix(for: pillID)
        LocalNotificationSupport.removePendingNotifications(center: center, matching: { request in
            self.isRegularPillReminderIdentifier(request.identifier) &&
                request.identifier.hasPrefix(pillPrefix)
        }, completion: completion)
    }

    private func removePendingRegularPillNotifications(completion: @escaping () -> Void) {
        LocalNotificationSupport.removePendingNotifications(center: center, matching: { request in
            self.isRegularPillReminderIdentifier(request.identifier)
        }, completion: completion)
    }

    private func makePendingNotificationRequests(forPillID pillID: UUID) throws -> [UNNotificationRequest] {
        let pills = try storeContext.performRead(fetchReminderConfigurations)
        let habits = try storeContext.performRead(fetchHabitReminderConfigurations)
        guard let pill = pills.first(where: { $0.id == pillID }) else {
            return []
        }

        let candidates = ReminderPlanningSupport.pillCandidates(
            reminders: [pill],
            now: clock.now(),
            schedulingWindowDays: schedulingWindowDays,
            calendar: calendar
        )
        recordPendingOverdueAnchors(from: candidates)

        return candidates.map { candidate in
            makeIndividualNotificationRequest(
                for: candidate,
                projectedBadgeCount: ProjectedBadgeCountCalculator.projectedOverdueCount(
                    at: candidate.scheduledDateTime,
                    habits: habits,
                    pills: pills,
                    calendar: calendar
                )
            )
        }
    }

    private func addPendingNotificationRequests(_ requests: [UNNotificationRequest], logName: String) {
        guard !requests.isEmpty else {
            ReliabilityLog.info("\(logName) finished with 0 request(s)")
            return
        }

        for request in requests {
            center.add(request) { error in
                if let error {
                    ReliabilityLog.error("\(logName) request \(request.identifier) failed: \(error.localizedDescription)")
                }
            }
        }
        ReliabilityLog.info("\(logName) finished with \(requests.count) request(s)")
    }
}

struct PillReminderConfiguration {
    let id: UUID
    let name: String
    let dosage: String
    let startDate: Date
    let scheduleDays: WeekdaySet
    let scheduleHistory: [PillScheduleVersion]
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let takenDays: Set<Date>
    let skippedDays: Set<Date>

    init(
        id: UUID,
        name: String,
        dosage: String,
        startDate: Date,
        scheduleDays: WeekdaySet,
        scheduleHistory: [PillScheduleVersion] = [],
        reminderEnabled: Bool,
        reminderTime: ReminderTime?,
        takenDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.startDate = startDate
        self.scheduleDays = scheduleDays
        self.scheduleHistory = scheduleHistory
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.takenDays = takenDays
        self.skippedDays = skippedDays
    }
}
