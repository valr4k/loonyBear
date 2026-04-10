import CoreData
import Foundation
import Testing
import UserNotifications
import XCTest

@testable import LoonyBear

@MainActor
@Suite
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
        draft.reminderTime = reminderTimeOneHourFromNow()

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
        draft.reminderTime = reminderTimeOneHourFromNow()

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

    private func reminderTimeOneHourFromNow() -> ReminderTime {
        let futureTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
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

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}
