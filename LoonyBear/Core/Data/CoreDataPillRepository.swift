import CoreData
import Foundation

@MainActor
struct CoreDataPillRepository: PillRepository {
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

    func fetchDashboardPills() throws -> [PillCardProjection] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        let pills = try readContext.fetch(request)
        let today = calendar.startOfDay(for: clock.now())
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
            let startDate = pillObject.dateValue(forKey: "startDate"),
            let historyMode = pillHistoryMode(for: pillObject, area: "details", report: &report)
        else {
            report.append(
                area: "details",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill details row is missing required fields or has invalid history mode."
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

        let latestSchedule = schedules.sorted(by: CoreDataScheduleSupport.isNewerSchedule).first
        let successfulIntakes = intakes.filter { $0.source.countsAsIntake }
        let skippedDays = Set(
            intakes
                .filter { !$0.source.countsAsIntake }
                .map { calendar.startOfDay(for: $0.localDate) }
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
            historyMode: historyMode,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            scheduleDays: latestSchedule?.weekdays ?? .daily,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            totalTakenDays: Set(successfulIntakes.map { calendar.startOfDay(for: $0.localDate) }).count,
            takenDays: Set(successfulIntakes.map { calendar.startOfDay(for: $0.localDate) }),
            skippedDays: skippedDays
        )
    }

    func reconcilePastDays(today: Date) throws -> Int {
        try repositoryContext.performWrite({ context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
            let pills = try context.fetch(request)
            let normalizedToday = calendar.startOfDay(for: today)
            var report = IntegrityReportBuilder()
            var insertedCount = 0

            for pillObject in pills {
                guard
                    let pillID = pillObject.uuidValue(forKey: "id"),
                    let startDate = pillObject.dateValue(forKey: "startDate"),
                    let historyMode = pillHistoryMode(for: pillObject, area: "reconciliation", report: &report)
                else {
                    report.append(
                        area: "reconciliation",
                        entityName: pillObject.entityName,
                        object: pillObject,
                        message: "Pill row is missing required fields or has invalid history mode for history reconciliation."
                    )
                    continue
                }

                guard
                    let schedules = loadSchedules(for: pillObject, pillID: pillID, report: &report),
                    let intakeModels = loadIntakes(for: pillObject, pillID: pillID, report: &report)
                else {
                    report.append(
                        area: "reconciliation",
                        entityName: pillObject.entityName,
                        object: pillObject,
                        message: "Pill reconciliation failed because related rows are corrupted."
                    )
                    continue
                }

                let existingIntakeObjects = (pillObject.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
                let existingIntakeObjectsByDay = CoreDataHistorySupport.groupedHistoryObjectsByDay(existingIntakeObjects)
                insertedCount += autoFinalizeMissingSkippedIntakes(
                    for: pillObject,
                    pillID: pillID,
                    startDate: startDate,
                    historyMode: historyMode,
                    schedules: schedules,
                    intakeObjectsByDay: existingIntakeObjectsByDay,
                    intakeModels: intakeModels,
                    today: normalizedToday,
                    context: context
                )
            }

            if report.hasIssues {
                throw report.makeError(operation: "pill.reconcilePastDays")
            }

            if insertedCount > 0 {
                try context.save()
            }

            return insertedCount
        }, missingResultError: PillRepositoryError.internalFailure)
    }

    func createPill(from draft: PillDraft) throws -> UUID {
        try repositoryContext.performWrite({ context in
            let countRequest = NSFetchRequest<NSDictionary>(entityName: "Pill")
            countRequest.resultType = .dictionaryResultType
            countRequest.propertiesToFetch = ["sortOrder"]
            countRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
            countRequest.fetchLimit = 1

            let maxSortOrder = try context.fetch(countRequest).first?["sortOrder"] as? Int32 ?? -1
            let now = clock.now()
            let pillID = UUID()

            let pill = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
            pill.setValue(pillID, forKey: "id")
            pill.setValue(draft.trimmedName, forKey: "name")
            pill.setValue(draft.trimmedDosage, forKey: "dosage")
            pill.setValue(draft.normalizedDetails, forKey: "detailsText")
            pill.setValue(maxSortOrder + 1, forKey: "sortOrder")
            pill.setValue(calendar.startOfDay(for: draft.startDate), forKey: "startDate")
            pill.setValue(
                draft.useScheduleForHistory ? PillHistoryMode.scheduleBased.rawValue : PillHistoryMode.everyDay.rawValue,
                forKey: "historyModeRaw"
            )
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
            schedule.setValue(calendar.startOfDay(for: draft.startDate), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(pill, forKey: "pill")

            for takenDay in draft.takenDays {
                let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
                intake.setValue(UUID(), forKey: "id")
                intake.setValue(pillID, forKey: "pillID")
                intake.setValue(calendar.startOfDay(for: takenDay), forKey: "localDate")
                intake.setValue(PillCompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                intake.setValue(now, forKey: "createdAt")
                intake.setValue(pill, forKey: "pill")
            }

            _ = autoFinalizeMissingSkippedIntakes(
                for: pill,
                pillID: pillID,
                startDate: draft.startDate,
                historyMode: draft.useScheduleForHistory ? .scheduleBased : .everyDay,
                schedules: [
                    PillScheduleVersion(
                        id: schedule.uuidValue(forKey: "id") ?? UUID(),
                        pillID: pillID,
                        weekdays: draft.scheduleDays,
                        effectiveFrom: calendar.startOfDay(for: draft.startDate),
                        createdAt: now,
                        version: 1
                    ),
                ],
                intakeObjectsByDay: [:],
                intakeModels: draft.takenDays.map {
                    PillIntake(
                        id: UUID(),
                        pillID: pillID,
                        localDate: calendar.startOfDay(for: $0),
                        source: .manualEdit,
                        createdAt: now
                    )
                },
                today: now,
                context: context
            )

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
            let now = clock.now()
            pill.setValue(now, forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: pill)
            let currentWeekdayMask = currentSchedule?.int16Value(forKey: "weekdayMask") ?? 0
            if currentWeekdayMask != draft.scheduleDays.rawValue {
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "pillID")
                schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
                schedule.setValue(calendar.startOfDay(for: now), forKey: "effectiveFrom")
                schedule.setValue(now, forKey: "createdAt")
                schedule.setValue(currentSchedule.map { $0.int32Value(forKey: "version") + 1 } ?? 1, forKey: "version")
                schedule.setValue(pill, forKey: "pill")
            }

            let normalizedToday = calendar.startOfDay(for: now)
            let existingIntakeObjects = (pill.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
            let editableSet = EditableHistoryWindow.dates(
                startDate: draft.startDate,
                today: normalizedToday,
                calendar: calendar
            )
            let historyMode = persistedHistoryMode(for: pill)
            let schedules = loadSchedules(for: pill, pillID: draft.id)
            let requiredFinalizedDays: Set<Date>
            switch historyMode {
            case .scheduleBased:
                requiredFinalizedDays = HistoryScheduleApplicability.pastScheduledEditableDays(
                    in: editableSet,
                    schedules: schedules,
                    today: normalizedToday,
                    calendar: calendar
                )
            case .everyDay:
                requiredFinalizedDays = HistoryScheduleApplicability.pastEditableDays(
                    in: editableSet,
                    today: normalizedToday,
                    calendar: calendar
                )
            }
            let normalizedSelection = EditableHistoryContract.normalizedSelection(
                positiveDays: draft.takenDays,
                skippedDays: draft.skippedDays,
                requiredFinalizedDays: requiredFinalizedDays,
                today: normalizedToday,
                calendar: calendar
            )
            let existingByDay = CoreDataHistorySupport.groupedHistoryObjectsByDay(existingIntakeObjects)

            for day in editableSet {
                let shouldBeTaken = normalizedSelection.positiveDays.contains(day)
                let shouldBeSkipped = normalizedSelection.skippedDays.contains(day)
                let existingObjects = existingByDay[day] ?? []
                let existing = primaryHistoryObject(in: existingObjects)

                for duplicate in existingObjects where duplicate != existing {
                    context.delete(duplicate)
                }

                if shouldBeTaken {
                    _ = try upsertIntake(
                        for: pill,
                        pillID: draft.id,
                        on: day,
                        source: .manualEdit,
                        in: context,
                        updateWhen: { !$0.countsAsIntake }
                    )
                } else if shouldBeSkipped {
                    _ = try upsertIntake(
                        for: pill,
                        pillID: draft.id,
                        on: day,
                        source: .skipped,
                        in: context,
                        updateWhen: { $0 != .skipped }
                    )
                } else if day == normalizedToday, let existing {
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
            let today = calendar.startOfDay(for: clock.now())
            let didChange = try upsertIntake(
                for: pill,
                pillID: id,
                on: today,
                source: .swipe,
                in: context,
                updateWhen: { $0 == .skipped }
            )

            guard didChange else { return }
            try context.save()
        }
    }

    func skipPillToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            let today = calendar.startOfDay(for: clock.now())
            let didChange = try upsertIntake(
                for: pill,
                pillID: id,
                on: today,
                source: .skipped,
                in: context,
                updateWhen: { _ in false }
            )

            guard didChange else { return }
            try context.save()
        }
    }

    func clearPillDayStateToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            let today = calendar.startOfDay(for: clock.now())
            let intakes = try fetchIntakes(for: id, on: today, in: context)
            guard !intakes.isEmpty else { return }

            for intake in intakes {
                context.delete(intake)
            }
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
        try CoreDataFetchSupport.fetchObject(
            entityName: "Pill",
            id: id,
            in: context
        )
    }

    private func fetchIntake(for pillID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        try CoreDataFetchSupport.fetchHistoryObject(
            entityName: "PillIntake",
            ownerKey: "pillID",
            ownerID: pillID,
            localDate: localDate,
            in: context
        )
    }

    private func fetchIntakes(for pillID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        try CoreDataFetchSupport.fetchHistoryObjects(
            entityName: "PillIntake",
            ownerKey: "pillID",
            ownerID: pillID,
            localDate: localDate,
            in: context
        )
    }

    private func primaryHistoryObject(in objects: [NSManagedObject]) -> NSManagedObject? {
        CoreDataHistorySupport.primaryHistoryObject(in: objects)
    }

    private func upsertIntake(
        for pill: NSManagedObject,
        pillID: UUID,
        on localDate: Date,
        source desiredSource: PillCompletionSource,
        in context: NSManagedObjectContext,
        updateWhen shouldUpdate: (PillCompletionSource) -> Bool
    ) throws -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        let existingObjects = try fetchIntakes(for: pillID, on: normalizedDate, in: context)
        let existing = primaryHistoryObject(in: existingObjects)
        let duplicateObjects = existingObjects.filter { $0 != existing }

        for duplicate in duplicateObjects {
            context.delete(duplicate)
        }

        guard let existing else {
            insertIntake(
                for: pill,
                pillID: pillID,
                on: normalizedDate,
                source: desiredSource,
                in: context
            )
            return true
        }

        guard
            let sourceRaw = existing.stringValue(forKey: "sourceRaw"),
            let existingSource = PillCompletionSource(rawValue: sourceRaw)
        else {
            return !duplicateObjects.isEmpty
        }

        guard shouldUpdate(existingSource), existingSource != desiredSource else {
            return !duplicateObjects.isEmpty
        }

        existing.setValue(desiredSource.rawValue, forKey: "sourceRaw")
        existing.setValue(clock.now(), forKey: "createdAt")
        existing.setValue(pill, forKey: "pill")
        return true
    }

    private func insertIntake(
        for pill: NSManagedObject,
        pillID: UUID,
        on localDate: Date,
        source: PillCompletionSource,
        in context: NSManagedObjectContext
    ) {
        let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
        intake.setValue(UUID(), forKey: "id")
        intake.setValue(pillID, forKey: "pillID")
        intake.setValue(localDate, forKey: "localDate")
        intake.setValue(source.rawValue, forKey: "sourceRaw")
        intake.setValue(clock.now(), forKey: "createdAt")
        intake.setValue(pill, forKey: "pill")
    }

    private func autoFinalizeMissingSkippedIntakes(
        for pillObject: NSManagedObject,
        pillID: UUID,
        startDate: Date,
        historyMode: PillHistoryMode,
        schedules: [PillScheduleVersion],
        intakeObjectsByDay: [Date: [NSManagedObject]],
        intakeModels: [PillIntake],
        today: Date,
        context: NSManagedObjectContext
    ) -> Int {
        let normalizedToday = calendar.startOfDay(for: today)
        let intakeDays = Set(intakeModels.map { calendar.startOfDay(for: $0.localDate) })
        let skippedDays = Set(
            intakeModels
                .filter { !$0.source.countsAsIntake }
                .map { calendar.startOfDay(for: $0.localDate) }
        )
        let editableDays = EditableHistoryWindow.dates(
            startDate: startDate,
            today: normalizedToday,
            calendar: calendar
        )
        let requiredFinalizedDays: Set<Date>
        switch historyMode {
        case .scheduleBased:
            requiredFinalizedDays = HistoryScheduleApplicability.pastScheduledEditableDays(
                in: editableDays,
                schedules: schedules,
                today: normalizedToday,
                calendar: calendar
            )
        case .everyDay:
            requiredFinalizedDays = HistoryScheduleApplicability.pastEditableDays(
                in: editableDays,
                today: normalizedToday,
                calendar: calendar
            )
        }

        var insertedCount = 0
        for day in requiredFinalizedDays.sorted() {
            guard !intakeDays.contains(day) else { continue }
            guard !skippedDays.contains(day) else { continue }
            guard (intakeObjectsByDay[day] ?? []).isEmpty else { continue }

            let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
            intake.setValue(UUID(), forKey: "id")
            intake.setValue(pillID, forKey: "pillID")
            intake.setValue(day, forKey: "localDate")
            intake.setValue(PillCompletionSource.skipped.rawValue, forKey: "sourceRaw")
            intake.setValue(clock.now(), forKey: "createdAt")
            intake.setValue(pillObject, forKey: "pill")
            insertedCount += 1
        }

        return insertedCount
    }

    private func loadIntakes(for pillObject: NSManagedObject, pillID: UUID) -> [PillIntake] {
        CoreDataRelationshipLoadingSupport.compactHistoryModels(
            from: pillObject,
            relationshipKey: "intakes"
        ) { intakeID, localDate, source, createdAt in
            PillIntake(
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
        CoreDataRelationshipLoadingSupport.validatedHistoryModels(
            from: pillObject,
            relationshipKey: "intakes",
            area: "dashboard",
            invalidMessage: "Pill intake row is missing required fields or has invalid sourceRaw.",
            report: &report
        ) { intakeID, localDate, source, createdAt in
            PillIntake(
                id: intakeID,
                pillID: pillID,
                localDate: localDate,
                source: source,
                createdAt: createdAt
            )
        }
    }

    private func loadSchedules(for pillObject: NSManagedObject, pillID: UUID) -> [PillScheduleVersion] {
        CoreDataRelationshipLoadingSupport.compactScheduleModels(
            from: pillObject,
            relationshipKey: "scheduleVersions"
        ) { scheduleID, weekdayMask, effectiveFrom, createdAt, version in
            PillScheduleVersion(
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
        CoreDataRelationshipLoadingSupport.validatedScheduleModels(
            from: pillObject,
            relationshipKey: "scheduleVersions",
            area: "dashboard",
            missingFieldsMessage: "Pill schedule row is missing required fields.",
            invalidMaskMessage: "Pill schedule row contains invalid weekdayMask.",
            report: &report
        ) { scheduleID, weekdayMask, effectiveFrom, createdAt, version in
            PillScheduleVersion(
                id: scheduleID,
                pillID: pillID,
                weekdays: WeekdaySet(rawValue: weekdayMask),
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func makeDashboardProjection(
        from pillObject: NSManagedObject,
        today: Date,
        report: inout IntegrityReportBuilder
    ) -> PillCardProjection? {
        guard
            let id = pillObject.uuidValue(forKey: "id"),
            let name = pillObject.stringValue(forKey: "name"),
            let dosage = pillObject.stringValue(forKey: "dosage"),
            pillHistoryMode(for: pillObject, area: "dashboard", report: &report) != nil
        else {
            report.append(
                area: "dashboard",
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill row is missing required fields or has invalid history mode."
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

        let latestSchedule = schedules.sorted(by: CoreDataScheduleSupport.isNewerSchedule).first
        let successfulIntakes = intakes.filter { $0.source.countsAsIntake }
        let isTakenToday = successfulIntakes.contains { calendar.isDate($0.localDate, inSameDayAs: today) }
        let isSkippedToday = intakes.contains {
            !$0.source.countsAsIntake && calendar.isDate($0.localDate, inSameDayAs: today)
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
        let isScheduledToday = latestSchedule?.weekdays.contains(calendar.weekdaySet(for: today)) ?? false

        return PillCardProjection(
            id: id,
            name: name,
            dosage: dosage,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            totalTakenDays: Set(successfulIntakes.map { calendar.startOfDay(for: $0.localDate) }).count,
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

    private func pillHistoryMode(
        for pillObject: NSManagedObject,
        area: String,
        report: inout IntegrityReportBuilder
    ) -> PillHistoryMode? {
        guard let rawValue = pillObject.stringValue(forKey: "historyModeRaw"),
              let historyMode = PillHistoryMode(rawValue: rawValue) else {
            report.append(
                area: area,
                entityName: pillObject.entityName,
                object: pillObject,
                message: "Pill row is missing required historyModeRaw or contains an invalid history mode."
            )
            return nil
        }
        return historyMode
    }

    private func persistedHistoryMode(for pillObject: NSManagedObject) -> PillHistoryMode {
        guard let rawValue = pillObject.stringValue(forKey: "historyModeRaw"),
              let historyMode = PillHistoryMode(rawValue: rawValue) else {
            return .scheduleBased
        }

        return historyMode
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
