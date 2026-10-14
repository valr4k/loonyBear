import SwiftUI
import CoreData
import XCTest

@testable import LoonyBear

@MainActor
final class EventCardAppearanceTests: XCTestCase {
    func testMidnightTimelineRefreshesAllDashboardsBeforeCombinedBadge() async throws {
        let persistence = PersistenceController(inMemory: true)
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        var now = midnight.addingTimeInterval(-1)
        let clock = AppClock(calendar: calendar, now: { now })
        let context = persistence.container.viewContext
        let makeContext = persistence.makeBackgroundContext
        let anchors = TestOverdueAnchorStore()
        let habits = CoreDataHabitRepository(context: context, makeWriteContext: makeContext,
            clock: clock, overdueAnchorStore: anchors)
        let pills = CoreDataPillRepository(context: context, makeWriteContext: makeContext,
            clock: clock, overdueAnchorStore: anchors)
        let events = CoreDataEventRepository(context: context, makeWriteContext: makeContext, clock: clock)
        var habit = CreateHabitDraft()
        habit.name = "Daily habit"
        habit.startDate = calendar.startOfDay(for: now)
        habit.scheduleDays = .daily
        habit.reminderEnabled = false
        let habitID = try habits.createHabit(from: habit)
        _ = try habits.completeHabitToday(id: habitID)
        var pill = PillDraft()
        pill.name = "Daily pill"
        pill.dosage = "1"
        pill.startDate = habit.startDate
        pill.scheduleDays = .daily
        pill.reminderEnabled = false
        let pillID = try pills.createPill(from: pill)
        _ = try pills.markTakenToday(id: pillID)
        _ = try events.createEvent(from: EventDraft(name: "Today", date: midnight))

        let applier = TimelineBadgeApplier()
        let load = LoadDashboardUseCase(repository: habits)
        let badge = AppBadgeService(loadDashboardUseCase: load, pillRepository: pills,
            eventRepository: events, clock: clock, badgeApplier: applier)
        let habitNotifications = NotificationService(context: context, makeWriteContext: makeContext, clock: clock)
        let pillNotifications = PillNotificationService(context: context, makeWriteContext: makeContext, clock: clock)
        let habitState = HabitAppState(loadDashboardUseCase: load,
            createHabitUseCase: CreateHabitUseCase(repository: habits),
            updateHabitUseCase: UpdateHabitUseCase(repository: habits),
            reconcileHistoryUseCase: ReconcileHabitHistoryUseCase(repository: habits, clock: clock),
            repository: habits, notificationService: habitNotifications,
            widgetSyncService: WidgetSyncService(clock: clock), badgeService: badge, clock: clock)
        let pillState = PillAppState(reconcileHistoryUseCase: ReconcilePillHistoryUseCase(repository: pills, clock: clock),
            repository: pills, notificationService: pillNotifications, badgeService: badge, clock: clock)
        let eventState = EventAppState(repository: events)
        await habitState.load()
        pillState.load()
        eventState.load()
        badge.refreshBadge(habitDashboard: habitState.dashboard, pillDashboard: pillState.dashboard, now: now)
        XCTAssertEqual(applier.lastCount, 0)
        XCTAssertTrue(try XCTUnwrap(habitState.dashboard.sections.flatMap(\.habits).first).isCompletedToday)
        XCTAssertTrue(try XCTUnwrap(pillState.dashboard.pills.first).isTakenToday)

        now = midnight
        AppTimelineRefresh.refresh(habits: habitState, pills: pillState, events: eventState,
            badgeService: badge, now: now)
        XCTAssertFalse(try XCTUnwrap(habitState.dashboard.sections.flatMap(\.habits).first).isCompletedToday)
        XCTAssertFalse(try XCTUnwrap(pillState.dashboard.pills.first).isTakenToday)
        XCTAssertEqual(EventBadgeSupport.count(eventState.dashboard.events, now: now), 1)
        XCTAssertEqual(applier.lastCount, try badge.overdueCount(now: now))
        XCTAssertEqual(applier.lastCount, 3)
    }

    func testDueCountdownTurnsGrayOnlyAfterAcknowledgment() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for dayOffset in [0, -1, -30] {
            let date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: dayOffset, to: now))
            var event = EventCardProjection(id: UUID(), name: "Launch", mode: .countdown,
                date: date, sortOrder: 0)
            XCTAssertEqual(EventCardView(event: event, position: .single, currentTime: now).durationColor, .red)
            XCTAssertEqual(EventBadgeSupport.count([event], now: now), 1)
            event.acknowledgedAt = now
            XCTAssertEqual(EventCardView(event: event, position: .single, currentTime: now).durationColor, .secondary)
            XCTAssertEqual(EventBadgeSupport.count([event], now: now), 0)
            XCTAssertEqual(EventDurationFormatter.text(for: event, now: now), "0d")
            event.acknowledgedAt = nil
            XCTAssertEqual(EventCardView(event: event, position: .single, currentTime: now).durationColor, .red)
        }
    }

    func testAcknowledgmentOnlyChangesCompletedCountdownAppearance() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for scheme in [ColorScheme.light, .dark] {
            for (mode, dayOffset) in [(EventMode.countdown, 0), (.countdown, 30), (.countUp, -30)] {
                var event = EventCardProjection(id: UUID(), name: "Launch", mode: mode,
                    date: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: dayOffset, to: now)), sortOrder: 0)
                func render(_ event: EventCardProjection) throws -> UIImage {
                    let renderer = ImageRenderer(content:
                        EventCardView(event: event, position: .single, currentTime: now)
                            .frame(width: 320)
                            .environment(\.colorScheme, scheme))
                    renderer.scale = 2
                    return try XCTUnwrap(renderer.uiImage)
                }
                let before = try render(event)
                event.acknowledgedAt = now
                let after = try render(event)
                XCTAssertEqual(before.size, after.size)
                if mode == .countdown && dayOffset == 0 {
                    XCTAssertNotEqual(before.pngData(), after.pngData())
                    let attachment = XCTAttachment(image: after)
                    attachment.name = "acknowledged-countdown-\(scheme)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                } else {
                    XCTAssertEqual(before.pngData(), after.pngData())
                }
            }
        }
    }

    func testNativeListMovementPersistsWithoutEditingHandles() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataEventRepository(context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext)
        let ids = try ["First", "Second", "Third"].map {
            try repository.createEvent(from: EventDraft(name: $0))
        }
        let countUpID = try repository.createEvent(from: EventDraft(name: "Other section", mode: .countUp, date: Date()))
        let state = EventAppState(repository: repository)
        state.load()
        var openedEvents: [UUID] = []
        let host = UIHostingController(rootView: MyEventsView(onEditEvent: { openedEvents.append($0.id) }).environmentObject(state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let collection = try XCTUnwrap(descendant(of: UICollectionView.self, in: host.view))
        XCTAssertFalse(collection.isEditing, "Sorting must not add native editing handles")
        // Each section starts with the app's non-movable header row.
        let source = IndexPath(item: 1, section: 0)
        let destination = IndexPath(item: 3, section: 0)
        let targetFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: destination)?.frame)
        XCTAssertTrue(collection.beginInteractiveMovementForItem(at: source))
        collection.updateInteractiveMovementTargetPosition(CGPoint(x: targetFrame.midX, y: targetFrame.midY))
        collection.cancelInteractiveMovement()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(state.dashboard.events.filter { $0.mode == .countdown }.map(\.id), ids)
        XCTAssertTrue(collection.beginInteractiveMovementForItem(at: source))
        collection.updateInteractiveMovementTargetPosition(CGPoint(x: targetFrame.midX, y: targetFrame.midY))
        collection.endInteractiveMovement()
        for _ in 0..<50 {
            if state.dashboard.events.filter({ $0.mode == .countdown }).map(\.id) == [ids[1], ids[2], ids[0]] { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertEqual(state.dashboard.events.filter { $0.mode == .countdown }.map(\.id), [ids[1], ids[2], ids[0]])
        XCTAssertEqual(try repository.fetchDashboardEvents().filter { $0.mode == .countdown }.map(\.id), [ids[1], ids[2], ids[0]])
        XCTAssertEqual(state.dashboard.events.filter { $0.mode == .countUp }.map(\.id), [countUpID])
        let proposedCrossSectionTarget = IndexPath(item: 1, section: 1)
        let allowedTarget = collection.delegate?.collectionView?(collection,
            targetIndexPathForMoveOfItemFromOriginalIndexPath: source,
            atCurrentIndexPath: source, toProposedIndexPath: proposedCrossSectionTarget)
        XCTAssertEqual(allowedTarget?.section, 0, "Native movement must stay inside its original section")
        XCTAssertTrue(openedEvents.isEmpty, "Moving or canceling movement must not open Event Details")
        XCTAssertTrue(try repository.fetchDashboardEvents().allSatisfy { $0.acknowledgedAt == nil })
    }

    func testCountUpMovementIsAvailableWithoutEnteringEditMode() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = CoreDataEventRepository(context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext)
        _ = try repository.createEvent(from: EventDraft(name: "First", mode: .countUp))
        _ = try repository.createEvent(from: EventDraft(name: "Second", mode: .countUp))
        let state = EventAppState(repository: repository)
        state.load()
        let host = UIHostingController(rootView: MyEventsView().environmentObject(state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let collection = try XCTUnwrap(descendant(of: UICollectionView.self, in: host.view))
        XCTAssertFalse(collection.isEditing)
        XCTAssertTrue(collection.beginInteractiveMovementForItem(at: IndexPath(item: 1, section: 0)))
        collection.cancelInteractiveMovement()
    }

    private func descendant<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.descendant(of: type, in: $0) }.first
    }

    func testSortingDoesNotChangeCardPixelsOrDimensions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = EventCardProjection(id: UUID(), name: "A long event name on two lines", mode: .countdown,
            date: now.addingTimeInterval(86400 * 30), sortOrder: 0)
        for scheme in [ColorScheme.light, .dark] {
            for width in [320.0, 402.0] {
                func render(sorting: Bool) throws -> UIImage {
                    let view = EventCardView(event: event, position: .single, currentTime: now)
                        .modifier(EventReorderModifier(enabled: sorting, event: event, events: [event],
                            move: { _ in }))
                        .frame(width: width)
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    return try XCTUnwrap(renderer.uiImage)
                }
                let normal = try render(sorting: false)
                let editing = try render(sorting: true)
                XCTAssertEqual(normal.size, editing.size)
                XCTAssertGreaterThan(normal.size.height, 72)
                XCTAssertEqual(normal.pngData(), editing.pngData())
                let attachment = XCTAttachment(image: editing)
                attachment.name = "event-sorting-\(scheme)-\(width)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

private final class TimelineBadgeApplier: AppBadgeApplying {
    private(set) var lastCount: Int?

    func setBadgeCount(_ badgeCount: Int) {
        lastCount = badgeCount
    }
}
