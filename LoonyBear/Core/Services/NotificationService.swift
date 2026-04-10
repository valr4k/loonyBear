import CoreData
import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let habitStoreDidChange = Notification.Name("habit_store_did_change")
    static let pillStoreDidChange = Notification.Name("pill_store_did_change")
    static let openMyHabitsTab = Notification.Name("open_my_habits_tab")
    static let openMyPillsTab = Notification.Name("open_my_pills_tab")
}

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
    private let readContext: NSManagedObjectContext
    private let makeWriteContext: () -> NSManagedObjectContext
    private let center = UNUserNotificationCenter.current()

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
        removePendingHabitNotifications {
            self.removeDeliveredAggregatedNotifications(on: Date())
            self.refreshReadContext()

            let habits: [HabitReminderConfiguration] = self.performRead { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
                let habits = try context.fetch(request)
                return habits.compactMap(self.makeReminderConfiguration(from:))
            } ?? []

            let pills: [PillReminderConfiguration] = self.performRead { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
                let pills = try context.fetch(request)
                return pills.compactMap(self.makePillReminderConfiguration(from:))
            } ?? []

            let candidates = habits.flatMap(self.reminderCandidates(for:))
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
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                let userInfo = notification.request.content.userInfo
                guard userInfo["type"] as? String == "aggregated" else {
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
        guard
            let type = response.notification.request.content.userInfo["type"] as? String
        else {
            return false
        }

        if handleDefaultTapRouting(type: type, actionIdentifier: response.actionIdentifier) {
            return true
        }

        guard
            let habitIDString = response.notification.request.content.userInfo["habitID"] as? String,
            let habitID = UUID(uuidString: habitIDString)
        else {
            return true
        }

        let deliveryDay = calendar.startOfDay(for: response.notification.date)
        let didMutateStore: Bool
        switch response.actionIdentifier {
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

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openMyHabitsTab, object: nil)
        }
        return true
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

    private func loadHabit(id: UUID) -> HabitReminderConfiguration? {
        performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard
                let object = try context.fetch(request).first,
                let configuration = makeReminderConfiguration(from: object)
            else {
                throw NotificationServiceError.habitNotFound
            }

            return configuration
        }
    }

    private func makeReminderConfiguration(from object: NSManagedObject) -> HabitReminderConfiguration? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let name = object.value(forKey: "name") as? String,
            let startDate = object.value(forKey: "startDate") as? Date
        else {
            return nil
        }

        let schedules = (object.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        let latestSchedule = schedules
            .sorted {
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
            }
            .first

        let weekdayMask = Int(latestSchedule?.value(forKey: "weekdayMask") as? Int16 ?? 0)
        let reminderEnabled = object.value(forKey: "reminderEnabled") as? Bool ?? false
        let hour = Int(object.value(forKey: "reminderHour") as? Int16 ?? 0)
        let minute = Int(object.value(forKey: "reminderMinute") as? Int16 ?? 0)
        let completions = (object.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
        let completionEntries = completions.compactMap { completion -> (Date, CompletionSource)? in
            guard
                let localDate = completion.value(forKey: "localDate") as? Date,
                let sourceRaw = completion.value(forKey: "sourceRaw") as? String,
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

    private func makePillReminderConfiguration(from object: NSManagedObject) -> PillReminderConfiguration? {
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
        let intakeEntries = intakes.compactMap { intakeObject -> (Date, PillCompletionSource)? in
            guard
                let localDate = intakeObject.value(forKey: "localDate") as? Date,
                let sourceRaw = intakeObject.value(forKey: "sourceRaw") as? String,
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

    @discardableResult
    private func createCompletionIfNeeded(for habitID: UUID, on localDate: Date, source: CompletionSource) -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)

        let didCreate = performWrite { context in
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
        }

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

        let didCreate = performWrite { context in
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
        }

        if didCreate == true {
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else { return }
                NotificationCenter.default.post(name: .habitStoreDidChange, object: nil)
            }
            return true
        }

        return false
    }

    private func performRead<T>(_ work: (NSManagedObjectContext) throws -> T) -> T? {
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
        case .failure:
            return nil
        case .none:
            return nil
        }
    }

    private func refreshReadContext() {
        readContext.performAndWait {
            readContext.refreshAllObjects()
        }
    }

    private func removePendingHabitNotifications(completion: @escaping () -> Void) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("habit_") }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
            completion()
        }
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
            return value
        case .failure:
            return nil
        case .none:
            return nil
        }
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
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: localDate))
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d%02d%02d", year, month, day)
    }

    private func timestampString(for date: Date) -> String {
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

private extension Calendar {
    func weekdaySet(for date: Date) -> WeekdaySet {
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
