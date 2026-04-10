import CoreData
import Foundation

struct CoreDataPillRepository: PillRepository {
    private let readContext: NSManagedObjectContext
    private let repositoryContext: CoreDataRepositoryContext

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext
    ) {
        readContext = context
        repositoryContext = CoreDataRepositoryContext(
            readContext: context,
            makeWriteContext: makeWriteContext
        )
    }

    func fetchDashboardPills() throws -> [PillCardProjection] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        let pills = try readContext.fetch(request)
        let today = Calendar.current.startOfDay(for: Date())
        var report = IntegrityReportBuilder()
        var projections: [PillCardProjection] = []

        for pillObject in pills {
            if let projection = makeDashboardProjection(
                from: pillObject,
                today: today,
                report: &report
            ) {
                projections.append(projection)
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: "fetchDashboardPills")
        }

        return projections.sorted(by: pillDashboardSort)
    }

    func fetchPillDetails(id: UUID) throws -> PillDetailsProjection? {
        guard let pillObject = try fetchPill(id: id, in: readContext) else { return nil }

        var report = IntegrityReportBuilder()
        guard
            let name = pillObject.stringValue(forKey: "name"),
            let dosage = pillObject.stringValue(forKey: "dosage"),
            let startDate = pillObject.dateValue(forKey: "startDate")
        else {
            report.append(
                area: "details",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill details row is missing required fields."
            )
            let error = report.makeError(operation: "fetchPillDetails")
            ReliabilityLog.error("pill.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        guard
            let schedules = loadSchedules(for: pillObject, pillID: id, report: &report),
            let intakes = loadIntakes(for: pillObject, pillID: id, report: &report)
        else {
            report.append(
                area: "details",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill details failed because related rows are corrupted."
            )
            let error = report.makeError(operation: "fetchPillDetails")
            ReliabilityLog.error("pill.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        let latestSchedule = schedules.sorted(by: isNewerSchedule).first
        let successfulIntakes = intakes.filter { $0.source.countsAsIntake }
        let skippedDays = Set(
            intakes
                .filter { !$0.source.countsAsIntake }
                .map { Calendar.current.startOfDay(for: $0.localDate) }
        )
        let reminderEnabled = pillObject.boolValue(forKey: "reminderEnabled")
        let reminderTime = ReminderValidation.validatedReminderTime(
            from: pillObject,
            reminderEnabled: reminderEnabled,
            area: "details",
            report: &report
        )
        guard !reminderEnabled || reminderTime != nil else {
            report.append(
                area: "details",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill details failed because reminder fields are corrupted."
            )
            let error = report.makeError(operation: "fetchPillDetails")
            ReliabilityLog.error("pill.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        return PillDetailsProjection(
            id: id,
            name: name,
            dosage: dosage,
            details: pillObject.stringValue(forKey: "detailsText"),
            startDate: startDate,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            scheduleDays: latestSchedule?.weekdays ?? .daily,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            totalTakenDays: Set(successfulIntakes.map { Calendar.current.startOfDay(for: $0.localDate) }).count,
            takenDays: Set(successfulIntakes.map { Calendar.current.startOfDay(for: $0.localDate) }),
            skippedDays: skippedDays
        )
    }

    func createPill(from draft: PillDraft) throws -> UUID {
        try repositoryContext.performWrite({ context in
            let countRequest = NSFetchRequest<NSDictionary>(entityName: "Pill")
            countRequest.resultType = .dictionaryResultType
            countRequest.propertiesToFetch = ["sortOrder"]
            countRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
            countRequest.fetchLimit = 1

            let maxSortOrder = try context.fetch(countRequest).first?["sortOrder"] as? Int32 ?? -1
            let now = Date()
            let pillID = UUID()

            let pill = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
            pill.setValue(pillID, forKey: "id")
            pill.setValue(draft.trimmedName, forKey: "name")
            pill.setValue(draft.trimmedDosage, forKey: "dosage")
            pill.setValue(draft.normalizedDetails, forKey: "detailsText")
            pill.setValue(maxSortOrder + 1, forKey: "sortOrder")
            pill.setValue(Calendar.current.startOfDay(for: draft.startDate), forKey: "startDate")
            pill.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            pill.setValue(now, forKey: "createdAt")
            pill.setValue(now, forKey: "updatedAt")
            pill.setValue(Int32(1), forKey: "version")

            let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
            schedule.setValue(UUID(), forKey: "id")
            schedule.setValue(pillID, forKey: "pillID")
            schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
            schedule.setValue(Calendar.current.startOfDay(for: draft.startDate), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(pill, forKey: "pill")

            for takenDay in draft.takenDays {
                let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
                intake.setValue(UUID(), forKey: "id")
                intake.setValue(pillID, forKey: "pillID")
                intake.setValue(Calendar.current.startOfDay(for: takenDay), forKey: "localDate")
                intake.setValue(PillCompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                intake.setValue(now, forKey: "createdAt")
                intake.setValue(pill, forKey: "pill")
            }

            try context.save()
            return pillID
        }, missingResultError: PillRepositoryError.internalFailure)
    }

    func updatePill(from draft: EditPillDraft) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: draft.id, in: context) else { return }

            pill.setValue(draft.trimmedName, forKey: "name")
            pill.setValue(draft.trimmedDosage, forKey: "dosage")
            pill.setValue(draft.normalizedDetails, forKey: "detailsText")
            pill.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            pill.setValue(Date(), forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: pill)
            let currentWeekdayMask = currentSchedule?.int16Value(forKey: "weekdayMask") ?? 0
            if currentWeekdayMask != draft.scheduleDays.rawValue {
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "pillID")
                schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
                schedule.setValue(Calendar.current.startOfDay(for: Date()), forKey: "effectiveFrom")
                schedule.setValue(Date(), forKey: "createdAt")
                schedule.setValue(currentSchedule.map { $0.int32Value(forKey: "version") + 1 } ?? 1, forKey: "version")
                schedule.setValue(pill, forKey: "pill")
            }

            let existingIntakeObjects = (pill.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
            let editableSet = EditableHistoryWindow.dates(startDate: draft.startDate)
            let existingByDay = Dictionary(uniqueKeysWithValues: existingIntakeObjects.compactMap { object -> (Date, NSManagedObject)? in
                guard let localDate = object.dateValue(forKey: "localDate") else { return nil }
                return (Calendar.current.startOfDay(for: localDate), object)
            })

            for day in editableSet {
                let shouldBeTaken = draft.takenDays.contains(day)
                let shouldBeSkipped = draft.skippedDays.contains(day)
                let existing = existingByDay[day]

                if shouldBeTaken, existing == nil {
                    let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
                    intake.setValue(UUID(), forKey: "id")
                    intake.setValue(draft.id, forKey: "pillID")
                    intake.setValue(day, forKey: "localDate")
                    intake.setValue(PillCompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                    intake.setValue(Date(), forKey: "createdAt")
                    intake.setValue(pill, forKey: "pill")
                } else if shouldBeTaken, let existing {
                    guard
                        let sourceRaw = existing.stringValue(forKey: "sourceRaw"),
                        let source = PillCompletionSource(rawValue: sourceRaw)
                    else {
                        continue
                    }

                    if !source.countsAsIntake {
                        existing.setValue(PillCompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                        existing.setValue(Date(), forKey: "createdAt")
                    }
                } else if shouldBeSkipped, existing == nil {
                    let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
                    intake.setValue(UUID(), forKey: "id")
                    intake.setValue(draft.id, forKey: "pillID")
                    intake.setValue(day, forKey: "localDate")
                    intake.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
                    intake.setValue(Date(), forKey: "createdAt")
                    intake.setValue(pill, forKey: "pill")
                } else if shouldBeSkipped, let existing {
                    guard
                        let sourceRaw = existing.stringValue(forKey: "sourceRaw"),
                        let source = PillCompletionSource(rawValue: sourceRaw)
                    else {
                        continue
                    }

                    if source != .skipped {
                        existing.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
                        existing.setValue(Date(), forKey: "createdAt")
                    }
                } else if let existing {
                    context.delete(existing)
                }
            }

            try context.save()
        }
    }

    func deletePill(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            context.delete(pill)
            try context.save()
        }
    }

    func markTakenToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            let today = Calendar.current.startOfDay(for: Date())
            if let existingIntake = try fetchIntake(for: id, on: today, in: context) {
                guard
                    let sourceRaw = existingIntake.value(forKey: "sourceRaw") as? String,
                    let source = PillCompletionSource(rawValue: sourceRaw)
                else {
                    return
                }

                if source == .skipped {
                    existingIntake.setValue(PillCompletionSource.swipe.rawValue, forKey: "sourceRaw")
                    existingIntake.setValue(Date(), forKey: "createdAt")
                    try context.save()
                }
                return
            }

            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(id, forKey: "pillID")
            intake.setValue(today, forKey: "localDate")
            intake.setValue(PillCompletionSource.swipe.rawValue, forKey: "sourceRaw")
            intake.setValue(Date(), forKey: "createdAt")
            intake.setValue(pill, forKey: "pill")

            try context.save()
        }
    }

    func skipPillToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            let today = Calendar.current.startOfDay(for: Date())

            if let existingIntake = try fetchIntake(for: id, on: today, in: context) {
                guard
                    let sourceRaw = existingIntake.value(forKey: "sourceRaw") as? String,
                    let source = PillCompletionSource(rawValue: sourceRaw)
                else {
                    return
                }

                guard source == .skipped else { return }
                return
            }

            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(id, forKey: "pillID")
            intake.setValue(today, forKey: "localDate")
            intake.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
            intake.setValue(Date(), forKey: "createdAt")
            intake.setValue(pill, forKey: "pill")

            try context.save()
        }
    }

    func clearPillDayStateToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            let today = Calendar.current.startOfDay(for: Date())
            guard let intake = try fetchIntake(for: id, on: today, in: context) else { return }
            context.delete(intake)
            try context.save()
        }
    }

    func movePills(from offsets: IndexSet, to destination: Int) throws {
        try repositoryContext.performWrite { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
            request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            let pills = reorderedItems(try context.fetch(request), from: offsets, to: destination)

            for (index, pill) in pills.enumerated() {
                pill.setValue(Int32(index), forKey: "sortOrder")
            }

            try context.save()
        }
    }

    private func fetchPill(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchIntake(for pillID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PillIntake")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "pillID == %@", pillID as CVarArg),
            NSPredicate(format: "localDate == %@", localDate as CVarArg),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func loadIntakes(for pillObject: NSManagedObject, pillID: UUID) -> [PillIntake] {
        let intakes = (pillObject.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
        return intakes.compactMap { intakeObject in
            guard
                let intakeID = intakeObject.uuidValue(forKey: "id"),
                let localDate = intakeObject.dateValue(forKey: "localDate"),
                let sourceRaw = intakeObject.stringValue(forKey: "sourceRaw"),
                let source = PillCompletionSource(rawValue: sourceRaw),
                let createdAt = intakeObject.dateValue(forKey: "createdAt")
            else {
                return nil
            }

            return PillIntake(
                id: intakeID,
                pillID: pillID,
                localDate: localDate,
                source: source,
                createdAt: createdAt
            )
        }
    }

    private func loadIntakes(
        for pillObject: NSManagedObject,
        pillID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [PillIntake]? {
        let intakes = (pillObject.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
        var models: [PillIntake] = []

        for intakeObject in intakes {
            guard
                let intakeID = intakeObject.uuidValue(forKey: "id"),
                let localDate = intakeObject.dateValue(forKey: "localDate"),
                let sourceRaw = intakeObject.stringValue(forKey: "sourceRaw"),
                let source = PillCompletionSource(rawValue: sourceRaw),
                let createdAt = intakeObject.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: "dashboard",
                    entityName: intakeObject.entityName,
                    object: intakeObject,
                    message: "Pill intake row is missing required fields or has invalid sourceRaw."
                )
                return nil
            }

            models.append(
                PillIntake(
                    id: intakeID,
                    pillID: pillID,
                    localDate: localDate,
                    source: source,
                    createdAt: createdAt
                )
            )
        }

        return models
    }

    private func loadSchedules(for pillObject: NSManagedObject, pillID: UUID) -> [PillScheduleVersion] {
        let schedules = (pillObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        return schedules.compactMap { scheduleObject in
            guard
                let scheduleID = scheduleObject.uuidValue(forKey: "id"),
                let effectiveFrom = scheduleObject.dateValue(forKey: "effectiveFrom"),
                let createdAt = scheduleObject.dateValue(forKey: "createdAt")
            else {
                return nil
            }

            let weekdayMask = scheduleObject.int16Value(forKey: "weekdayMask")
            let version = Int(scheduleObject.int32Value(forKey: "version", default: 1))

            return PillScheduleVersion(
                id: scheduleID,
                pillID: pillID,
                weekdays: WeekdaySet(rawValue: weekdayMask),
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func loadSchedules(
        for pillObject: NSManagedObject,
        pillID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [PillScheduleVersion]? {
        let schedules = (pillObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        var models: [PillScheduleVersion] = []

        for scheduleObject in schedules {
            guard
                let scheduleID = scheduleObject.uuidValue(forKey: "id"),
                let effectiveFrom = scheduleObject.dateValue(forKey: "effectiveFrom"),
                let createdAt = scheduleObject.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: "dashboard",
                    entityName: scheduleObject.entityName,
                    object: scheduleObject,
                    message: "Pill schedule row is missing required fields."
                )
                return nil
            }

            models.append(
                PillScheduleVersion(
                    id: scheduleID,
                    pillID: pillID,
                    weekdays: WeekdaySet(rawValue: Int(scheduleObject.int16Value(forKey: "weekdayMask"))),
                    effectiveFrom: effectiveFrom,
                    createdAt: createdAt,
                    version: Int(scheduleObject.int32Value(forKey: "version", default: 1))
                )
            )
        }

        return models
    }

    private func makeDashboardProjection(
        from pillObject: NSManagedObject,
        today: Date,
        report: inout IntegrityReportBuilder
    ) -> PillCardProjection? {
        guard
            let id = pillObject.uuidValue(forKey: "id"),
            let name = pillObject.stringValue(forKey: "name"),
            let dosage = pillObject.stringValue(forKey: "dosage")
        else {
            report.append(
                area: "dashboard",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill row is missing required fields."
            )
            return nil
        }

        guard
            let schedules = loadSchedules(for: pillObject, pillID: id, report: &report),
            let intakes = loadIntakes(for: pillObject, pillID: id, report: &report)
        else {
            report.append(
                area: "dashboard",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill dashboard projection was skipped because related rows are corrupted."
            )
            return nil
        }

        let latestSchedule = schedules.sorted(by: isNewerSchedule).first
        let successfulIntakes = intakes.filter { $0.source.countsAsIntake }
        let isTakenToday = successfulIntakes.contains { Calendar.current.isDate($0.localDate, inSameDayAs: today) }
        let isSkippedToday = intakes.contains {
            !$0.source.countsAsIntake && Calendar.current.isDate($0.localDate, inSameDayAs: today)
        }
        let reminderEnabled = pillObject.boolValue(forKey: "reminderEnabled")
        let validatedReminderTime = ReminderValidation.validatedReminderTime(
            from: pillObject,
            reminderEnabled: reminderEnabled,
            area: "dashboard",
            report: &report
        )
        guard !reminderEnabled || validatedReminderTime != nil else {
            report.append(
                area: "dashboard",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill dashboard projection was skipped because reminder fields are corrupted."
            )
            return nil
        }
        let reminderText = validatedReminderTime?.formatted
        let isScheduledToday = latestSchedule?.weekdays.contains(Calendar.current.weekdaySet(for: today)) ?? false

        return PillCardProjection(
            id: id,
            name: name,
            dosage: dosage,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            totalTakenDays: Set(successfulIntakes.map { Calendar.current.startOfDay(for: $0.localDate) }).count,
            reminderText: reminderText,
            reminderHour: validatedReminderTime?.hour,
            reminderMinute: validatedReminderTime?.minute,
            isReminderScheduledToday: isScheduledToday,
            isScheduledToday: isScheduledToday,
            isTakenToday: isTakenToday,
            isSkippedToday: isSkippedToday,
            sortOrder: Int(pillObject.int32Value(forKey: "sortOrder"))
        )
    }

    private func loadLatestScheduleObject(for pillObject: NSManagedObject) -> NSManagedObject? {
        CoreDataScheduleSupport.latestScheduleObject(in: pillObject.mutableSetValue(forKey: "scheduleVersions"))
    }

    private func isNewerSchedule(_ lhs: PillScheduleVersion, _ rhs: PillScheduleVersion) -> Bool {
        if lhs.effectiveFrom != rhs.effectiveFrom {
            return lhs.effectiveFrom > rhs.effectiveFrom
        }
        if lhs.version != rhs.version {
            return lhs.version > rhs.version
        }
        return lhs.createdAt > rhs.createdAt
    }

    private func pillDashboardSort(_ lhs: PillCardProjection, _ rhs: PillCardProjection) -> Bool {
        let lhsTime = reminderSortKey(for: lhs)
        let rhsTime = reminderSortKey(for: rhs)

        if lhsTime != rhsTime {
            return lhsTime < rhsTime
        }

        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func reminderSortKey(for pill: PillCardProjection) -> Int {
        guard let hour = pill.reminderHour, let minute = pill.reminderMinute else {
            return Int.max
        }

        return hour * 60 + minute
    }

    private func reorderedItems<T>(_ items: [T], from offsets: IndexSet, to destination: Int) -> [T] {
        var reordered = items
        let movedItems = offsets.map { reordered[$0] }

        for offset in offsets.sorted(by: >) {
            reordered.remove(at: offset)
        }

        let insertionIndex = min(
            destination - offsets.count(in: 0..<destination),
            reordered.count
        )
        reordered.insert(contentsOf: movedItems, at: insertionIndex)
        return reordered
    }
}
