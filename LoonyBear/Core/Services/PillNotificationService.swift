import CoreData
import Foundation
import UIKit
import UserNotifications

final class PillNotificationService {
    private let categoryIdentifier = "pill.reminder"
    private let summaryCategoryIdentifier = "pill.reminder.summary"
    private let takeActionIdentifier = "pill.take"
    private let aggregationThreshold = 3
    private let schedulingWindowDays = 2
    private let readContext: NSManagedObjectContext
    private let makeWriteContext: () -> NSManagedObjectContext
    private let center = UNUserNotificationCenter.current()
    private let prefix = "pill_"

    private var calendar: Calendar {
        .autoupdatingCurrent
    }

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext
    ) {
        readContext = context
        self.makeWriteContext = makeWriteContext
    }

    func ensureAuthorizationIfNeeded() async -> Bool {
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

        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [takeAction],
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
            self.refreshReadContext()

            let reminders = self.performRead(self.fetchReminderConfigurations) ?? []
            let candidates = reminders.flatMap(self.reminderCandidates(for:))
            let groupedCandidates = Dictionary(grouping: candidates, by: \.scheduledDateTime)

            for group in groupedCandidates.values {
                for request in self.notificationRequests(for: group) {
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
            response.actionIdentifier == takeActionIdentifier,
            let pillIDString = response.notification.request.content.userInfo["pillID"] as? String,
            let pillID = UUID(uuidString: pillIDString)
        else {
            return true
        }

        let deliveryDay = calendar.startOfDay(for: response.notification.date)
        let didCreateIntake = createIntakeIfNeeded(for: pillID, on: deliveryDay, source: .notification)
        guard didCreateIntake else { return true }

        removeDeliveredNotifications(forPillID: pillID, on: deliveryDay)
        rescheduleAllNotifications()
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
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                guard notification.request.content.userInfo["type"] as? String == "pill_aggregated" else {
                    return nil
                }

                let deliveredDay = self.calendar.startOfDay(for: notification.date)
                return deliveredDay == normalizedDay ? notification.request.identifier : nil
            }

            self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private func cleanupStaleDeliveredNotifications() {
        let today = calendar.startOfDay(for: Date())
        center.getDeliveredNotifications { notifications in
            let staleIdentifiers = notifications.compactMap { notification -> String? in
                let notificationDay = self.calendar.startOfDay(for: notification.date)
                return notificationDay < today ? notification.request.identifier : nil
            }
            self.center.removeDeliveredNotifications(withIdentifiers: staleIdentifiers)
        }
    }

    private func fetchReminderConfigurations(context: NSManagedObjectContext) throws -> [PillReminderConfiguration] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        let pills = try context.fetch(request)
        return pills.compactMap(makeReminderConfiguration(from:))
    }

    private func makeReminderConfiguration(from object: NSManagedObject) -> PillReminderConfiguration? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let name = object.value(forKey: "name") as? String,
            let dosage = object.value(forKey: "dosage") as? String,
            let startDate = object.value(forKey: "startDate") as? Date
        else {
            return nil
        }

        let reminderEnabled = object.value(forKey: "reminderEnabled") as? Bool ?? false
        let reminderHourValue = object.value(forKey: "reminderHour") as? Int16
        let reminderMinuteValue = object.value(forKey: "reminderMinute") as? Int16
        let reminderTime: ReminderTime?
        if let reminderHourValue, let reminderMinuteValue {
            reminderTime = ReminderTime(hour: Int(reminderHourValue), minute: Int(reminderMinuteValue))
        } else {
            reminderTime = nil
        }

        let scheduleVersions = (object.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        let latestSchedule = scheduleVersions.sorted {
            let lhs = $0.value(forKey: "effectiveFrom") as? Date ?? .distantPast
            let rhs = $1.value(forKey: "effectiveFrom") as? Date ?? .distantPast
            if lhs != rhs {
                return lhs > rhs
            }

            let lhsVersion = $0.value(forKey: "version") as? Int32 ?? 0
            let rhsVersion = $1.value(forKey: "version") as? Int32 ?? 0
            if lhsVersion != rhsVersion {
                return lhsVersion > rhsVersion
            }

            let lhsCreatedAt = $0.value(forKey: "createdAt") as? Date ?? .distantPast
            let rhsCreatedAt = $1.value(forKey: "createdAt") as? Date ?? .distantPast
            return lhsCreatedAt > rhsCreatedAt
        }.first

        let weekdayMask = Int(latestSchedule?.value(forKey: "weekdayMask") as? Int16 ?? 0)
        let intakes = (object.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
        let takenDays = Set(intakes.compactMap { intakeObject in
            (intakeObject.value(forKey: "localDate") as? Date).map { calendar.startOfDay(for: $0) }
        })

        return PillReminderConfiguration(
            id: id,
            name: name,
            dosage: dosage,
            startDate: startDate,
            scheduleDays: WeekdaySet(rawValue: weekdayMask),
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            takenDays: takenDays
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
            guard reminder.scheduleDays.contains(calendar.pillWeekdaySet(for: normalizedDay)) else { return nil }
            guard !reminder.takenDays.contains(normalizedDay) else { return nil }
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

    private func notificationRequests(for candidates: [ScheduledPillReminderCandidate]) -> [UNNotificationRequest] {
        guard let firstCandidate = candidates.first else { return [] }

        if candidates.count < aggregationThreshold {
            return candidates.map(makeIndividualNotificationRequest)
        }

        return [makeAggregatedNotificationRequest(for: candidates, scheduledDateTime: firstCandidate.scheduledDateTime)]
    }

    private func makeIndividualNotificationRequest(for candidate: ScheduledPillReminderCandidate) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.pillName
        content.body = "Take \(candidate.dosage)."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
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
        scheduledDateTime: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Pills"
        content.body = "You have \(candidates.count) pills to take."
        content.sound = .default
        content.categoryIdentifier = summaryCategoryIdentifier
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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.string(from: date)
    }

    private func performRead<T>(_ work: (NSManagedObjectContext) throws -> T) -> T? {
        var result: T?
        readContext.performAndWait {
            result = try? work(readContext)
        }
        return result
    }

    @discardableResult
    private func createIntakeIfNeeded(for pillID: UUID, on localDate: Date, source: PillCompletionSource) -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let didCreate = performWrite { context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "pillID == %@", pillID as CVarArg),
                NSPredicate(format: "localDate == %@", normalizedDate as CVarArg),
            ])
            fetchRequest.fetchLimit = 1

            if try context.fetch(fetchRequest).isEmpty == false {
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

    private func performWrite<T>(_ work: (NSManagedObjectContext) throws -> T) -> T? {
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
            refreshReadContext()
            return value
        case .failure, .none:
            return nil
        }
    }

    private func refreshReadContext() {
        readContext.performAndWait {
            readContext.refreshAllObjects()
        }
    }

    private func removePendingPillNotifications(completion: @escaping () -> Void) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(self.prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
            completion()
        }
    }
}

private struct PillReminderConfiguration {
    let id: UUID
    let name: String
    let dosage: String
    let startDate: Date
    let scheduleDays: WeekdaySet
    let reminderEnabled: Bool
    let reminderTime: ReminderTime?
    let takenDays: Set<Date>
}

private struct ScheduledPillReminderCandidate {
    let pillID: UUID
    let pillName: String
    let dosage: String
    let localDate: Date
    let scheduledDateTime: Date
}

private extension Calendar {
    func pillWeekdaySet(for date: Date) -> WeekdaySet {
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
