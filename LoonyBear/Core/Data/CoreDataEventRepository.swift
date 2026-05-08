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

    func fetchEventDetails(id: UUID) throws -> EventDetailsProjection? {
        guard let object = try fetchEvent(id: id, in: readContext) else { return nil }

        var report = IntegrityReportBuilder()
        guard let details = makeDetailsProjection(from: object, report: &report) else {
            let error = report.makeError(operation: "fetchEventDetails")
            ReliabilityLog.error("event.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        return details
    }

    func createEvent(from draft: EventDraft) throws -> UUID {
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

    func updateEvent(from draft: EditEventDraft) throws {
        try repositoryContext.performWrite { context in
            guard let object = try fetchEvent(id: draft.id, in: context) else {
                throw EventRepositoryError.internalFailure
            }

            object.setValue(draft.trimmedName, forKey: "name")
            object.setValue(draft.mode.rawValue, forKey: "modeRaw")
            object.setValue(calendar.startOfDay(for: draft.date), forKey: "eventDate")
            object.setValue(clock.now(), forKey: "updatedAt")
            object.setValue(object.int32Value(forKey: "version", default: 1) + 1, forKey: "version")

            try context.save()
        }
    }

    func deleteEvent(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let object = try fetchEvent(id: id, in: context) else {
                throw EventRepositoryError.internalFailure
            }

            context.delete(object)
            try context.save()
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
            let date = object.dateValue(forKey: "eventDate"),
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
            date: calendar.startOfDay(for: date),
            sortOrder: Int(object.int32Value(forKey: "sortOrder"))
        )
    }

    private func makeDetailsProjection(
        from object: NSManagedObject,
        report: inout IntegrityReportBuilder
    ) -> EventDetailsProjection? {
        guard
            let id = object.uuidValue(forKey: "id"),
            let name = object.stringValue(forKey: "name"),
            let date = object.dateValue(forKey: "eventDate"),
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
            date: calendar.startOfDay(for: date)
        )
    }
}
