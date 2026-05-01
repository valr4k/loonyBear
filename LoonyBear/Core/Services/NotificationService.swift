import CoreData
import Foundation
import UIKit
import UserNotifications

private enum NotificationServiceError: LocalizedError {
    case habitNotFound
    case invalidStoredCompletionSource

    var errorDescription: String? {
        switch self {
        case .habitNotFound:
            return "Habit notification target is missing."
        case .invalidStoredCompletionSource:
            return "Stored habit completion source is invalid."
        }
    }
}

final class NotificationService {
    private enum NotificationActionDayState {
        case current
        case inactive
        case failed
    }

    private let categoryIdentifier = "habit.reminder"
    private let summaryCategoryIdentifier = "habit.reminder.summary"
    private let completeActionIdentifier = "habit.complete"
    private let skipActionIdentifier = "habit.skip"
    private let schedulingWindowDays = 2
    private let aggregationThreshold = 3
    private let storeContext: NotificationStoreContext
    private let center = UNUserNotificationCenter.current()
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
        center.getPendingNotificationRequests { requests in
            guard !requests.contains(where: { $0.identifier.hasPrefix("habit_summary_") }) else {
                self.rescheduleAllNotifications()
                return
            }

            let requestsToAdd: [UNNotificationRequest]
            do {
                requestsToAdd = try self.makePendingNotificationRequests(forHabitID: habitID)
            } catch {
                ReliabilityLog.error("notification.habit.reschedule.item failed: \(error.localizedDescription)")
                return
            }

            self.removePendingNotifications(forHabitID: habitID) {
                self.addPendingNotificationRequests(
                    requestsToAdd,
                    logName: "notification.habit.reschedule.item"
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
            logName: "notification.habit.reschedule",
            now: clock.now,
            removeDeliveredAggregatedNotifications: removeDeliveredAggregatedNotifications(on:),
            removePendingNotifications: removePendingHabitNotifications(completion:),
            makePendingRequests: makePendingNotificationRequests,
            completion: completion
        )
    }

    func removePendingNotification(forHabitID habitID: UUID, on localDate: Date) {
        NotificationCleanupSupport.removePendingNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: habitID),
            on: localDate,
            calendar: calendar
        )
    }

    func removeNotifications(forHabitID habitID: UUID) {
        overdueAnchorStore.clearAnchorDay(for: .habit, id: habitID)
        rescheduleAllNotifications()
        removeDeliveredNotifications(forHabitID: habitID)
    }

    func removeDeliveredNotifications(forHabitID habitID: UUID) {
        NotificationCleanupSupport.removeDeliveredNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: habitID)
        )
    }

    func removeDeliveredNotifications(
        forHabitID habitID: UUID,
        on localDate: Date,
        notificationIdentifier: String? = nil
    ) {
        NotificationCleanupSupport.removeDeliveredNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: habitID),
            on: localDate,
            calendar: calendar,
            including: notificationIdentifier
        )
    }

    func removeDeliveredNotifications(
        forHabitID habitID: UUID,
        on localDate: Date,
        notificationIdentifier: String? = nil,
        completion: @escaping () -> Void
    ) {
        NotificationCleanupSupport.removeDeliveredNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: habitID),
            on: localDate,
            calendar: calendar,
            including: notificationIdentifier,
            completion: completion
        )
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
            notificationDate: response.notification.date,
            notificationIdentifier: response.notification.request.identifier
        )
    }

    func handleNotificationResponse(
        _ response: UNNotificationResponse,
        completion: @escaping (Bool) -> Void
    ) {
        guard
            let type = response.notification.request.content.userInfo["type"] as? String
        else {
            completion(false)
            return
        }

        handleNotificationResponse(
            type: type,
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier,
            notificationDate: response.notification.date,
            notificationIdentifier: response.notification.request.identifier,
            completion: completion
        )
    }

    @discardableResult
    func handleNotificationResponse(
        type: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        notificationDate: Date,
        notificationIdentifier: String? = nil
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
        switch notificationActionDayState(for: habitID, deliveryDay: deliveryDay) {
        case .current:
            break
        case .inactive:
            removeDeliveredNotifications(
                forHabitID: habitID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            )
            return true
        case .failed:
            return true
        }

        let actionOutcome: NotificationMutationOutcome
        switch actionIdentifier {
        case completeActionIdentifier:
            actionOutcome = createCompletionIfNeeded(for: habitID, on: deliveryDay, source: .notification)
        case skipActionIdentifier:
            actionOutcome = createSkippedCompletionIfNeeded(for: habitID, on: deliveryDay)
        default:
            return true
        }

        guard case .failed = actionOutcome else {
            clearOverdueAnchorIfNeeded(for: habitID, on: deliveryDay)
            removeDeliveredNotifications(
                forHabitID: habitID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            )
            if case .mutated = actionOutcome {
                rescheduleAllNotifications()
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
        onCleanupFinished: (() -> Void)? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        if handleDefaultTapRouting(type: type, actionIdentifier: actionIdentifier) {
            completion(true)
            return
        }

        guard
            let habitIDString = userInfo["habitID"] as? String,
            let habitID = UUID(uuidString: habitIDString)
        else {
            completion(true)
            return
        }

        let deliveryDay = localDate(from: userInfo, fallbackDate: notificationDate)
        switch notificationActionDayState(for: habitID, deliveryDay: deliveryDay) {
        case .current:
            break
        case .inactive:
            removeDeliveredNotifications(
                forHabitID: habitID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            ) {
                onCleanupFinished?()
                completion(true)
            }
            return
        case .failed:
            completion(true)
            return
        }

        let actionOutcome: NotificationMutationOutcome
        switch actionIdentifier {
        case completeActionIdentifier:
            actionOutcome = createCompletionIfNeeded(for: habitID, on: deliveryDay, source: .notification)
        case skipActionIdentifier:
            actionOutcome = createSkippedCompletionIfNeeded(for: habitID, on: deliveryDay)
        default:
            completion(true)
            return
        }

        guard case .failed = actionOutcome else {
            clearOverdueAnchorIfNeeded(for: habitID, on: deliveryDay)
            removeDeliveredNotifications(
                forHabitID: habitID,
                on: deliveryDay,
                notificationIdentifier: notificationIdentifier
            ) {
                onCleanupFinished?()
                if case .mutated = actionOutcome {
                    self.rescheduleAllNotifications()
                }
                completion(true)
            }
            return
        }

        completion(true)
    }

    private func notificationActionDayState(for habitID: UUID, deliveryDay: Date) -> NotificationActionDayState {
        let normalizedDeliveryDay = calendar.startOfDay(for: deliveryDay)

        do {
            let isCurrent = try storeContext.performRead { context in
                let habitRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
                habitRequest.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
                habitRequest.fetchLimit = 1

                guard let habit = try context.fetch(habitRequest).first else {
                    return false
                }

                var report = IntegrityReportBuilder()
                guard
                    let startDate = habit.dateValue(forKey: "startDate"),
                    let schedules = loadHabitSchedules(for: habit, habitID: habitID, report: &report),
                    let completionEntries = loadHabitCompletionEntries(for: habit, report: &report)
                else {
                    throw report.makeError(operation: "notification.habit.action.currentDay")
                }

                let reminderEnabled = habit.boolValue(forKey: "reminderEnabled")
                let reminderTime = ReminderValidation.validatedReminderTime(
                    from: habit,
                    reminderEnabled: reminderEnabled,
                    area: "notification.action.currentDay",
                    report: &report
                )
                guard !reminderEnabled || reminderTime != nil else {
                    throw report.makeError(operation: "notification.habit.action.currentDay")
                }

                let completedDays = Set(completionEntries.compactMap { $0.1.countsAsCompletion ? $0.0 : nil })
                let skippedDays = Set(completionEntries.compactMap { !$0.1.countsAsCompletion ? $0.0 : nil })
                let activeOverdueDay = ScheduledOverdueState.activeOverdueDay(
                    startDate: startDate,
                    schedules: schedules,
                    reminderTime: reminderTime,
                    positiveDays: completedDays,
                    skippedDays: skippedDays,
                    now: clock.now(),
                    calendar: calendar
                )

                return activeOverdueDay.map { calendar.startOfDay(for: $0) == normalizedDeliveryDay } ?? false
            }
            return isCurrent ? .current : .inactive
        } catch {
            ReliabilityLog.error("notification.habit.action.currentDay failed: \(error.localizedDescription)")
            return .failed
        }
    }

    private func insertSkippedCompletionIfNeeded(
        for habit: NSManagedObject,
        habitID: UUID,
        on localDate: Date,
        context: NSManagedObjectContext
    ) throws -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
        ])
        fetchRequest.fetchLimit = 1

        if try context.fetch(fetchRequest).first != nil {
            return false
        }

        let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
        completion.setValue(UUID(), forKey: "id")
        completion.setValue(habitID, forKey: "habitID")
        completion.setValue(normalizedDate, forKey: "localDate")
        completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
        completion.setValue(clock.now(), forKey: "createdAt")
        completion.setValue(habit, forKey: "habit")
        return true
    }

    private func loadHabitSchedules(
        for habitObject: NSManagedObject,
        habitID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [HabitScheduleVersion]? {
        CoreDataRelationshipLoadingSupport.validatedScheduleModels(
            from: habitObject,
            relationshipKey: "scheduleVersions",
            area: "notification.action.catchUp",
            missingFieldsMessage: "Habit schedule row is missing required fields.",
            invalidMaskMessage: "Habit schedule row contains invalid weekdayMask.",
            report: &report
        ) { scheduleID, rule, effectiveFrom, createdAt, version in
            HabitScheduleVersion(
                id: scheduleID,
                habitID: habitID,
                rule: rule,
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func postHabitStoreDidChangeIfActive() {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else { return }
            NotificationCenter.default.post(name: .habitStoreDidChange, object: nil)
        }
    }

    @discardableResult
    func handleDefaultTapRouting(type: String, actionIdentifier: String) -> Bool {
        NotificationResponseSupport.handleDefaultTapRouting(
            type: type,
            actionIdentifier: actionIdentifier,
            acceptedTypes: ["aggregated", "individual"],
            notificationName: .openMyHabitsTab
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

    func makePendingNotificationRequests() throws -> [UNNotificationRequest] {
        let habits = try storeContext.performRead(fetchHabitReminderConfigurations)
        let pills = try storeContext.performRead(fetchPillReminderConfigurations)
        let candidates = ReminderPlanningSupport.habitCandidates(
            reminders: habits,
            now: clock.now(),
            schedulingWindowDays: schedulingWindowDays,
            calendar: calendar
        )
        recordPendingOverdueAnchors(from: candidates)
        let deliveries = ReminderPlanningSupport.habitDeliveries(
            candidates: candidates,
            habits: habits,
            pills: pills,
            aggregationThreshold: aggregationThreshold,
            calendar: calendar
        )

        return deliveries.map(makeNotificationRequest(for:))
    }

    private func recordPendingOverdueAnchors(from candidates: [HabitNotificationCandidate]) {
        let candidateDaysByHabitID = Dictionary(grouping: candidates, by: \.habitID)
            .mapValues { candidates in
                Set(candidates.map { calendar.startOfDay(for: $0.localDate) })
            }
        let today = calendar.startOfDay(for: clock.now())

        for (habitID, candidateDays) in candidateDaysByHabitID {
            guard let earliestCandidateDay = candidateDays.sorted().first else { continue }
            if let currentAnchor = overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar) {
                if currentAnchor <= today {
                    continue
                }
                if candidateDays.contains(currentAnchor), currentAnchor <= earliestCandidateDay {
                    continue
                }
            }
            overdueAnchorStore.setAnchorDay(earliestCandidateDay, for: .habit, id: habitID, calendar: calendar)
        }
    }

    private func clearOverdueAnchorIfNeeded(for habitID: UUID, on day: Date) {
        guard
            let anchorDay = overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar),
            anchorDay == calendar.startOfDay(for: day)
        else {
            return
        }
        overdueAnchorStore.clearAnchorDay(for: .habit, id: habitID)
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
        try NotificationConfigurationSupport.fetchConfigurations(
            entityName: "Habit",
            operation: "notification.fetchHabitReminderConfigurations",
            context: context,
            build: makeReminderConfiguration(from:report:)
        )
    }

    private func fetchPillReminderConfigurations(context: NSManagedObjectContext) throws -> [PillReminderConfiguration] {
        try NotificationConfigurationSupport.fetchConfigurations(
            entityName: "Pill",
            operation: "notification.fetchPillReminderConfigurations",
            context: context,
            build: makePillReminderConfiguration(from:report:)
        )
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

        guard let scheduleHistory = loadHabitSchedules(for: object, habitID: id, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Habit reminder configuration failed because schedule rows are corrupted."
            )
            return nil
        }
        let scheduleRule = latestScheduleRule(from: scheduleHistory)
        let scheduleDays = scheduleRule.weeklyDays ?? .daily

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
            scheduleRule: scheduleRule,
            scheduleHistory: scheduleHistory,
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
        guard let scheduleHistory = loadPillSchedules(for: object, pillID: id, report: &report) else {
            report.append(
                area: "notification",
                entityName: object.entityName,
                object: object,
                message: "Pill reminder configuration failed because schedule rows are corrupted."
            )
            return nil
        }
        let scheduleRule = latestScheduleRule(from: scheduleHistory)
        let scheduleDays = scheduleRule.weeklyDays ?? .daily
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
            scheduleRule: scheduleRule,
            scheduleHistory: scheduleHistory,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            takenDays: takenDays,
            skippedDays: skippedDays
        )
    }

    private func latestScheduleDays<Schedule: HistoryScheduleVersionLike>(from schedules: [Schedule]) -> WeekdaySet {
        latestScheduleRule(from: schedules).weeklyDays ?? WeekdaySet(rawValue: 0)
    }

    private func latestScheduleRule<Schedule: HistoryScheduleVersionLike>(from schedules: [Schedule]) -> ScheduleRule {
        schedules.sorted { lhs, rhs in
            if lhs.effectiveFrom != rhs.effectiveFrom {
                return lhs.effectiveFrom > rhs.effectiveFrom
            }
            if lhs.version != rhs.version {
                return lhs.version > rhs.version
            }
            return lhs.createdAt > rhs.createdAt
        }.first?.rule ?? .weekly(WeekdaySet(rawValue: 0))
    }

    private func loadPillSchedules(
        for object: NSManagedObject,
        pillID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [PillScheduleVersion]? {
        CoreDataRelationshipLoadingSupport.validatedScheduleModels(
            from: object,
            relationshipKey: "scheduleVersions",
            area: "notification",
            missingFieldsMessage: "Pill schedule row is missing required fields.",
            invalidMaskMessage: "Pill schedule row contains invalid weekdayMask.",
            report: &report
        ) { scheduleID, rule, effectiveFrom, createdAt, version in
            PillScheduleVersion(
                id: scheduleID,
                pillID: pillID,
                rule: rule,
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

    @discardableResult
    private func createCompletionIfNeeded(
        for habitID: UUID,
        on localDate: Date,
        source: CompletionSource
    ) -> NotificationMutationOutcome {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let mutationResult = storeContext.performWrite({ context in
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
                    throw NotificationServiceError.invalidStoredCompletionSource
                }

                if existingSource == .skipped {
                    existing.setValue(source.rawValue, forKey: "sourceRaw")
                    existing.setValue(clock.now(), forKey: "createdAt")
                    try context.save()
                    return NotificationMutationOutcome.mutated
                }

                return NotificationMutationOutcome.noChange
            }

            let habitRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            habitRequest.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
            habitRequest.fetchLimit = 1

            guard let habit = try context.fetch(habitRequest).first else {
                return NotificationMutationOutcome.noChange
            }

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(habitID, forKey: "habitID")
            completion.setValue(normalizedDate, forKey: "localDate")
            completion.setValue(source.rawValue, forKey: "sourceRaw")
            completion.setValue(clock.now(), forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")

            try context.save()
            return .mutated
        })

        switch mutationResult {
        case .success(let outcome):
            if case .mutated = outcome {
                DispatchQueue.main.async {
                    guard UIApplication.shared.applicationState == .active else { return }
                    NotificationCenter.default.post(name: .habitStoreDidChange, object: nil)
                }
            }
            return outcome
        case .failure(let error):
            ReliabilityLog.error("notification.habit.action.store write failed: \(error.localizedDescription)")
            return .failed(error)
        }
    }

    @discardableResult
    private func createSkippedCompletionIfNeeded(for habitID: UUID, on localDate: Date) -> NotificationMutationOutcome {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let mutationResult = storeContext.performWrite({ context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "habitID == %@", habitID as CVarArg),
                NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
            ])
            fetchRequest.fetchLimit = 1

            if let existing = try context.fetch(fetchRequest).first {
                guard
                    let sourceRaw = existing.value(forKey: "sourceRaw") as? String,
                    CompletionSource(rawValue: sourceRaw) != nil
                else {
                    throw NotificationServiceError.invalidStoredCompletionSource
                }

                return NotificationMutationOutcome.noChange
            }

            let habitRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            habitRequest.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
            habitRequest.fetchLimit = 1

            guard let habit = try context.fetch(habitRequest).first else {
                return NotificationMutationOutcome.noChange
            }

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(habitID, forKey: "habitID")
            completion.setValue(normalizedDate, forKey: "localDate")
            completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
            completion.setValue(clock.now(), forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")

            try context.save()
            return .mutated
        })

        switch mutationResult {
        case .success(let outcome):
            if case .mutated = outcome {
                DispatchQueue.main.async {
                    guard UIApplication.shared.applicationState == .active else { return }
                    NotificationCenter.default.post(name: .habitStoreDidChange, object: nil)
                }
            }
            return outcome
        case .failure(let error):
            ReliabilityLog.error("notification.habit.action.store write failed: \(error.localizedDescription)")
            return .failed(error)
        }
    }

    private func removePendingHabitNotifications(completion: @escaping () -> Void) {
        LocalNotificationSupport.removePendingNotifications(center: center, prefix: "habit_", completion: completion)
    }

    private func removePendingNotifications(forHabitID habitID: UUID, completion: @escaping () -> Void) {
        LocalNotificationSupport.removePendingNotifications(
            center: center,
            prefix: notificationIdentifierPrefix(for: habitID),
            completion: completion
        )
    }

    private func makePendingNotificationRequests(forHabitID habitID: UUID) throws -> [UNNotificationRequest] {
        let habits = try storeContext.performRead(fetchHabitReminderConfigurations)
        let pills = try storeContext.performRead(fetchPillReminderConfigurations)
        guard let habit = habits.first(where: { $0.id == habitID }) else {
            return []
        }

        let candidates = ReminderPlanningSupport.habitCandidates(
            reminders: [habit],
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

    private func makeNotificationRequest(for delivery: HabitNotificationDeliveryPlan) -> UNNotificationRequest {
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
        for candidate: HabitNotificationCandidate,
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
        for candidates: [HabitNotificationCandidate],
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
    let scheduleRule: ScheduleRule
    let scheduleHistory: [HabitScheduleVersion]
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let completedDays: Set<Date>
    let skippedDays: Set<Date>

    init(
        id: UUID,
        name: String,
        startDate: Date,
        scheduleDays: WeekdaySet,
        scheduleRule: ScheduleRule? = nil,
        scheduleHistory: [HabitScheduleVersion] = [],
        reminderEnabled: Bool,
        reminderTime: ReminderTime?,
        completedDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.scheduleDays = scheduleDays
        self.scheduleRule = scheduleRule ?? .weekly(scheduleDays)
        self.scheduleHistory = scheduleHistory
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.completedDays = completedDays
        self.skippedDays = skippedDays
    }
}
