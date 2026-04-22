import CoreData
import Foundation
import Testing
@preconcurrency import UserNotifications
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

        await rescheduleAllNotifications(service)

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

        await rescheduleAllNotifications(service)

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

        await rescheduleAllNotifications(habitService)
        await rescheduleAllNotifications(pillService)

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
    func habitPlanningAggregatesMatchingCandidatesWithoutNotificationCenter() {
        let clock = makeUTCClock()
        let calendar = clock.calendar
        let now = makeUTCDate(year: 2025, month: 1, day: 10, hour: 8, minute: 0)
        let today = calendar.startOfDay(for: now)
        let reminderTime = ReminderTime(hour: 9, minute: 30)

        let habits = (0..<3).map { index in
            HabitReminderConfiguration(
                id: UUID(),
                name: "Habit \(index)",
                startDate: today,
                scheduleDays: .daily,
                reminderEnabled: true,
                reminderTime: reminderTime,
                completedDays: [],
                skippedDays: []
            )
        }

        let candidates = ReminderPlanningSupport.habitCandidates(
            reminders: habits,
            now: now,
            schedulingWindowDays: 2,
            calendar: calendar
        )
        let deliveries = ReminderPlanningSupport.habitDeliveries(
            candidates: candidates,
            habits: habits,
            pills: [],
            aggregationThreshold: 3,
            calendar: calendar
        )

        #expect(candidates.count == 6)
        #expect(deliveries.count == 2)
        #expect(deliveries.allSatisfy {
            if case .aggregated(let groupedCandidates, _, _) = $0 {
                return groupedCandidates.count == 3
            }
            return false
        })
    }

    @Test
    func pillPlanningFiltersPastTakenSkippedAndPreStartCandidatesWithoutNotificationCenter() {
        let clock = makeUTCClock()
        let calendar = clock.calendar
        let now = makeUTCDate(year: 2025, month: 1, day: 10, hour: 8, minute: 0)
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let pills = [
            PillReminderConfiguration(
                id: UUID(),
                name: "Future pill",
                dosage: "1 tablet",
                startDate: tomorrow,
                scheduleDays: .daily,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 9, minute: 0),
                takenDays: [],
                skippedDays: []
            ),
            PillReminderConfiguration(
                id: UUID(),
                name: "Taken today",
                dosage: "1 tablet",
                startDate: today,
                scheduleDays: .daily,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 9, minute: 0),
                takenDays: [today],
                skippedDays: []
            ),
            PillReminderConfiguration(
                id: UUID(),
                name: "Eligible",
                dosage: "1 tablet",
                startDate: today,
                scheduleDays: .daily,
                reminderEnabled: true,
                reminderTime: ReminderTime(hour: 9, minute: 0),
                takenDays: [],
                skippedDays: []
            ),
        ]

        let candidates = ReminderPlanningSupport.pillCandidates(
            reminders: pills,
            now: now,
            schedulingWindowDays: 2,
            calendar: calendar
        )

        #expect(candidates.count == 4)
        #expect(Set(candidates.map(\.pillName)) == ["Future pill", "Taken today", "Eligible"])
    }

    @Test
    func notificationRescheduleSupportCoalescesOverlappingRunsAndKeepsLatestRequests() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storeContext = NotificationStoreContext(
            readContext: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let center = UNUserNotificationCenter.current()
        let prefix = "coalesce_\(UUID().uuidString.lowercased())"
        let tracker = RescheduleInvocationTracker()

        try await clearNotifications()

        let removePendingNotifications: (@escaping () -> Void) -> Void = { completion in
            let callIndex = tracker.nextRemoveCall()
            let delay = callIndex == 1 ? 0.15 : 0.01

            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                completion()
            }
        }

        let makePendingRequests: () throws -> [UNNotificationRequest] = {
            let suffix = tracker.nextRequestSuffix()
            return [makeNotificationRequest(identifier: "\(prefix)_\(suffix)")]
        }

        async let first: Void = triggerRescheduleSupport(
            center: center,
            storeContext: storeContext,
            logName: "notification.test.coalesce",
            removePendingNotifications: removePendingNotifications,
            makePendingRequests: makePendingRequests
        )

        async let second: Void = triggerRescheduleSupport(
            center: center,
            storeContext: storeContext,
            logName: "notification.test.coalesce",
            removePendingNotifications: removePendingNotifications,
            makePendingRequests: makePendingRequests
        )

        _ = await (first, second)

        let requests = try await waitForPendingRequests(
            expectedCount: 1,
            matching: { $0.identifier.hasPrefix(prefix) }
        )
        let counts = tracker.counts

        #expect(counts.make == 2)
        #expect(counts.remove == 2)
        #expect(Set(requests.map(\.identifier)) == ["\(prefix)_new"])

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
    func habitActionCompletionWaitsForDeliveredCleanup() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let today = Calendar.current.startOfDay(for: Date())
        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = today
        draft.scheduleDays = .daily
        let habitID = try repository.createHabit(from: draft)

        final class SequencingState {
            var cleanupFinished = false
            var completionObservedBeforeCleanup = false
        }
        let state = SequencingState()

        let handled = await withCheckedContinuation { continuation in
            service.handleNotificationResponse(
                type: "individual",
                userInfo: [
                    "type": "individual",
                    "habitID": habitID.uuidString,
                    "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
                ],
                actionIdentifier: "habit.complete",
                notificationDate: Date(),
                onCleanupFinished: {
                    state.cleanupFinished = true
                },
                completion: { handled in
                    if !state.cleanupFinished {
                        state.completionObservedBeforeCleanup = true
                    }
                    continuation.resume(returning: handled)
                }
            )
        }

        #expect(handled)
        #expect(state.cleanupFinished)
        #expect(!state.completionObservedBeforeCleanup)
    }

    @Test
    func pillActionCompletionWaitsForDeliveredCleanup() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        let pillID = try repository.createPill(from: draft)
        try repository.clearPillDayStateToday(id: pillID)

        final class SequencingState {
            var cleanupFinished = false
            var completionObservedBeforeCleanup = false
        }
        let state = SequencingState()

        let handled = await withCheckedContinuation { continuation in
            service.handleNotificationResponse(
                type: "pill",
                userInfo: [
                    "type": "pill",
                    "pillID": pillID.uuidString,
                    "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
                ],
                actionIdentifier: "pill.take",
                notificationDate: Date(),
                onCleanupFinished: {
                    state.cleanupFinished = true
                },
                completion: { handled in
                    if !state.cleanupFinished {
                        state.completionObservedBeforeCleanup = true
                    }
                    continuation.resume(returning: handled)
                }
            )
        }

        #expect(handled)
        #expect(state.cleanupFinished)
        #expect(!state.completionObservedBeforeCleanup)
    }

    @Test
    func habitActionDoesNotCleanupWhenStoreMutationFails() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataHabitRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let today = Calendar.current.startOfDay(for: Date())
        var draft = CreateHabitDraft()
        draft.name = "Walk"
        draft.startDate = today
        draft.scheduleDays = .daily
        let habitID = try repository.createHabit(from: draft)
        try repository.completeHabitToday(id: habitID)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", today as CVarArg),
        ])
        let completion = try #require(persistence.container.viewContext.fetch(request).first)
        completion.setValue("invalid", forKey: "sourceRaw")
        try persistence.container.viewContext.save()

        final class CleanupState {
            var cleanupFinished = false
        }
        let state = CleanupState()

        let handled = await withCheckedContinuation { continuation in
            service.handleNotificationResponse(
                type: "individual",
                userInfo: [
                    "type": "individual",
                    "habitID": habitID.uuidString,
                    "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
                ],
                actionIdentifier: "habit.complete",
                notificationDate: Date(),
                onCleanupFinished: {
                    state.cleanupFinished = true
                },
                completion: { handled in
                    continuation.resume(returning: handled)
                }
            )
        }

        #expect(handled)
        #expect(!state.cleanupFinished)
    }

    @Test
    func pillActionDoesNotCleanupWhenStoreMutationFails() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataPillRepository(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let service = PillNotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        let today = Calendar.current.startOfDay(for: Date())
        var draft = PillDraft()
        draft.name = "Vitamin D"
        draft.dosage = "1 tablet"
        draft.startDate = today
        let pillID = try repository.createPill(from: draft)
        try repository.markTakenToday(id: pillID)

        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", today as CVarArg),
        ])
        let intake = try #require(persistence.container.viewContext.fetch(request).first)
        intake.setValue("invalid", forKey: "sourceRaw")
        try persistence.container.viewContext.save()

        final class CleanupState {
            var cleanupFinished = false
        }
        let state = CleanupState()

        let handled = await withCheckedContinuation { continuation in
            service.handleNotificationResponse(
                type: "pill",
                userInfo: [
                    "type": "pill",
                    "pillID": pillID.uuidString,
                    "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
                ],
                actionIdentifier: "pill.take",
                notificationDate: Date(),
                onCleanupFinished: {
                    state.cleanupFinished = true
                },
                completion: { handled in
                    continuation.resume(returning: handled)
                }
            )
        }

        #expect(handled)
        #expect(!state.cleanupFinished)
    }

    @Test
    func defaultTapRoutingCompletionDoesNotRequireCleanup() async throws {
        let persistence = PersistenceController(inMemory: true)
        let service = NotificationService(
            context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext
        )

        final class RoutingState {
            var cleanupFinished = false
        }
        let state = RoutingState()

        let handled = await withCheckedContinuation { continuation in
            service.handleNotificationResponse(
                type: "individual",
                userInfo: ["type": "individual"],
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                notificationDate: Date(),
                onCleanupFinished: {
                    state.cleanupFinished = true
                },
                completion: { handled in
                    continuation.resume(returning: handled)
                }
            )
        }

        #expect(handled)
        #expect(!state.cleanupFinished)
    }

    @Test
    func habitDeliveredCleanupUsesPayloadLocalDateWhenNotificationDateIsDifferent() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let logicalDay = LocalNotificationSupport.deliveredNotificationLogicalDay(
            userInfo: [
                "type": "individual",
                "localDate": LocalNotificationSupport.localDateIdentifier(for: yesterday, calendar: calendar),
            ],
            deliveryDate: today,
            calendar: calendar
        )

        #expect(logicalDay == yesterday)
    }

    @Test
    func pillDeliveredCleanupUsesPayloadLocalDateWhenNotificationDateIsDifferent() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let logicalDay = LocalNotificationSupport.deliveredNotificationLogicalDay(
            userInfo: [
                "type": "pill",
                "localDate": LocalNotificationSupport.localDateIdentifier(for: yesterday, calendar: calendar),
            ],
            deliveryDate: today,
            calendar: calendar
        )

        #expect(logicalDay == yesterday)
    }

    @Test
    func pillRemindLaterCleanupUsesPayloadLocalDateWhenNotificationDateIsDifferent() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let logicalDay = LocalNotificationSupport.deliveredNotificationLogicalDay(
            userInfo: [
                "type": "pill",
                "localDate": LocalNotificationSupport.localDateIdentifier(for: yesterday, calendar: calendar),
            ],
            deliveryDate: today,
            calendar: calendar
        )

        #expect(logicalDay == yesterday)
    }

    @Test
    func deliveredCleanupFallsBackToNotificationDateWhenPayloadLocalDateIsMissing() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let logicalDay = LocalNotificationSupport.deliveredNotificationLogicalDay(
            userInfo: ["type": "pill"],
            deliveryDate: today,
            calendar: calendar
        )

        #expect(logicalDay == today)
    }

    @Test
    func deliveredCleanupFallsBackToNotificationDateWhenPayloadLocalDateIsInvalid() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let logicalDay = LocalNotificationSupport.deliveredNotificationLogicalDay(
            userInfo: [
                "type": "individual",
                "localDate": "not-a-date",
            ],
            deliveryDate: today,
            calendar: calendar
        )

        #expect(logicalDay == today)
    }

    @Test
    func pillRemindLaterCompletionStillSchedulesNotification() async throws {
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

        let handled = await withCheckedContinuation { continuation in
            service.handleNotificationResponse(
                type: "pill",
                userInfo: [
                    "type": "pill",
                    "pillID": pillID.uuidString,
                    "localDate": LocalNotificationSupport.localDateIdentifier(for: today, calendar: .current),
                ],
                actionIdentifier: "pill.remind_later",
                notificationDate: Date(),
                fallbackTitle: "Vitamin D",
                fallbackBody: "Take 1 tablet.",
                completion: { handled in
                    continuation.resume(returning: handled)
                }
            )
        }

        #expect(handled)
        let requests = try await waitForPendingRequests(
            expectedCount: 1,
            matching: { $0.identifier.contains("remindlater_") }
        )
        #expect(requests.count == 1)

        try await clearNotifications()
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

        await rescheduleAllNotifications(service)
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

        await rescheduleAllNotifications(service)

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

        await rescheduleAllNotifications(service)
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

        await rescheduleAllNotifications(service)
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
        await rescheduleAllNotifications(service)
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
            scheduleDays: details.scheduleDays,
            reminderEnabled: true,
            reminderTime: reminderTimeHoursFromNow(4),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        )
        try repository.updatePill(from: updatedDraft)

        let updatedRegularCount = expectedRequestCount(reminderTime: updatedDraft.reminderTime, schedulingWindowDays: 2)
        await rescheduleAllNotifications(service)

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

        await rescheduleAllNotifications(service)
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

        await rescheduleAllNotifications(service)
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
        await rescheduleAllNotifications(service)
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

        await rescheduleAllNotifications(service)
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
        await rescheduleAllNotifications(service)
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

        await rescheduleAllNotifications(service)
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

    private func makeUTCClock() -> AppClock {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return AppClock(calendar: calendar, now: { Date(timeIntervalSince1970: 0) })
    }

    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func clearNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        for _ in 0..<20 {
            let pendingCount = await pendingRequests().count
            let deliveredCount = await deliveredNotifications().count
            if pendingCount == 0, deliveredCount == 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
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

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }

    private func rescheduleAllNotifications(_ service: NotificationService) async {
        await withCheckedContinuation { continuation in
            service.rescheduleAllNotifications {
                continuation.resume()
            }
        }
    }

    private func rescheduleAllNotifications(_ service: PillNotificationService) async {
        await withCheckedContinuation { continuation in
            service.rescheduleAllNotifications {
                continuation.resume()
            }
        }
    }

    private func triggerRescheduleSupport(
        center: UNUserNotificationCenter,
        storeContext: NotificationStoreContext,
        logName: String,
        removePendingNotifications: @escaping (@escaping () -> Void) -> Void,
        makePendingRequests: @escaping () throws -> [UNNotificationRequest]
    ) async {
        await withCheckedContinuation { continuation in
            NotificationRescheduleSupport.rescheduleAll(
                center: center,
                storeContext: storeContext,
                logName: logName,
                now: { Date(timeIntervalSince1970: 0) },
                removeDeliveredAggregatedNotifications: { _ in },
                removePendingNotifications: removePendingNotifications,
                makePendingRequests: makePendingRequests
            ) {
                continuation.resume()
            }
        }
    }

    nonisolated private func makeNotificationRequest(identifier: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Reminder"

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )
    }
}

private final class RescheduleInvocationTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var makeCallCount = 0
    private var removeCallCount = 0

    func nextRemoveCall() -> Int {
        lock.lock()
        defer { lock.unlock() }

        removeCallCount += 1
        return removeCallCount
    }

    func nextRequestSuffix() -> String {
        lock.lock()
        defer { lock.unlock() }

        makeCallCount += 1
        return makeCallCount == 1 ? "old" : "new"
    }

    var counts: (make: Int, remove: Int) {
        lock.lock()
        defer { lock.unlock() }

        return (makeCallCount, removeCallCount)
    }
}
