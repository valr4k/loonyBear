import CoreData
import Foundation
import Testing
import UserNotifications
import XCTest

@testable import LoonyBear

@MainActor
@Suite(.serialized)
struct NotificationServiceTests {
    @Test
    func habitSchedulingUsesCurrentTwoDayWindow() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        try await clearNotifications()

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeMinutesFromNow(5)

        let expectedCount = expectedRequestCount(
            reminderTime: draft.reminderTime,
            schedulingWindowDays: 2
        )
        let habitID = try repository.createHabit(from: draft)

        service.rescheduleAllNotifications()

        let requests = try await waitForPendingRequests(expectedCount: expectedCount)
        let identifiers = Set(requests.map(\.identifier))

        #expect(requests.count == expectedCount)
        #expect(identifiers.count == expectedCount)
        #expect(requests.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == false })
        #expect(requests.allSatisfy { $0.identifier.hasPrefix("habit_\(habitID.uuidString.lowercased())_") })

        try await clearNotifications()
    }

    @Test
    func pillSchedulingUsesCurrentTwoDayWindow() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        try await clearNotifications()

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeHoursFromNow(2)

        let expectedCount = expectedRequestCount(
            reminderTime: draft.reminderTime,
            schedulingWindowDays: 2
        )
        let pillID = try repository.createPill(from: draft)

        service.rescheduleAllNotifications()

        let requests = try await waitForPendingRequests(expectedCount: expectedCount)
        let identifiers = Set(requests.map(\.identifier))

        #expect(requests.count == expectedCount)
        #expect(identifiers.count == expectedCount)
        #expect(requests.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == false })
        #expect(requests.allSatisfy { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") })

        try await clearNotifications()
    }

    @Test
    func aggregationUsesDistinctSummaryIdentifiersPerDomain() async throws {
        let persistence = PersistenceController(inMemory: true)
        let habitRepository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let habitService = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillService = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        try await clearNotifications()

        let reminderTime = reminderTimeOneHourFromNow()
        let expectedGroupsPerDomain = expectedRequestCount(
            reminderTime: reminderTime,
            schedulingWindowDays: 2
        )

        for index in 0..<3 {
            var habitDraft = CreateHabitDraft()
            habitDraft.name = "Habit \(index)"
            habitDraft.startDate = Calendar.current.startOfDay(for: Date())
            habitDraft.scheduleDays = .daily
            habitDraft.reminderEnabled = true
            habitDraft.reminderTime = reminderTime
            _ = try habitRepository.createHabit(from: habitDraft)

            var pillDraft = PillDraft()
            pillDraft.name = "Pill \(index)"
            pillDraft.dosage = "1 tablet"
            pillDraft.startDate = Calendar.current.startOfDay(for: Date())
            pillDraft.scheduleDays = .daily
            pillDraft.reminderEnabled = true
            pillDraft.reminderTime = reminderTime
            _ = try pillRepository.createPill(from: pillDraft)
        }

        habitService.rescheduleAllNotifications()
        pillService.rescheduleAllNotifications()

        let requests = try await waitForPendingRequests(expectedCount: expectedGroupsPerDomain * 2)
        let habitSummaryIdentifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix("habit_summary_") }
        let pillSummaryIdentifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix("pill_summary_") }

        #expect(habitSummaryIdentifiers.count == expectedGroupsPerDomain)
        #expect(pillSummaryIdentifiers.count == expectedGroupsPerDomain)
        #expect(Set(habitSummaryIdentifiers).count == habitSummaryIdentifiers.count)
        #expect(Set(pillSummaryIdentifiers).count == pillSummaryIdentifiers.count)
        #expect(Set(habitSummaryIdentifiers).isDisjoint(with: Set(pillSummaryIdentifiers)))

        try await clearNotifications()
    }

    @Test
    func habitDefaultTapRoutingPostsOpenHabitsSignal() {
        let persistence = PersistenceController(inMemory: true)
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let firstExpectation = XCTNSNotificationExpectation(name: .openMyHabitsTab)
        #expect(service.handleDefaultTapRouting(type: "individual", actionIdentifier: UNNotificationDefaultActionIdentifier))
        #expect(XCTWaiter.wait(for: [firstExpectation], timeout: 1) == .completed)

        let secondExpectation = XCTNSNotificationExpectation(name: .openMyHabitsTab)
        #expect(service.handleDefaultTapRouting(type: "aggregated", actionIdentifier: UNNotificationDefaultActionIdentifier))
        #expect(XCTWaiter.wait(for: [secondExpectation], timeout: 1) == .completed)
    }

    @Test
    func pillDefaultTapRoutingPostsOpenPillsSignal() {
        let persistence = PersistenceController(inMemory: true)
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let firstExpectation = XCTNSNotificationExpectation(name: .openMyPillsTab)
        #expect(service.handleDefaultTapRouting(type: "pill", actionIdentifier: UNNotificationDefaultActionIdentifier))
        #expect(XCTWaiter.wait(for: [firstExpectation], timeout: 1) == .completed)

        let secondExpectation = XCTNSNotificationExpectation(name: .openMyPillsTab)
        #expect(service.handleDefaultTapRouting(type: "pill_aggregated", actionIdentifier: UNNotificationDefaultActionIdentifier))
        #expect(XCTWaiter.wait(for: [secondExpectation], timeout: 1) == .completed)
    }

    @Test
    func individualNotificationCategoriesIncludeSkippedActions() throws {
        let persistence = PersistenceController(inMemory: true)
        let habitService = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillService = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let habitCategory = try #require(
            habitService.notificationCategories().first { $0.identifier == "habit.reminder" }
        )
        let pillCategory = try #require(
            pillService.notificationCategories().first { $0.identifier == "pill.reminder" }
        )

        #expect(habitCategory.actions.map(\.identifier) == ["habit.complete", "habit.skip"])
        #expect(pillCategory.actions.map(\.identifier) == ["pill.take", "pill.skip"])
    }

    @Test
    func habitReminderReschedulesAfterEdit() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        try await clearNotifications()

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let habitID = try repository.createHabit(from: draft)

        service.rescheduleAllNotifications()
        let initialRequests = try await waitForPendingRequests(
            expectedCount: expectedRequestCount(reminderTime: draft.reminderTime, schedulingWindowDays: 2)
        )
        let initialIdentifiers = Set(initialRequests.map(\.identifier))

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        let updatedDraft = EditHabitDraft(
            id: habitID,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: true,
            reminderTime: reminderTimeHoursFromNow(3),
            completedDays: [],
            skippedDays: []
        )
        try repository.updateHabit(from: updatedDraft)

        service.rescheduleAllNotifications()
        _ = try await waitForPendingRequests(
            expectedCount: expectedRequestCount(reminderTime: updatedDraft.reminderTime, schedulingWindowDays: 2)
        )
        let updatedIdentifiers = try await waitForPendingIdentifiers(
            expectedCount: expectedRequestCount(reminderTime: updatedDraft.reminderTime, schedulingWindowDays: 2)
        ) { identifiers in
            identifiers != initialIdentifiers
        }

        #expect(!updatedIdentifiers.isEmpty)
        #expect(updatedIdentifiers != initialIdentifiers)

        try await clearNotifications()
    }

    @Test
    func habitNotificationRequestsFailOnCorruptedCompletionRow() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let habitObject = try #require(context.fetch(request).first)
        let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
        completion.setValue(UUID(), forKey: "id")
        completion.setValue(habitID, forKey: "habitID")
        completion.setValue(Calendar.current.startOfDay(for: Date()), forKey: "localDate")
        completion.setValue("broken_source", forKey: "sourceRaw")
        completion.setValue(Date(), forKey: "createdAt")
        completion.setValue(habitObject, forKey: "habit")
        try context.save()

        do {
            _ = try service.makePendingNotificationRequests()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "notification.fetchHabitReminderConfigurations")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func pillNotificationRequestsFailOnCorruptedIntakeRow() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let pillID = try repository.createPill(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        request.fetchLimit = 1
        let pillObject = try #require(context.fetch(request).first)
        let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
        intake.setValue(UUID(), forKey: "id")
        intake.setValue(pillID, forKey: "pillID")
        intake.setValue(Calendar.current.startOfDay(for: Date()), forKey: "localDate")
        intake.setValue("broken_source", forKey: "sourceRaw")
        intake.setValue(Date(), forKey: "createdAt")
        intake.setValue(pillObject, forKey: "pill")
        try context.save()

        do {
            _ = try service.makePendingNotificationRequests()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "notification.fetchPillReminderConfigurations")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func habitNotificationRequestsFailWhenReminderHourIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderHour")
        try context.save()

        do {
            _ = try service.makePendingNotificationRequests()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "notification.fetchHabitReminderConfigurations")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func habitNotificationRequestsFailWhenReminderMinuteIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        do {
            _ = try service.makePendingNotificationRequests()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "notification.fetchHabitReminderConfigurations")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func habitNotificationRequestsFailWhenReminderHourIsOutOfRange() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(Int16(24), forKey: "reminderHour")
        try context.save()

        do {
            _ = try service.makePendingNotificationRequests()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "notification.fetchHabitReminderConfigurations")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func habitNotificationRequestsFailWhenReminderMinuteIsOutOfRange() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let habitID = try repository.createHabit(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(Int16(60), forKey: "reminderMinute")
        try context.save()

        do {
            _ = try service.makePendingNotificationRequests()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "notification.fetchHabitReminderConfigurations")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func habitRescheduleFailureKeepsExistingPendingNotifications() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        try await clearNotifications()

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeMinutesFromNow(20)
        let habitID = try repository.createHabit(from: draft)

        let expectedCount = expectedRequestCount(reminderTime: draft.reminderTime, schedulingWindowDays: 2)
        service.rescheduleAllNotifications()
        let initialRequests = try await waitForPendingRequests(expectedCount: expectedCount)
        let initialIdentifiers = Set(initialRequests.map(\.identifier))

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", habitID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderHour")
        try context.save()

        service.rescheduleAllNotifications()
        try await Task.sleep(for: .milliseconds(300))

        let preservedRequests = await pendingRequests()
        #expect(Set(preservedRequests.map(\.identifier)) == initialIdentifiers)

        try await clearNotifications()
    }

    @Test
    func pillNotificationRequestsFailWhenReminderMinuteIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        var draft = PillDraft()
        draft.name = "Omega 3"
        draft.dosage = "2 capsules"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeOneHourFromNow()
        let pillID = try repository.createPill(from: draft)

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        do {
            _ = try service.makePendingNotificationRequests()
            Issue.record("Expected data integrity error.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "notification.fetchPillReminderConfigurations")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func pillRescheduleFailureKeepsExistingPendingNotifications() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        try await clearNotifications()

        var draft = PillDraft()
        draft.name = "Omega 3"
        draft.dosage = "2 capsules"
        draft.startDate = Calendar.current.startOfDay(for: Date())
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeMinutesFromNow(20)
        let pillID = try repository.createPill(from: draft)

        let expectedCount = expectedRequestCount(reminderTime: draft.reminderTime, schedulingWindowDays: 2)
        service.rescheduleAllNotifications()
        let initialRequests = try await waitForPendingRequests(expectedCount: expectedCount)
        let initialIdentifiers = Set(initialRequests.map(\.identifier))

        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", pillID as CVarArg)
        request.fetchLimit = 1
        let object = try #require(context.fetch(request).first)
        object.setValue(nil, forKey: "reminderMinute")
        try context.save()

        service.rescheduleAllNotifications()
        try await Task.sleep(for: .milliseconds(300))

        let preservedRequests = await pendingRequests()
        #expect(Set(preservedRequests.map(\.identifier)) == initialIdentifiers)

        try await clearNotifications()
    }

    private func reminderTimeOneHourFromNow() -> ReminderTime {
        let futureTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: futureTime)
        return ReminderTime(
            hour: components.hour ?? 20,
            minute: components.minute ?? 0
        )
    }

    private func reminderTimeHoursFromNow(_ hours: Int) -> ReminderTime {
        let futureTime = Calendar.current.date(byAdding: .hour, value: hours, to: Date()) ?? Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: futureTime)
        return ReminderTime(
            hour: components.hour ?? 20,
            minute: components.minute ?? 0
        )
    }

    private func reminderTimeMinutesFromNow(_ minutes: Int) -> ReminderTime {
        let futureTime = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: futureTime)
        return ReminderTime(
            hour: components.hour ?? 20,
            minute: components.minute ?? 0
        )
    }

    private func expectedRequestCount(reminderTime: ReminderTime, schedulingWindowDays: Int) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        return (0..<schedulingWindowDays).reduce(into: 0) { count, offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return }
            guard let scheduledDate = calendar.date(
                bySettingHour: reminderTime.hour,
                minute: reminderTime.minute,
                second: 0,
                of: day
            ) else {
                return
            }
            if scheduledDate > now {
                count += 1
            }
        }
    }

    private func clearNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        try await Task.sleep(for: .milliseconds(50))
    }

    private func waitForPendingRequests(expectedCount: Int) async throws -> [UNNotificationRequest] {
        for _ in 0..<20 {
            let requests = await pendingRequests()
            if requests.count == expectedCount {
                return requests
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        return await pendingRequests()
    }

    private func waitForPendingIdentifiers(
        expectedCount: Int,
        until predicate: (Set<String>) -> Bool
    ) async throws -> Set<String> {
        for _ in 0..<20 {
            let identifiers = Set(await pendingRequests().map(\.identifier))
            if identifiers.count == expectedCount, predicate(identifiers) {
                return identifiers
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        return Set(await pendingRequests().map(\.identifier))
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}
