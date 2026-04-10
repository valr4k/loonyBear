import CoreData
import Foundation
import UIKit
import UserNotifications

final class PillNotificationService {
    private let categoryIdentifier = "pill.reminder"
    private let summaryCategoryIdentifier = "pill.reminder.summary"
    private let takeActionIdentifier = "pill.take"
    private let skipActionIdentifier = "pill.skip"
    private let aggregationThreshold = 3
    private let schedulingWindowDays = 2
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

        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [takeAction, skipAction],
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
        removePendingPillNotifications {
            self.removeDeliveredAggregatedNotifications(on: Date())
            self.storeContext.refreshReadContext()

            let pills = self.storeContext.performRead(self.fetchReminderConfigurations) ?? []
            let habits: [HabitReminderConfiguration] = self.storeContext.performRead { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
                let habits = try context.fetch(request)
                return habits.compactMap(self.makeHabitReminderConfiguration(from:))
            } ?? []

            let candidates = pills.flatMap(self.reminderCandidates(for:))
            let groupedCandidates = Dictionary(grouping: candidates, by: \.scheduledDateTime)

            for group in groupedCandidates.values {
                for request in self.notificationRequests(for: group, habits: habits, pills: pills) {
                    self.center.add(request) { error in
                        if let error {
                            print("Failed to schedule notification \(request.identifier): \(error.localizedDescription)")
                        }
                    }
                }
            }
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

        if handleDefaultTapRouting(type: type, actionIdentifier: response.actionIdentifier) {
            return true
        }

        guard type == "pill" else { return false }

        guard
            let pillIDString = response.notification.request.content.userInfo["pillID"] as? String,
            let pillID = UUID(uuidString: pillIDString)
        else {
            return true
        }

        let deliveryDay = calendar.startOfDay(for: response.notification.date)
        let didMutateStore: Bool
        switch response.actionIdentifier {
        case takeActionIdentifier:
            didMutateStore = createIntakeIfNeeded(for: pillID, on: deliveryDay, source: .notification)
        case skipActionIdentifier:
            didMutateStore = createSkippedIntakeIfNeeded(for: pillID, on: deliveryDay)
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

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openMyPillsTab, object: nil)
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

    private func fetchReminderConfigurations(context: NSManagedObjectContext) throws -> [PillReminderConfiguration] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        let pills = try context.fetch(request)
        return pills.compactMap(makeReminderConfiguration(from:))
    }

    private func makeReminderConfiguration(from object: NSManagedObject) -> PillReminderConfiguration? {
        guard
            let id = object.uuidValue(forKey: "id"),
            let name = object.stringValue(forKey: "name"),
            let dosage = object.stringValue(forKey: "dosage"),
            let startDate = object.dateValue(forKey: "startDate")
        else {
            return nil
        }

        let reminderEnabled = object.boolValue(forKey: "reminderEnabled")
        let reminderHourValue = object.value(forKey: "reminderHour") as? Int16
        let reminderMinuteValue = object.value(forKey: "reminderMinute") as? Int16
        let reminderTime: ReminderTime?
        if let reminderHourValue, let reminderMinuteValue {
            reminderTime = ReminderTime(hour: Int(reminderHourValue), minute: Int(reminderMinuteValue))
        } else {
            reminderTime = nil
        }

        let latestSchedule = CoreDataScheduleSupport.latestScheduleObject(
            in: object.mutableSetValue(forKey: "scheduleVersions")
        )
        let weekdayMask = latestSchedule?.int16Value(forKey: "weekdayMask") ?? 0
        let intakes = (object.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
        let intakeEntries = intakes.compactMap { intakeObject -> (Date, PillCompletionSource)? in
            guard
                let localDate = intakeObject.dateValue(forKey: "localDate"),
                let sourceRaw = intakeObject.stringValue(forKey: "sourceRaw"),
                let source = PillCompletionSource(rawValue: sourceRaw)
            else {
                return nil
            }

            return (calendar.startOfDay(for: localDate), source)
        }
        let takenDays = Set(intakeEntries.compactMap { $0.1.countsAsIntake ? $0.0 : nil })
        let skippedDays = Set(intakeEntries.compactMap { !$0.1.countsAsIntake ? $0.0 : nil })

        return PillReminderConfiguration(
            id: id,
            name: name,
            dosage: dosage,
            startDate: startDate,
            scheduleDays: WeekdaySet(rawValue: weekdayMask),
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
        ]

        let triggerDate = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDateTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        return UNNotificationRequest(
            identifier: aggregatedNotificationIdentifier(for: scheduledDateTime),
            content: content,
            trigger: trigger
        )
    }

    private func makeHabitReminderConfiguration(from object: NSManagedObject) -> HabitReminderConfiguration? {
        guard
            let id = object.uuidValue(forKey: "id"),
            let name = object.stringValue(forKey: "name"),
            let startDate = object.dateValue(forKey: "startDate")
        else {
            return nil
        }

        let latestSchedule = CoreDataScheduleSupport.latestScheduleObject(
            in: object.mutableSetValue(forKey: "scheduleVersions")
        )
        let weekdayMask = latestSchedule?.int16Value(forKey: "weekdayMask") ?? 0
        let reminderEnabled = object.boolValue(forKey: "reminderEnabled")
        let hour = object.int16Value(forKey: "reminderHour")
        let minute = object.int16Value(forKey: "reminderMinute")
        let completions = (object.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
        let completionEntries = completions.compactMap { completion -> (Date, CompletionSource)? in
            guard
                let localDate = completion.dateValue(forKey: "localDate"),
                let sourceRaw = completion.stringValue(forKey: "sourceRaw"),
                let source = CompletionSource(rawValue: sourceRaw)
            else {
                return nil
            }

            return (calendar.startOfDay(for: localDate), source)
        }
        let completedDays = Set(completionEntries.compactMap { $0.1.countsAsCompletion ? $0.0 : nil })
        let skippedDays = Set(completionEntries.compactMap { !$0.1.countsAsCompletion ? $0.0 : nil })

        return HabitReminderConfiguration(
            id: id,
            name: name,
            startDate: startDate,
            scheduleDays: WeekdaySet(rawValue: weekdayMask),
            reminderEnabled: reminderEnabled,
            reminderTime: reminderEnabled ? ReminderTime(hour: hour, minute: minute) : nil,
            completedDays: completedDays,
            skippedDays: skippedDays
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
