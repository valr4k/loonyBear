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
        draft.reminderTime = reminderTimeHoursFromNow(2)

        let expectedCount = expectedRequestCount(
            reminderTime: draft.reminderTime,
            schedulingWindowDays: 2
        )
        let habitID = try repository.createHabit(from: draft)

        service.rescheduleAllNotifications()

        let requests = try await waitForPendingRequests(
            expectedCount: expectedCount,
            matching: { $0.identifier.hasPrefix("habit_\(habitID.uuidString.lowercased())_") }
        )
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

        let requests = try await waitForPendingRequests(
            expectedCount: expectedCount,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )
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

        let requests = try await waitForPendingRequests(
            expectedCount: expectedGroupsPerDomain * 2,
            matching: {
                $0.identifier.hasPrefix("habit_summary_") || $0.identifier.hasPrefix("pill_summary_")
            }
        )
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
        #expect(pillCategory.actions.map(\.identifier) == ["pill.take", "pill.skip", "pill.remind_later"])
    }

    @Test
    func habitCompleteActionUsesPayloadLocalDateAfterMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let today = Calendar.current.startOfDay(for: Date())
        let notificationDate = Calendar.current.date(byAdding: .hour, value: 1, to: today) ?? today

        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = yesterday
        draft.scheduleDays = Calendar.current.weekdaySet(for: today)
        let habitID = try repository.createHabit(from: draft)

        let userInfo: [AnyHashable: Any] = [
            "type": "individual",
            "habitID": habitID.uuidString,
            "localDate": LocalNotificationSupport.localDateIdentifier(for: yesterday, calendar: .current),
        ]

        #expect(service.handleNotificationResponse(
            type: "individual",
            userInfo: userInfo,
            actionIdentifier: "habit.complete",
            notificationDate: notificationDate
        ))

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.completedDays.contains(yesterday))
        #expect(!details.completedDays.contains(today))
        #expect(!details.skippedDays.contains(today))
    }

    @Test
    func habitSkipActionUsesPayloadLocalDateAfterMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let today = Calendar.current.startOfDay(for: Date())
        let notificationDate = Calendar.current.date(byAdding: .hour, value: 1, to: today) ?? today

        var draft = CreateHabitDraft()
        draft.name = "Read"
        draft.startDate = yesterday
        draft.scheduleDays = Calendar.current.weekdaySet(for: today)
        let habitID = try repository.createHabit(from: draft)

        let userInfo: [AnyHashable: Any] = [
            "type": "individual",
            "habitID": habitID.uuidString,
            "localDate": LocalNotificationSupport.localDateIdentifier(for: yesterday, calendar: .current),
        ]

        #expect(service.handleNotificationResponse(
            type: "individual",
            userInfo: userInfo,
            actionIdentifier: "habit.skip",
            notificationDate: notificationDate
        ))

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.skippedDays.contains(yesterday))
        #expect(!details.skippedDays.contains(today))
        #expect(!details.completedDays.contains(today))
    }

    @Test
    func pillTakeActionUsesPayloadLocalDateAfterMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let today = Calendar.current.startOfDay(for: Date())
        let notificationDate = Calendar.current.date(byAdding: .hour, value: 1, to: today) ?? today

        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = yesterday
        let pillID = try repository.createPill(from: draft)
        try repository.clearPillDayStateToday(id: pillID)

        let userInfo: [AnyHashable: Any] = [
            "type": "pill",
            "pillID": pillID.uuidString,
            "localDate": LocalNotificationSupport.localDateIdentifier(for: yesterday, calendar: .current),
        ]

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: userInfo,
            actionIdentifier: "pill.take",
            notificationDate: notificationDate
        ))

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(details.takenDays.contains(yesterday))
        #expect(!details.takenDays.contains(today))
        #expect(!details.skippedDays.contains(today))
    }

    @Test
    func pillSkipActionUsesPayloadLocalDateAfterMidnight() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let today = Calendar.current.startOfDay(for: Date())
        let notificationDate = Calendar.current.date(byAdding: .hour, value: 1, to: today) ?? today

        var draft = PillDraft()
        draft.name = "Omega 3"
        draft.dosage = "2 capsules"
        draft.startDate = yesterday
        let pillID = try repository.createPill(from: draft)
        try repository.clearPillDayStateToday(id: pillID)

        let userInfo: [AnyHashable: Any] = [
            "type": "pill",
            "pillID": pillID.uuidString,
            "localDate": LocalNotificationSupport.localDateIdentifier(for: yesterday, calendar: .current),
        ]

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: userInfo,
            actionIdentifier: "pill.skip",
            notificationDate: notificationDate
        ))

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(details.skippedDays.contains(yesterday))
        #expect(!details.skippedDays.contains(today))
        #expect(!details.takenDays.contains(today))
    }

    @Test
    func pillRemindLaterActionSchedulesNotificationInTenMinutes() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        let pillID = try repository.createPill(from: draft)

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Vitamin D",
            fallbackBody: "Take 1 tablet."
        ))

        let requests = try await waitForPendingRequests(
            expectedCount: 1,
            matching: { $0.identifier.contains("remindlater_") }
        )
        let request = try #require(requests.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        let nextTriggerDate = try #require(trigger.nextTriggerDate())
        let interval = nextTriggerDate.timeIntervalSinceNow

        #expect(request.content.categoryIdentifier == "pill.reminder")
        #expect(request.content.title == "Vitamin D")
        #expect(request.content.body == "Take 1 tablet.")
        #expect(interval >= 9 * 60)
        #expect(interval <= 11 * 60)

        try await clearNotifications()
    }

    @Test
    func pillRemindLaterSurvivesGlobalReschedule() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeHoursFromNow(2)
        let pillID = try repository.createPill(from: draft)
        let expectedRegularCount = expectedRequestCount(reminderTime: draft.reminderTime, schedulingWindowDays: 2)

        service.rescheduleAllNotifications()
        _ = try await waitForPendingRequests(
            expectedCount: expectedRegularCount,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") && !$0.identifier.contains("remindlater_") }
        )

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Vitamin D",
            fallbackBody: "Take 1 tablet."
        ))

        _ = try await waitForPendingRequests(
            expectedCount: expectedRegularCount + 1,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )

        service.rescheduleAllNotifications()

        let requests = try await waitForPendingRequests(
            expectedCount: expectedRegularCount + 1,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )
        let snoozedRequests = requests.filter { $0.identifier.contains("remindlater_") }
        let regularRequests = requests.filter { !$0.identifier.contains("remindlater_") }

        #expect(snoozedRequests.count == 1)
        #expect(regularRequests.count == expectedRegularCount)

        try await clearNotifications()
    }

    @Test
    func pillRemindLaterSurvivesAppActiveFlow() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Magnesium"
        draft.dosage = "1 capsule"
        draft.startDate = today
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeHoursFromNow(2)
        let pillID = try repository.createPill(from: draft)
        let expectedRegularCount = expectedRequestCount(reminderTime: draft.reminderTime, schedulingWindowDays: 2)

        service.rescheduleAllNotifications()
        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Magnesium",
            fallbackBody: "Take 1 capsule."
        ))

        _ = try await waitForPendingRequests(
            expectedCount: expectedRegularCount + 1,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )

        service.handleAppDidBecomeActive()

        let requests = try await waitForPendingRequests(
            expectedCount: expectedRegularCount + 1,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )

        #expect(requests.contains { $0.identifier.contains("remindlater_") })

        try await clearNotifications()
    }

    @Test
    func pillRemindLaterSurvivesUnrelatedPillUpdateReschedule() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())

        var firstDraft = PillDraft()
        firstDraft.name = "Vitamin D"
        firstDraft.dosage = "1 tablet"
        firstDraft.startDate = today
        firstDraft.scheduleDays = .daily
        firstDraft.reminderEnabled = true
        firstDraft.reminderTime = reminderTimeHoursFromNow(2)
        let firstPillID = try repository.createPill(from: firstDraft)

        var secondDraft = PillDraft()
        secondDraft.name = "Omega 3"
        secondDraft.dosage = "2 capsules"
        secondDraft.startDate = today
        secondDraft.scheduleDays = .daily
        secondDraft.reminderEnabled = true
        secondDraft.reminderTime = reminderTimeHoursFromNow(3)
        let secondPillID = try repository.createPill(from: secondDraft)

        service.rescheduleAllNotifications()
        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": firstPillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Vitamin D",
            fallbackBody: "Take 1 tablet."
        ))

        let secondDetails = try #require(try repository.fetchPillDetails(id: secondPillID))
        let updatedDraft = EditPillDraft(
            id: secondPillID,
            name: secondDetails.name,
            dosage: secondDetails.dosage,
            details: secondDetails.details ?? "",
            startDate: secondDetails.startDate,
            historyMode: secondDetails.historyMode,
            scheduleDays: secondDetails.scheduleDays,
            reminderEnabled: true,
            reminderTime: reminderTimeHoursFromNow(4),
            takenDays: secondDetails.takenDays,
            skippedDays: secondDetails.skippedDays
        )
        try repository.updatePill(from: updatedDraft)

        service.rescheduleNotifications(forPillID: secondPillID)

        let snoozedRequests = try await waitForPendingRequests(
            expectedCount: 1,
            matching: {
                $0.identifier.hasPrefix("pill_\(firstPillID.uuidString.lowercased())_") &&
                $0.identifier.contains("remindlater_")
            }
        )

        #expect(snoozedRequests.count == 1)

        try await clearNotifications()
    }

    @Test
    func pillTakeRemovesSnoozedReminderForSameDay() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        let pillID = try repository.createPill(from: draft)
        try repository.clearPillDayStateToday(id: pillID)

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Vitamin D",
            fallbackBody: "Take 1 tablet."
        ))
        _ = try await waitForPendingRequests(expectedCount: 1, matching: { $0.identifier.contains("remindlater_") })

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.take",
            notificationDate: Date()
        ))

        let remainingRequests = try await waitForPendingRequests(
            expectedCount: 0,
            matching: {
                $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") &&
                $0.identifier.contains("remindlater_")
            }
        )
        #expect(remainingRequests.isEmpty)

        try await clearNotifications()
    }

    @Test
    func pillSkipRemovesSnoozedReminderForSameDay() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Omega 3"
        draft.dosage = "2 capsules"
        draft.startDate = today
        let pillID = try repository.createPill(from: draft)
        try repository.clearPillDayStateToday(id: pillID)

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Omega 3",
            fallbackBody: "Take 2 capsules."
        ))
        _ = try await waitForPendingRequests(expectedCount: 1, matching: { $0.identifier.contains("remindlater_") })

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.skip",
            notificationDate: Date()
        ))

        let remainingRequests = try await waitForPendingRequests(
            expectedCount: 0,
            matching: {
                $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") &&
                $0.identifier.contains("remindlater_")
            }
        )
        #expect(remainingRequests.isEmpty)

        try await clearNotifications()
    }

    @Test
    func deletingPillRemovesSnoozedReminder() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Zinc"
        draft.dosage = "1 tablet"
        draft.startDate = today
        let pillID = try repository.createPill(from: draft)

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Zinc",
            fallbackBody: "Take 1 tablet."
        ))
        _ = try await waitForPendingRequests(expectedCount: 1, matching: { $0.identifier.contains("remindlater_") })

        try repository.deletePill(id: pillID)
        service.removeNotifications(forPillID: pillID)

        let remainingRequests = try await waitForPendingRequests(
            expectedCount: 0,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )
        #expect(remainingRequests.isEmpty)

        try await clearNotifications()
    }

    @Test
    func pillRegularRescheduleReplacesOnlyRegularReminders() async throws {
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

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        draft.scheduleDays = .daily
        draft.reminderEnabled = true
        draft.reminderTime = reminderTimeHoursFromNow(2)
        let pillID = try repository.createPill(from: draft)

        let initialRegularCount = expectedRequestCount(reminderTime: draft.reminderTime, schedulingWindowDays: 2)
        service.rescheduleAllNotifications()
        let initialRegularIdentifiers = try await waitForPendingIdentifiers(
            expectedCount: initialRegularCount,
            matching: {
                $0.hasPrefix("pill_\(pillID.uuidString.lowercased())_") &&
                !$0.contains("remindlater_")
            }
        ) { _ in true }

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: [
                "type": "pill",
                "pillID": pillID.uuidString,
                "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
            ],
            actionIdentifier: "pill.remind_later",
            notificationDate: Date(),
            fallbackTitle: "Vitamin D",
            fallbackBody: "Take 1 tablet."
        ))

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        let updatedDraft = EditPillDraft(
            id: pillID,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            historyMode: details.historyMode,
            scheduleDays: details.scheduleDays,
            reminderEnabled: true,
            reminderTime: reminderTimeHoursFromNow(4),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )
        try repository.updatePill(from: updatedDraft)

        let updatedRegularCount = expectedRequestCount(reminderTime: updatedDraft.reminderTime, schedulingWindowDays: 2)
        service.rescheduleAllNotifications()

        let updatedRegularIdentifiers = try await waitForPendingIdentifiers(
            expectedCount: updatedRegularCount,
            matching: {
                $0.hasPrefix("pill_\(pillID.uuidString.lowercased())_") &&
                !$0.contains("remindlater_")
            }
        ) { identifiers in
            identifiers != initialRegularIdentifiers
        }
        let snoozedRequests = await pendingRequests {
            $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") && $0.identifier.contains("remindlater_")
        }

        #expect(updatedRegularIdentifiers != initialRegularIdentifiers)
        #expect(snoozedRequests.count == 1)

        try await clearNotifications()
    }

    @Test
    func habitNotificationActionFallsBackToNotificationDateWhenLocalDateIsMissing() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let today = Calendar.current.startOfDay(for: Date())
        let notificationDate = Calendar.current.date(byAdding: .hour, value: 1, to: today) ?? today

        var draft = CreateHabitDraft()
        draft.name = "Meditate"
        draft.startDate = yesterday
        draft.scheduleDays = Calendar.current.weekdaySet(for: today)
        let habitID = try repository.createHabit(from: draft)

        let userInfo: [AnyHashable: Any] = [
            "type": "individual",
            "habitID": habitID.uuidString,
        ]

        #expect(service.handleNotificationResponse(
            type: "individual",
            userInfo: userInfo,
            actionIdentifier: "habit.complete",
            notificationDate: notificationDate
        ))

        let details = try #require(try repository.fetchHabitDetails(id: habitID))
        #expect(details.completedDays.contains(today))
        #expect(!details.completedDays.contains(yesterday))
    }

    @Test
    func pillNotificationActionFallsBackToNotificationDateWhenLocalDateIsInvalid() throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let today = Calendar.current.startOfDay(for: Date())
        let notificationDate = Calendar.current.date(byAdding: .hour, value: 1, to: today) ?? today

        var draft = PillDraft()
        draft.name = "Magnesium"
        draft.dosage = "1 capsule"
        draft.startDate = yesterday
        let pillID = try repository.createPill(from: draft)
        try repository.clearPillDayStateToday(id: pillID)

        let userInfo: [AnyHashable: Any] = [
            "type": "pill",
            "pillID": pillID.uuidString,
            "localDate": "invalid-date",
        ]

        #expect(service.handleNotificationResponse(
            type: "pill",
            userInfo: userInfo,
            actionIdentifier: "pill.take",
            notificationDate: notificationDate
        ))

        let details = try #require(try repository.fetchPillDetails(id: pillID))
        #expect(details.takenDays.contains(today))
        #expect(!details.takenDays.contains(yesterday))
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
            expectedCount: expectedRequestCount(reminderTime: draft.reminderTime, schedulingWindowDays: 2),
            matching: { $0.identifier.hasPrefix("habit_\(habitID.uuidString.lowercased())_") }
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
            expectedCount: expectedRequestCount(reminderTime: updatedDraft.reminderTime, schedulingWindowDays: 2),
            matching: { $0.identifier.hasPrefix("habit_\(habitID.uuidString.lowercased())_") }
        )
        let updatedIdentifiers = try await waitForPendingIdentifiers(
            expectedCount: expectedRequestCount(reminderTime: updatedDraft.reminderTime, schedulingWindowDays: 2),
            matching: { $0.hasPrefix("habit_\(habitID.uuidString.lowercased())_") }
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
        let initialRequests = try await waitForPendingRequests(
            expectedCount: expectedCount,
            matching: { $0.identifier.hasPrefix("habit_\(habitID.uuidString.lowercased())_") }
        )
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

        let preservedRequests = await pendingRequests(
            matching: { $0.identifier.hasPrefix("habit_\(habitID.uuidString.lowercased())_") }
        )
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
        let initialRequests = try await waitForPendingRequests(
            expectedCount: expectedCount,
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )
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

        let preservedRequests = await pendingRequests(
            matching: { $0.identifier.hasPrefix("pill_\(pillID.uuidString.lowercased())_") }
        )
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

    private func waitForPendingRequests(
        expectedCount: Int,
        matching predicate: @escaping (UNNotificationRequest) -> Bool = { _ in true }
    ) async throws -> [UNNotificationRequest] {
        for _ in 0..<20 {
            let requests = await pendingRequests(matching: predicate)
            if requests.count == expectedCount {
                return requests
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        return await pendingRequests(matching: predicate)
    }

    private func waitForPendingIdentifiers(
        expectedCount: Int,
        matching filter: @escaping (String) -> Bool = { _ in true },
        until predicate: (Set<String>) -> Bool
    ) async throws -> Set<String> {
        for _ in 0..<20 {
            let identifiers = Set(await pendingRequests().map(\.identifier).filter(filter))
            if identifiers.count == expectedCount, predicate(identifiers) {
                return identifiers
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        return Set(await pendingRequests().map(\.identifier).filter(filter))
    }

    private func pendingRequests(
        matching predicate: @escaping (UNNotificationRequest) -> Bool = { _ in true }
    ) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.filter(predicate))
            }
        }
    }
}
