import CoreData
import Foundation

@MainActor
struct CoreDataEventRepository: EventRepository {
    private let readContext: NSManagedObjectContext
    private let repositoryContext: CoreDataRepositoryContext
    private let calendar: Calendar
    private let clock: AppClock

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        clock: AppClock? = nil
    ) {
        let resolvedClock = clock ?? AppClock(calendar: calendar)
        readContext = context
        self.calendar = resolvedClock.calendar
        self.clock = resolvedClock
        repositoryContext = CoreDataRepositoryContext(
            readContext: context,
            makeWriteContext: makeWriteContext
        )
    }

    func fetchDashboardEvents() throws -> [EventCardProjection] {
        try PerformanceLog.measure("event.dashboard.fetch") {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Event")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        var report = IntegrityReportBuilder()
        let objects = try readContext.fetch(request)
        let events = objects.compactMap { makeCardProjection(from: $0, report: &report) }

        if report.hasIssues {
            throw report.makeError(operation: "fetchDashboardEvents")
        }

        return events
        }
    }

    func fetchEventDetails(id: UUID) throws -> EventDetailsProjection? {
        try PerformanceLog.measure("event.details.fetch", metadata: "id=\(id.uuidString)") {
        guard let object = try fetchEvent(id: id, in: readContext) else { return nil }

        var report = IntegrityReportBuilder()
        guard let details = makeDetailsProjection(from: object, report: &report) else {
            let error = report.makeError(operation: "fetchEventDetails")
            ReliabilityLog.error("event.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        return details
        }
    }

    func createEvent(from draft: EventDraft) throws -> UUID {
        try PerformanceLog.measure("event.create.save") {
        try repositoryContext.performWrite({ context in
            let countRequest = NSFetchRequest<NSDictionary>(entityName: "Event")
            countRequest.resultType = .dictionaryResultType
            countRequest.propertiesToFetch = ["sortOrder"]
            countRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
            countRequest.fetchLimit = 1

            let maxSortOrder = try context.fetch(countRequest).first?["sortOrder"] as? Int32 ?? -1
            let now = clock.now()
            let eventID = UUID()

            let object = NSEntityDescription.insertNewObject(forEntityName: "Event", into: context)
            object.setValue(eventID, forKey: "id")
            object.setValue(EventLocalDate.key(for: draft.date, calendar: calendar), forKey: "dateKey")
            object.setValue(draft.trimmedName, forKey: "name")
            object.setValue(draft.mode.rawValue, forKey: "modeRaw")
            object.setValue(calendar.startOfDay(for: draft.date), forKey: "eventDate")
            object.setValue(maxSortOrder + 1, forKey: "sortOrder")
            object.setValue(now, forKey: "createdAt")
            object.setValue(now, forKey: "updatedAt")
            object.setValue(Int32(1), forKey: "version")

            try context.save()
            return eventID
        }, missingResultError: EventRepositoryError.internalFailure)
        }
    }

    func updateEvent(from draft: EditEventDraft) throws {
        try PerformanceLog.measure("event.update.save", metadata: "id=\(draft.id.uuidString)") {
        try repositoryContext.performWrite { context in
            guard let object = try fetchEvent(id: draft.id, in: context) else {
                throw EventRepositoryError.internalFailure
            }

            let nextKey = draft.resolvedDateKey(calendar: calendar)
            let oldKey = object.stringValue(forKey: "dateKey")
                ?? object.dateValue(forKey: "eventDate").map { EventLocalDate.legacyKey(for: $0, calendar: calendar) }
            if oldKey != nextKey || object.stringValue(forKey: "modeRaw") != draft.mode.rawValue {
                object.setValue(nil, forKey: "acknowledgedAt")
            }
            if object.stringValue(forKey: "modeRaw") != draft.mode.rawValue {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Event")
                request.predicate = NSPredicate(format: "modeRaw == %@", draft.mode.rawValue)
                let lastOrder = try context.fetch(request).map { $0.int32Value(forKey: "sortOrder") }.max() ?? -1
                object.setValue(lastOrder + 1, forKey: "sortOrder")
            }
            object.setValue(nextKey, forKey: "dateKey")
            object.setValue(draft.trimmedName, forKey: "name")
            object.setValue(draft.mode.rawValue, forKey: "modeRaw")
            object.setValue(EventLocalDate.date(for: nextKey, calendar: calendar), forKey: "eventDate")
            object.setValue(clock.now(), forKey: "updatedAt")
            object.setValue(object.int32Value(forKey: "version", default: 1) + 1, forKey: "version")

            try context.save()
        }
        }
    }

    func deleteEvent(id: UUID) throws {
        try PerformanceLog.measure("event.delete.save", metadata: "id=\(id.uuidString)") {
        try repositoryContext.performWrite { context in
            guard let object = try fetchEvent(id: id, in: context) else {
                throw EventRepositoryError.internalFailure
            }

            context.delete(object)
            try context.save()
        }
        }
    }

    private func fetchEvent(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Event")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func makeCardProjection(
        from object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> EventCardProjection? {
        guard
            let id = object.uuidValue(forKey: "id"),
            let name = object.stringValue(forKey: "name"),
            let storedDate = object.dateValue(forKey: "eventDate"),
            let date = localDate(object, fallback: storedDate),
            let modeRaw = object.stringValue(forKey: "modeRaw"),
            let mode = EventMode(rawValue: modeRaw)
        else {
            report.append(
                area: "event.dashboard",
                entityName: object.entityName,
                object: object,
                message: "Event row is missing required fields or has invalid mode."
            )
            return nil
        }

        return EventCardProjection(
            id: id,
            name: name,
            mode: mode,
            date: date,
            sortOrder: Int(object.int32Value(forKey: "sortOrder")),
            acknowledgedAt: object.dateValue(forKey: "acknowledgedAt")
        )
    }

    private func makeDetailsProjection(
        from object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> EventDetailsProjection? {
        guard
            let id = object.uuidValue(forKey: "id"),
            let name = object.stringValue(forKey: "name"),
            let storedDate = object.dateValue(forKey: "eventDate"),
            let date = localDate(object, fallback: storedDate),
            let modeRaw = object.stringValue(forKey: "modeRaw"),
            let mode = EventMode(rawValue: modeRaw)
        else {
            report.append(
                area: "event.details",
                entityName: object.entityName,
                object: object,
                message: "Event details row is missing required fields or has invalid mode."
            )
            return nil
        }

        return EventDetailsProjection(
            id: id,
            name: name,
            mode: mode,
            date: date,
            dateKey: object.stringValue(forKey: "dateKey")
        )
    }

    private func localDate(_ object: NSManagedObject, fallback: Date) -> Date? {
        if let key = object.stringValue(forKey: "dateKey") {
            return EventLocalDate.date(for: key, calendar: calendar)
        }
        return CoreDataDateOnlyStorage.normalizedDay(fromStoredDate: fallback, calendar: calendar)
    }

    func prepareLocalDates() throws {
        try repositoryContext.performWrite { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Event")
            request.predicate = NSPredicate(format: "dateKey == nil")
            for object in try context.fetch(request) {
                guard let date = object.dateValue(forKey: "eventDate") else { throw EventRepositoryError.internalFailure }
                object.setValue(EventLocalDate.legacyKey(for: date, calendar: calendar), forKey: "dateKey")
            }
            if context.hasChanges { try context.save() }
        }
    }

    func acknowledgeEvent(id: UUID) throws -> Bool {
        try repositoryContext.performWrite({ context in
            guard let object = try fetchEvent(id: id, in: context),
                  object.stringValue(forKey: "modeRaw") == EventMode.countdown.rawValue,
                  object.dateValue(forKey: "acknowledgedAt") == nil,
                  let date = object.dateValue(forKey: "eventDate"),
                  let localDay = localDate(object, fallback: date),
                  localDay <= calendar.startOfDay(for: clock.now()) else { return false }
            object.setValue(clock.now(), forKey: "acknowledgedAt")
            object.setValue(clock.now(), forKey: "updatedAt")
            object.setValue(object.int32Value(forKey: "version", default: 1) + 1, forKey: "version")
            try context.save()
            return true
        }, missingResultError: EventRepositoryError.internalFailure)
    }

    func reorderEvents(ids: [UUID], mode: EventMode) throws {
        try repositoryContext.performWrite { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Event")
            request.predicate = NSPredicate(format: "modeRaw == %@", mode.rawValue)
            let objects = try context.fetch(request)
            guard ids.count == Set(ids).count, Set(ids) == Set(objects.compactMap { $0.uuidValue(forKey: "id") }) else {
                throw EventRepositoryError.internalFailure
            }
            let positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            for object in objects {
                guard let id = object.uuidValue(forKey: "id"), let position = positions[id] else { continue }
                guard object.int32Value(forKey: "sortOrder") != Int32(position) else { continue }
                object.setValue(Int32(position), forKey: "sortOrder")
                object.setValue(clock.now(), forKey: "updatedAt")
                object.setValue(object.int32Value(forKey: "version", default: 1) + 1, forKey: "version")
            }
            if context.hasChanges { try context.save() }
        }
    }
}
