import CoreData
import Foundation
import Testing
import UserNotifications

@testable import LoonyBear

@MainActor
struct EventBadgeTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return value
    }

    private func repository(_ persistence: PersistenceController, now: Date, calendar: Calendar? = nil) -> CoreDataEventRepository {
        let resolvedCalendar = calendar ?? self.calendar
        return CoreDataEventRepository(context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext,
            clock: AppClock(calendar: resolvedCalendar, now: { now }))
    }

    @Test
    func badgeStartsAtMidnightAndAcknowledgmentIsIdempotent() throws {
        let midnight = TestSupport.makeDate(2026, 10, 12, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let before = repository(persistence, now: midnight.addingTimeInterval(-1))
        let id = try before.createEvent(from: EventDraft(name: "Launch", date: midnight))
        let cards = try before.fetchDashboardEvents()
        #expect(EventBadgeSupport.count(cards, now: midnight.addingTimeInterval(-1), calendar: calendar) == 0)
        #expect(try !before.acknowledgeEvent(id: id))
        #expect(EventBadgeSupport.count(cards, now: midnight, calendar: calendar) == 1)
        let due = repository(persistence, now: midnight)
        #expect(try due.acknowledgeEvent(id: id))
        #expect(try !due.acknowledgeEvent(id: id))
        let acknowledged = try due.fetchDashboardEvents()
        #expect(EventBadgeSupport.count(acknowledged, now: midnight, calendar: calendar) == 0)
        #expect(EventDurationFormatter.text(for: acknowledged[0], now: midnight, calendar: calendar) == "0d")
        #expect(EventDurationFormatter.isCountdownComplete(acknowledged[0], now: midnight, calendar: calendar))
    }

    @Test
    func onlySavedDateOrModeChangeResetsAcknowledgment() throws {
        let now = TestSupport.makeDate(2026, 10, 12, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repo = repository(persistence, now: now)
        let id = try repo.createEvent(from: EventDraft(name: "Launch", date: now))
        #expect(try repo.acknowledgeEvent(id: id))
        var draft = EditEventDraft(details: try #require(try repo.fetchEventDetails(id: id)))
        draft.name = "Renamed"
        try repo.updateEvent(from: draft)
        #expect(try repo.fetchDashboardEvents()[0].acknowledgedAt != nil)
        draft.date = calendar.date(byAdding: .day, value: 1, to: now)!
        #expect(try repo.fetchDashboardEvents()[0].acknowledgedAt != nil)
        try repo.updateEvent(from: draft)
        #expect(try repo.fetchDashboardEvents()[0].acknowledgedAt == nil)
        draft.date = now
        try repo.updateEvent(from: draft)
        #expect(EventBadgeSupport.count(try repo.fetchDashboardEvents(), now: now, calendar: calendar) == 1)
        draft.mode = .countUp
        try repo.updateEvent(from: draft)
        #expect(EventBadgeSupport.count(try repo.fetchDashboardEvents(), now: now, calendar: calendar) == 0)
        #expect(try !repo.acknowledgeEvent(id: id))
        try repo.deleteEvent(id: id)
        #expect(try repo.fetchDashboardEvents().isEmpty)
    }

    @Test(arguments: ["America/Los_Angeles", "Pacific/Auckland", "Asia/Tokyo"])
    func dateAndAcknowledgmentSurviveTimeZoneChanges(zone: String) throws {
        let originalDay = TestSupport.makeDate(2026, 10, 12, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let original = repository(persistence, now: originalDay)
        let id = try original.createEvent(from: EventDraft(name: "Trip", date: originalDay))
        #expect(try original.acknowledgeEvent(id: id))
        var openDraft = EditEventDraft(details: try #require(try original.fetchEventDetails(id: id)))
        openDraft.name = "Renamed while traveling"
        var destination = calendar
        destination.timeZone = try #require(TimeZone(identifier: zone))
        let localDay = TestSupport.makeDate(2026, 10, 12, calendar: destination)
        let relocated = repository(persistence, now: localDay, calendar: destination)
        try relocated.updateEvent(from: openDraft)
        let card = try #require(relocated.fetchDashboardEvents().first)
        #expect(card.date == localDay)
        #expect(card.acknowledgedAt != nil)
        #expect(EventBadgeSupport.count([card], now: localDay, calendar: destination) == 0)
    }

    @Test
    func legacyDatesReusePillHabitNormalizationAndArePersistedOnce() throws {
        let storedDate = TestSupport.makeDate(2026, 10, 12, calendar: calendar)
        var destination = calendar
        destination.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let persistence = PersistenceController(inMemory: true)
        let repo = repository(persistence, now: storedDate)
        _ = try repo.createEvent(from: EventDraft(name: "Legacy", date: storedDate))
        let context = persistence.container.viewContext
        let object = try #require(try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Event")).first)
        object.setValue(nil, forKey: "dateKey")
        try context.save()
        let relocated = repository(persistence, now: storedDate, calendar: destination)
        try relocated.prepareLocalDates()
        let card = try #require(relocated.fetchDashboardEvents().first)
        #expect(EventLocalDate.key(for: card.date, calendar: destination) == "2026-10-12")
        try relocated.prepareLocalDates()
        #expect(try relocated.fetchDashboardEvents().first == card)
    }

    @Test
    func reorderIsSectionScopedAndRejectsPartialDuplicateAndForeignIDs() throws {
        let now = TestSupport.makeDate(2026, 10, 12, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repo = repository(persistence, now: now)
        let a = try repo.createEvent(from: EventDraft(name: "A", date: now))
        let b = try repo.createEvent(from: EventDraft(name: "B", date: now))
        let c = try repo.createEvent(from: EventDraft(name: "C", mode: .countUp, date: now))
        try repo.reorderEvents(ids: [b, a], mode: .countdown)
        #expect(try repo.fetchDashboardEvents().filter { $0.mode == .countdown }.map(\.id) == [b, a])
        #expect(throws: EventRepositoryError.self) { try repo.reorderEvents(ids: [a, c], mode: .countdown) }
        #expect(throws: EventRepositoryError.self) { try repo.reorderEvents(ids: [a, a], mode: .countdown) }
        #expect(throws: EventRepositoryError.self) { try repo.reorderEvents(ids: [a], mode: .countdown) }
        #expect(try repo.fetchDashboardEvents().filter { $0.mode == .countUp }.map(\.id) == [c])
        let d = try repo.createEvent(from: EventDraft(name: "D", date: now))
        #expect(try repo.fetchDashboardEvents().filter { $0.mode == .countdown }.map(\.id) == [b, a, d])
        var draft = EditEventDraft(details: try #require(try repo.fetchEventDetails(id: b)))
        draft.mode = .countUp
        try repo.updateEvent(from: draft)
        #expect(try repo.fetchDashboardEvents().filter { $0.mode == .countUp }.map(\.id) == [c, b])
    }

    @Test
    func notificationIsBadgeOnlyGroupedAndUsesFloatingLocalMidnight() throws {
        let now = TestSupport.makeDate(2026, 10, 24, calendar: calendar)
        let due = TestSupport.makeDate(2026, 10, 25, calendar: calendar)
        let next = TestSupport.makeDate(2026, 10, 26, calendar: calendar)
        let events = [
            EventCardProjection(id: UUID(), name: "A", mode: .countdown, date: due, sortOrder: 0),
            EventCardProjection(id: UUID(), name: "B", mode: .countdown, date: due, sortOrder: 1),
            EventCardProjection(id: UUID(), name: "C", mode: .countdown, date: next, sortOrder: 2),
            EventCardProjection(id: UUID(), name: "Seen", mode: .countdown, date: now, sortOrder: 3, acknowledgedAt: now),
            EventCardProjection(id: UUID(), name: "Up", mode: .countUp, date: now, sortOrder: 4),
        ]
        let requests = EventBadgeNotificationSupport.requests(events: events, habits: [], pills: [], now: now, calendar: calendar, limit: 56)
        #expect(requests.count == 2)
        #expect(requests.map { $0.content.badge?.intValue } == [2, 3])
        for request in requests {
            #expect(request.content.title.isEmpty && request.content.body.isEmpty)
            #expect(request.content.sound == nil)
            #expect(request.content.categoryIdentifier.isEmpty)
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.dateComponents.hour == 0 && trigger.dateComponents.minute == 0)
            #expect(trigger.dateComponents.timeZone == nil)
            #expect(!trigger.repeats)
        }
        #expect(EventBadgeNotificationSupport.requests(events: events, habits: [], pills: [], now: next, calendar: calendar, limit: 56).isEmpty)
        #expect(EventBadgeNotificationSupport.requests(events: events, habits: [], pills: [], now: now, calendar: calendar, limit: 1).count == 1)
    }

    @Test
    func backupRoundTripPreservesOrderDateAndAcknowledgment() throws {
        let now = TestSupport.makeDate(2026, 10, 12, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let repo = repository(persistence, now: now)
        let a = try repo.createEvent(from: EventDraft(name: "A", date: now))
        let b = try repo.createEvent(from: EventDraft(name: "B", date: now))
        try repo.reorderEvents(ids: [b, a], mode: .countdown)
        #expect(try repo.acknowledgeEvent(id: a))
        let original = try repo.fetchDashboardEvents()
        let suite = "EventBadgeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = BackupService(context: persistence.container.viewContext,
            makeWorkContext: persistence.makeBackgroundContext, defaults: defaults, compressionService: CompressionService())
        try service.saveFolderBookmark(for: folder)
        try service.createBackup()
        try repo.deleteEvent(id: a)
        try repo.deleteEvent(id: b)
        try service.restoreBackup()
        #expect(try repo.fetchDashboardEvents() == original)
    }

    @Test
    func legacyBackupEventDecodesWithoutNewFields() throws {
        let date = Date(timeIntervalSince1970: 0)
        let old = BackupEvent(id: UUID(), name: "Legacy", mode: "countdown", date: date, sortOrder: 0, createdAt: date, updatedAt: date, version: 1)
        let data = try JSONEncoder().encode(old)
        let restored = try JSONDecoder().decode(BackupEvent.self, from: data)
        #expect(restored.dateKey == nil && restored.acknowledgedAt == nil)
    }

    @Test
    func legacyStoreMigratesWithoutDroppingEvents() throws {
        let bundleURL = try #require(Bundle.main.url(forResource: "LoonyBear", withExtension: "momd"))
        let oldModel = try #require(NSManagedObjectModel(contentsOf: bundleURL.appendingPathComponent("LoonyBear.mom")))
        let newModel = try #require(NSManagedObjectModel(contentsOf: bundleURL.appendingPathComponent("LoonyBearEventBadges.mom")))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("migration.sqlite")
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        let oldStore = try oldCoordinator.addPersistentStore(type: .sqlite, at: url)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = oldCoordinator
        let object = NSEntityDescription.insertNewObject(forEntityName: "Event", into: context)
        let id = UUID()
        object.setValue(id, forKey: "id")
        object.setValue("Legacy", forKey: "name")
        object.setValue("countdown", forKey: "modeRaw")
        for key in ["eventDate", "createdAt", "updatedAt"] { object.setValue(Date(), forKey: key) }
        try context.save()
        context.reset()
        try oldCoordinator.remove(oldStore)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: newModel)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url, options: [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
        ])
        let migrated = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        migrated.persistentStoreCoordinator = coordinator
        let events = try migrated.fetch(NSFetchRequest<NSManagedObject>(entityName: "Event"))
        #expect(events.count == 1)
        #expect(events[0].value(forKey: "id") as? UUID == id)
        #expect(events[0].value(forKey: "acknowledgedAt") == nil)
        #expect(events[0].value(forKey: "dateKey") == nil)
        migrated.reset()
        try coordinator.remove(store)
    }

    @Test
    func reminderPayloadsIncludeEventsAndUpdateAfterAcknowledgment() throws {
        let now = TestSupport.makeDate(2026, 10, 12, calendar: calendar)
        let persistence = PersistenceController(inMemory: true)
        let clock = AppClock(calendar: calendar, now: { now })
        let events = repository(persistence, now: now)
        let eventID = try events.createEvent(from: EventDraft(name: "Today", date: now))
        let pills = CoreDataPillRepository(context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext, clock: clock)
        var draft = PillDraft()
        draft.name = "Pill"
        draft.dosage = "One"
        draft.startDate = now
        draft.reminderEnabled = true
        draft.reminderTime = ReminderTime(hour: 10, minute: 0)
        _ = try pills.createPill(from: draft)
        let service = PillNotificationService(context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext, clock: clock)
        let before = try service.makePendingNotificationRequests()
        #expect(!before.isEmpty)
        #expect(before.allSatisfy { $0.content.badge?.intValue == 2 })
        #expect(try events.acknowledgeEvent(id: eventID))
        let freshService = PillNotificationService(context: persistence.container.viewContext,
            makeWriteContext: persistence.makeBackgroundContext, clock: clock)
        #expect(try freshService.makePendingNotificationRequests().allSatisfy { $0.content.badge?.intValue == 1 })
    }
}
