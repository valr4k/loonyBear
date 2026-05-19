import CoreData
import Foundation

@MainActor
struct CoreDataPillRepository: PillRepository {
    private let readContext: NSManagedObjectContext
    private let repositoryContext: CoreDataRepositoryContext
    private let calendar: Calendar
    private let clock: AppClock
    private let overdueAnchorStore: OverdueAnchorStore

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext,
        calendar: Calendar = .autoupdatingCurrent,
        clock: AppClock? = nil,
        overdueAnchorStore: OverdueAnchorStore? = nil
    ) {
        let resolvedClock = clock ?? AppClock(calendar: calendar)
        readContext = context
        self.calendar = resolvedClock.calendar
        self.clock = resolvedClock
        self.overdueAnchorStore = overdueAnchorStore ?? UserDefaultsOverdueAnchorStore.shared
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
        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        var report = IntegrityReportBuilder()
        var projections: [PillCardProjection] = []

        for pillObject in pills {
            if let projection = makeDashboardProjection(
                from: pillObject,
                now: now,
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
            let historySnapshot = CoreDataHistoryBucketSupport.validatedSnapshot(
                from: pillObject,
                bucketRelationshipKey: "historyBuckets",
                rangeRelationshipKey: "historyRanges",
                rangeOwnerKey: "pillID",
                ownerID: id,
                legacyRelationshipKey: "intakes",
                area: "details",
                invalidBucketMessage: "Pill history bucket row is missing required fields or has overlapping masks.",
                invalidRangeMessage: "Pill history range row is missing required fields or has invalid schedule/count.",
                invalidLegacyMessage: "Pill intake row is missing required fields or has invalid sourceRaw.",
                report: &report,
                legacySourceToState: bucketState(from:),
                calendar: calendar
            )
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

        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        let endDate = pillObject.dateValue(forKey: "endDate")
        let isArchived = pillObject.boolValue(forKey: "isArchived")
        let activeStartDate = ActiveCycleStartDate.value(
            for: pillObject,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        let displayRange = initialDetailsHistoryRange(startDate: activeStartDate, today: today)
        let historySets = historySnapshot.daySets(
            from: displayRange.lowerBound,
            through: displayRange.upperBound,
            calendar: calendar
        )
        let takenDays = historySets.positiveDays
        let skippedDays = historySets.skippedDays
        let archivedDays = historySets.archivedDays
        let activeOverdueDay = isArchived ? nil : ScheduledOverdueState.activeOverdueDay(
            startDate: activeStartDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            hasPositiveState: { historySnapshot.state(on: $0, calendar: calendar) == .positive },
            hasSkippedState: { historySnapshot.state(on: $0, calendar: calendar) == .skipped },
            now: now,
            calendar: calendar
        )
        let scheduledDates = HistoryScheduleApplicability.scheduledDays(
            in: initialCalendarMonthRange(startDate: activeStartDate, today: today),
            startDate: activeStartDate,
            limitingTo: endDate,
            schedules: schedules,
            calendar: calendar
        )

        return PillDetailsProjection(
            id: id,
            name: name,
            dosage: dosage,
            details: pillObject.stringValue(forKey: "detailsText"),
            startDate: startDate,
            activeFrom: pillObject.dateValue(forKey: "activeFrom"),
            endDate: endDate,
            historyMode: historyMode,
            scheduleSummary: latestSchedule?.rule.summary ?? "No days selected",
            scheduleDays: latestSchedule?.rule.weeklyDays ?? .daily,
            scheduleRule: latestSchedule?.rule ?? .weekly(.daily),
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            totalTakenDays: historySnapshot.positiveCount,
            takenDays: takenDays,
            skippedDays: skippedDays,
            archivedDays: archivedDays,
            historySnapshot: historySnapshot,
            scheduleHistory: schedules,
            scheduledDates: scheduledDates,
            needsHistoryReview: !isArchived && needsHistoryReview(
                startDate: activeStartDate,
                endDate: endDate,
                schedules: schedules,
                positiveDays: takenDays,
                skippedDays: skippedDays,
                today: today,
                activeOverdueDay: activeOverdueDay
            ),
            requiredPastScheduledDays: isArchived ? [] : requiredPastScheduledDays(
                startDate: activeStartDate,
                endDate: endDate,
                schedules: schedules,
                today: today
            ),
            activeOverdueDay: activeOverdueDay,
            isArchived: isArchived,
            archivedAt: pillObject.dateValue(forKey: "archivedAt")
        )
    }

    func reconcilePastDays(today: Date) throws -> Int { 0 }

    func createPill(from draft: PillDraft) throws -> UUID {
        try repositoryContext.performWrite({ context in
            let totalPillsRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Pill")
            let totalPills = try context.count(for: totalPillsRequest)
            guard totalPills < 20 else {
                throw PillRepositoryError.tooManyPills
            }

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
            pill.setValue(draft.endDate.map { calendar.startOfDay(for: $0) }, forKey: "endDate")
            pill.setValue(false, forKey: "isArchived")
            pill.setValue(nil, forKey: "archivedAt")
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
            CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
            schedule.setValue(calendar.startOfDay(for: draft.startDate), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(pill, forKey: "pill")

            for takenDay in draft.takenDays {
                try insertIntake(
                    for: pill,
                    pillID: pillID,
                    on: takenDay,
                    source: .manualEdit,
                    in: context
                )
            }

            let existingTakenDays = Set(draft.takenDays.map { calendar.startOfDay(for: $0) })
            let initialTakenPlan = CoreDataInitialHistoryPlanner.positiveHistoryPlan(
                startDate: draft.startDate,
                endDate: draft.endDate,
                scheduleRule: draft.scheduleRule,
                useScheduleForHistory: draft.useScheduleForHistory,
                today: now,
                calendar: calendar
            )
            try CoreDataHistoryRangeSupport.insertRange(
                owner: pill,
                ownerID: pillID,
                draft: initialTakenPlan.coldRange,
                rangeEntityName: "PillHistoryRange",
                ownerKey: "pillID",
                ownerRelationshipKey: "pill",
                in: context,
                now: now
            )
            try CoreDataHistoryBucketSupport.setStates(
                owner: pill,
                ownerID: pillID,
                plan: initialTakenPlan.editableBucketPlan,
                state: .positive,
                bucketEntityName: "PillHistoryBucket",
                ownerKey: "pillID",
                ownerRelationshipKey: "pill",
                legacyEntityName: "PillIntake",
                rangeEntityName: "PillHistoryRange",
                in: context,
                calendar: calendar,
                now: now,
                shouldDeleteLegacyRows: false
            )

            applyAutomaticArchiveIfNeeded(
                for: pill,
                pillID: pillID,
                startDate: calendar.startOfDay(for: draft.startDate),
                endDate: draft.endDate,
                schedules: loadSchedules(for: pill, pillID: pillID),
                isFinalized: { day in
                    existingTakenDays.contains(day) || initialTakenPlan.contains(day, calendar: calendar)
                }
            )

            try context.save()
            return pillID
        }, missingResultError: PillRepositoryError.internalFailure)
    }

    func updatePill(from draft: EditPillDraft) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: draft.id, in: context) else { return }
            let wasArchived = pill.boolValue(forKey: "isArchived")

            pill.setValue(draft.trimmedName, forKey: "name")
            pill.setValue(draft.trimmedDosage, forKey: "dosage")
            pill.setValue(draft.normalizedDetails, forKey: "detailsText")
            pill.setValue(draft.endDate.map { calendar.startOfDay(for: $0) }, forKey: "endDate")
            pill.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            let now = clock.now()
            let normalizedToday = calendar.startOfDay(for: now)
            let activeStartDate = ActiveCycleStartDate.value(
                startDate: draft.startDate,
                activeFrom: draft.activeFrom,
                calendar: calendar
            )
            let normalizedSelection = EditableHistoryContract.normalizedSelection(
                positiveDays: draft.takenDays,
                skippedDays: draft.skippedDays,
                requiredFinalizedDays: [],
                pastDefaultSelection: .none,
                today: normalizedToday,
                calendar: calendar
            )
            pill.setValue(now, forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: pill)
            let currentRule = currentSchedule.flatMap(CoreDataScheduleSupport.rule)
            let requestedEffectiveFrom = draft.scheduleEffectiveFrom.map { calendar.startOfDay(for: $0) }
            let shouldCreateScheduleVersion: Bool = {
                guard let requestedEffectiveFrom else {
                    return currentRule != draft.scheduleRule
                }
                guard currentRule == draft.scheduleRule else {
                    return true
                }
                guard let currentEffectiveFrom = currentSchedule?.dateValue(forKey: "effectiveFrom") else {
                    return true
                }
                return calendar.startOfDay(for: currentEffectiveFrom) != requestedEffectiveFrom
            }()
            var savedEffectiveFrom: Date?
            if shouldCreateScheduleVersion {
                let effectiveFrom = resolvedScheduleEffectiveFrom(
                    from: draft,
                    normalizedSelection: normalizedSelection,
                    now: now
                )
                savedEffectiveFrom = effectiveFrom
                let scheduleRelationship = pill.mutableSetValue(forKey: "scheduleVersions")
                let nextVersion = CoreDataScheduleSupport.nextVersion(in: scheduleRelationship)
                CoreDataScheduleSupport.deleteScheduleObjects(
                    in: scheduleRelationship,
                    onOrAfter: effectiveFrom,
                    calendar: calendar,
                    context: context
                )
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "pillID")
                CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
                schedule.setValue(effectiveFrom, forKey: "effectiveFrom")
                schedule.setValue(now, forKey: "createdAt")
                schedule.setValue(nextVersion, forKey: "version")
                schedule.setValue(pill, forKey: "pill")
            }
            if wasArchived, let activeFrom = savedEffectiveFrom ?? requestedEffectiveFrom {
                pill.setValue(activeFrom, forKey: "activeFrom")
            }

            let editableSet = EditableHistoryWindow.dates(
                startDate: activeStartDate,
                today: normalizedToday,
                calendar: calendar
            )
            let scheduledEditableSet = HistoryScheduleApplicability.pastScheduledEditableDays(
                in: editableSet,
                startDate: activeStartDate,
                endDate: draft.endDate,
                schedules: loadSchedules(for: pill, pillID: draft.id),
                today: normalizedToday,
                calendar: calendar
            )
            let missingPastDays = EditableHistoryValidation.missingPastDays(
                editableDays: scheduledEditableSet,
                positiveDays: normalizedSelection.positiveDays,
                skippedDays: normalizedSelection.skippedDays,
                today: normalizedToday,
                calendar: calendar
            )
            guard wasArchived || missingPastDays.isEmpty else {
                throw EditableHistoryValidationError.missingPillPastDays(missingPastDays)
            }

            let existingByDay = try historySources(pillID: draft.id, on: editableSet, in: context)

            for day in editableSet {
                let shouldBeTaken = normalizedSelection.positiveDays.contains(day)
                let shouldBeSkipped = normalizedSelection.skippedDays.contains(day)
                let existing = existingByDay[day]

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
                } else if existing != nil {
                    _ = try clearIntake(for: pill, pillID: draft.id, on: day, in: context)
                }
            }

            applyAutomaticArchiveIfNeeded(
                for: pill,
                pillID: draft.id,
                positiveDays: normalizedSelection.positiveDays,
                skippedDays: normalizedSelection.skippedDays
            )

            try context.save()
            if !wasArchived {
                syncTodayOverdueAnchorAfterEdit(
                    pillID: draft.id,
                    startDate: activeStartDate,
                    endDate: draft.endDate,
                    schedules: loadSchedules(for: pill, pillID: draft.id),
                    reminderTime: draft.reminderEnabled ? draft.reminderTime : nil,
                    positiveDays: normalizedSelection.positiveDays,
                    skippedDays: normalizedSelection.skippedDays,
                    now: now
                )
            }
        }
    }

    func restorePill(from draft: EditPillDraft, historyMode: RestoreHistoryMode) throws -> Bool {
        try repositoryContext.performWrite({ context in
            guard let pill = try fetchPill(id: draft.id, in: context) else { return false }
            guard pill.boolValue(forKey: "isArchived") else { return false }

            let now = clock.now()
            let today = calendar.startOfDay(for: now)
            let archivedAt = pill.dateValue(forKey: "archivedAt").map { calendar.startOfDay(for: $0) } ?? today
            let activeFrom = calendar.startOfDay(for: draft.restoreActiveFrom ?? today)
            let minimumActiveFrom = restoreMinimumActiveFrom(archivedAt: archivedAt, today: today)
            guard activeFrom >= minimumActiveFrom else {
                throw PillRepositoryError.internalFailure
            }

            pill.setValue(draft.trimmedName, forKey: "name")
            pill.setValue(draft.trimmedDosage, forKey: "dosage")
            pill.setValue(draft.normalizedDetails, forKey: "detailsText")
            pill.setValue(draft.endDate.map { calendar.startOfDay(for: $0) }, forKey: "endDate")
            pill.setValue(false, forKey: "isArchived")
            pill.setValue(nil, forKey: "archivedAt")
            pill.setValue(activeFrom, forKey: "activeFrom")
            pill.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            pill.setValue(now, forKey: "updatedAt")

            if historyMode == .startFresh {
                pill.setValue(activeFrom, forKey: "startDate")
                deleteRelatedObjects(from: pill, relationshipKey: "historyBuckets", in: context)
                deleteRelatedObjects(from: pill, relationshipKey: "historyRanges", in: context)
                deleteRelatedObjects(from: pill, relationshipKey: "intakes", in: context)
                deleteRelatedObjects(from: pill, relationshipKey: "scheduleVersions", in: context)

                let scheduleID = UUID()
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
                schedule.setValue(scheduleID, forKey: "id")
                schedule.setValue(draft.id, forKey: "pillID")
                CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
                schedule.setValue(activeFrom, forKey: "effectiveFrom")
                schedule.setValue(now, forKey: "createdAt")
                schedule.setValue(Int32(1), forKey: "version")
                schedule.setValue(pill, forKey: "pill")

                try context.save()

                syncTodayOverdueAnchorAfterEdit(
                    pillID: draft.id,
                    startDate: activeFrom,
                    endDate: draft.endDate,
                    schedules: [
                        PillScheduleVersion(
                            id: scheduleID,
                            pillID: draft.id,
                            rule: draft.scheduleRule,
                            effectiveFrom: activeFrom,
                            createdAt: now,
                            version: 1
                        )
                    ],
                    reminderTime: draft.reminderEnabled ? draft.reminderTime : nil,
                    positiveDays: [],
                    skippedDays: [],
                    now: now
                )
                return true
            }

            let scheduleRelationship = pill.mutableSetValue(forKey: "scheduleVersions")
            let nextVersion = CoreDataScheduleSupport.nextVersion(in: scheduleRelationship)
            CoreDataScheduleSupport.deleteScheduleObjects(
                in: scheduleRelationship,
                onOrAfter: activeFrom,
                calendar: calendar,
                context: context
            )
            let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
            schedule.setValue(UUID(), forKey: "id")
            schedule.setValue(draft.id, forKey: "pillID")
            CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
            schedule.setValue(activeFrom, forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(nextVersion, forKey: "version")
            schedule.setValue(pill, forKey: "pill")

            try clearArchivedHistoryOnOrAfter(
                for: pill,
                pillID: draft.id,
                activeFrom: activeFrom,
                in: context
            )

            try writeArchivedGap(
                for: pill,
                pillID: draft.id,
                archivedAt: archivedAt,
                activeFrom: activeFrom,
                in: context
            )

            try applyRestoreDraftHistorySelection(
                for: pill,
                pillID: draft.id,
                draft: draft,
                activeFrom: activeFrom,
                today: today,
                in: context
            )

            let schedules = loadSchedules(for: pill, pillID: draft.id)
            let restoredDays = try autoFillRestoredTakenDays(
                for: pill,
                pillID: draft.id,
                activeFrom: activeFrom,
                endDate: draft.endDate,
                schedules: schedules,
                today: today,
                in: context
            )

            try context.save()

            let allIntakes = loadIntakes(for: pill, pillID: draft.id)
            let positiveDays = Set(
                allIntakes
                    .filter { $0.source.countsAsIntake }
                    .map { calendar.startOfDay(for: $0.localDate) }
            ).union(restoredDays)
            let skippedDays = Set(
                allIntakes
                    .filter { $0.source.countsAsSkipped }
                    .map { calendar.startOfDay(for: $0.localDate) }
            )
            syncTodayOverdueAnchorAfterEdit(
                pillID: draft.id,
                startDate: activeFrom,
                endDate: draft.endDate,
                schedules: schedules,
                reminderTime: draft.reminderEnabled ? draft.reminderTime : nil,
                positiveDays: positiveDays,
                skippedDays: skippedDays,
                now: now
            )
            return true
        }, missingResultError: PillRepositoryError.internalFailure)
    }

    func deletePill(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            context.delete(pill)
            try context.save()
        }
    }

    func setPillArchived(id: UUID, isArchived: Bool) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            guard pill.boolValue(forKey: "isArchived") != isArchived else { return }

            pill.setValue(isArchived, forKey: "isArchived")
            pill.setValue(isArchived ? clock.now() : nil, forKey: "archivedAt")
            pill.setValue(clock.now(), forKey: "updatedAt")
            try context.save()

            if isArchived {
                overdueAnchorStore.clearAnchorDay(for: .pill, id: id)
            }
        }
    }

    func markTakenToday(id: UUID) throws {
        try markPillTaken(id: id, on: clock.now())
    }

    func markPillTaken(id: UUID, on day: Date) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            guard !pill.boolValue(forKey: "isArchived") else { return }
            let today = calendar.startOfDay(for: day)
            guard
                let startDate = pill.dateValue(forKey: "startDate"),
                today >= calendar.startOfDay(for: startDate)
            else {
                return
            }
            let didChange = try upsertIntake(
                for: pill,
                pillID: id,
                on: today,
                source: .swipe,
                in: context,
                updateWhen: { $0 == .skipped }
            )

            guard didChange else { return }
            applyAutomaticArchiveIfNeeded(for: pill, pillID: id)
            try context.save()
            clearOverdueAnchorIfNeeded(for: id, on: today)
        }
    }

    func skipPillToday(id: UUID) throws {
        try skipPillDay(id: id, on: clock.now())
    }

    func skipPillDay(id: UUID, on day: Date) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            guard !pill.boolValue(forKey: "isArchived") else { return }
            let today = calendar.startOfDay(for: day)
            guard
                let startDate = pill.dateValue(forKey: "startDate"),
                today >= calendar.startOfDay(for: startDate)
            else {
                return
            }
            let didChange = try upsertIntake(
                for: pill,
                pillID: id,
                on: today,
                source: .skipped,
                in: context,
                updateWhen: { _ in false }
            )

            guard didChange else { return }
            applyAutomaticArchiveIfNeeded(for: pill, pillID: id)
            try context.save()
            clearOverdueAnchorIfNeeded(for: id, on: today)
        }
    }

    func clearPillDayStateToday(id: UUID) throws {
        try clearPillDayState(id: id, on: clock.now())
    }

    func clearPillDayState(id: UUID, on day: Date) throws {
        try repositoryContext.performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            guard !pill.boolValue(forKey: "isArchived") else { return }
            let today = calendar.startOfDay(for: day)
            let didChange = try clearIntake(for: pill, pillID: id, on: today, in: context)
            guard didChange else { return }
            try context.save()
            syncTodayOverdueAnchorAfterClearingDay(for: pill, pillID: id, clearedDay: today)
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

    private func fetchIntakes(for pillID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        try CoreDataFetchSupport.fetchHistoryObjects(
            entityName: "PillIntake",
            ownerKey: "pillID",
            ownerID: pillID,
            localDate: localDate,
            in: context
        )
    }

    private func fetchIntakes(
        for pillID: UUID,
        on localDates: Set<Date>,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        try CoreDataFetchSupport.fetchHistoryObjects(
            entityName: "PillIntake",
            ownerKey: "pillID",
            ownerID: pillID,
            localDates: localDates,
            in: context
        )
    }

    private func primaryHistoryObject(in objects: [NSManagedObject]) -> NSManagedObject? {
        CoreDataHistorySupport.primaryHistoryObject(in: objects)
    }

    private func bucketState(for source: PillCompletionSource) -> CoreDataHistoryBucketState {
        if source.countsAsSkipped {
            return .skipped
        }
        if source == .archived {
            return .archived
        }
        return .positive
    }

    private func bucketState(from sourceRaw: String) -> CoreDataHistoryBucketState? {
        PillCompletionSource(rawValue: sourceRaw).map(bucketState(for:))
    }

    private func pillSource(for state: CoreDataHistoryBucketState) -> PillCompletionSource {
        switch state {
        case .positive: return .manualEdit
        case .skipped: return .skipped
        case .archived: return .archived
        }
    }

    private func historySource(for pillID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> PillCompletionSource? {
        try CoreDataHistoryBucketSupport.state(
            ownerID: pillID,
            localDate: localDate,
            bucketEntityName: "PillHistoryBucket",
            ownerKey: "pillID",
            legacyEntityName: "PillIntake",
            rangeEntityName: "PillHistoryRange",
            legacySourceToState: bucketState(from:),
            in: context,
            calendar: calendar
        ).map(pillSource(for:))
    }

    private func explicitHistorySource(for pillID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> PillCompletionSource? {
        try CoreDataHistoryBucketSupport.state(
            ownerID: pillID,
            localDate: localDate,
            bucketEntityName: "PillHistoryBucket",
            ownerKey: "pillID",
            legacyEntityName: "PillIntake",
            legacySourceToState: bucketState(from:),
            in: context,
            calendar: calendar
        ).map(pillSource(for:))
    }

    private func historySources(
        pillID: UUID,
        on localDates: Set<Date>,
        in context: NSManagedObjectContext
    ) throws -> [Date: PillCompletionSource] {
        guard !localDates.isEmpty else { return [:] }

        let normalizedDates = Set(localDates.map { calendar.startOfDay(for: $0) })
        var sources: [Date: PillCompletionSource] = [:]
        for day in normalizedDates {
            if let source = try historySource(for: pillID, on: day, in: context) {
                sources[day] = source
            }
        }

        return sources
    }

    private func clearIntake(
        for pill: NSManagedObject,
        pillID: UUID,
        on localDate: Date,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        try CoreDataHistoryBucketSupport.clearState(
            owner: pill,
            ownerID: pillID,
            localDate: localDate,
            bucketEntityName: "PillHistoryBucket",
            ownerKey: "pillID",
            ownerRelationshipKey: "pill",
            legacyEntityName: "PillIntake",
            rangeEntityName: "PillHistoryRange",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
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
        guard let existingSource = try explicitHistorySource(for: pillID, on: normalizedDate, in: context) else {
            return try insertIntake(
                for: pill,
                pillID: pillID,
                on: normalizedDate,
                source: desiredSource,
                in: context
            )
        }

        guard shouldUpdate(existingSource), existingSource != desiredSource else {
            return false
        }

        return try insertIntake(
            for: pill,
            pillID: pillID,
            on: normalizedDate,
            source: desiredSource,
            in: context
        )
    }

    @discardableResult
    private func insertIntake(
        for pill: NSManagedObject,
        pillID: UUID,
        on localDate: Date,
        source: PillCompletionSource,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        try CoreDataHistoryBucketSupport.setState(
            owner: pill,
            ownerID: pillID,
            localDate: localDate,
            state: bucketState(for: source),
            bucketEntityName: "PillHistoryBucket",
            ownerKey: "pillID",
            ownerRelationshipKey: "pill",
            legacyEntityName: "PillIntake",
            rangeEntityName: "PillHistoryRange",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
    }

    private func clearArchivedHistoryOnOrAfter(
        for pill: NSManagedObject,
        pillID: UUID,
        activeFrom: Date,
        in context: NSManagedObjectContext
    ) throws {
        try CoreDataHistoryRangeSupport.removeStateOnOrAfter(
            owner: pill,
            ownerID: pillID,
            startDate: activeFrom,
            state: .archived,
            rangeEntityName: "PillHistoryRange",
            ownerKey: "pillID",
            ownerRelationshipKey: "pill",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
    }

    private func writeArchivedGap(
        for pill: NSManagedObject,
        pillID: UUID,
        archivedAt: Date,
        activeFrom: Date,
        in context: NSManagedObjectContext
    ) throws {
        let normalizedArchivedAt = calendar.startOfDay(for: archivedAt)
        let normalizedActiveFrom = calendar.startOfDay(for: activeFrom)
        guard let end = calendar.date(byAdding: .day, value: -1, to: normalizedActiveFrom), normalizedArchivedAt <= end else {
            return
        }

        try CoreDataHistoryRangeSupport.insertCalendarDayRanges(
            owner: pill,
            ownerID: pillID,
            startDate: normalizedArchivedAt,
            endDate: end,
            state: .archived,
            excludedDays: explicitHistoryDates(
                for: pill,
                pillID: pillID,
                from: normalizedArchivedAt,
                through: end
            ),
            rangeEntityName: "PillHistoryRange",
            ownerKey: "pillID",
            ownerRelationshipKey: "pill",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
    }

    private func applyRestoreDraftHistorySelection(
        for pill: NSManagedObject,
        pillID: UUID,
        draft: EditPillDraft,
        activeFrom: Date,
        today: Date,
        in context: NSManagedObjectContext
    ) throws {
        let editableSet = EditableHistoryWindow.dates(
            startDate: activeFrom,
            today: today,
            calendar: calendar
        )
        let normalizedSelection = EditableHistoryContract.normalizedSelection(
            positiveDays: draft.takenDays,
            skippedDays: draft.skippedDays,
            requiredFinalizedDays: [],
            pastDefaultSelection: .none,
            today: today,
            calendar: calendar
        )
        let existingByDay = try historySources(pillID: pillID, on: editableSet, in: context)

        for day in editableSet {
            let shouldBeTaken = normalizedSelection.positiveDays.contains(day)
            let shouldBeSkipped = normalizedSelection.skippedDays.contains(day)
            let existing = existingByDay[day]

            if shouldBeTaken {
                _ = try upsertIntake(
                    for: pill,
                    pillID: pillID,
                    on: day,
                    source: .manualEdit,
                    in: context,
                    updateWhen: { !$0.countsAsIntake }
                )
            } else if shouldBeSkipped {
                _ = try upsertIntake(
                    for: pill,
                    pillID: pillID,
                    on: day,
                    source: .skipped,
                    in: context,
                    updateWhen: { $0 != .skipped }
                )
            } else if existing != nil {
                _ = try clearIntake(for: pill, pillID: pillID, on: day, in: context)
            }
        }
    }

    private func autoFillRestoredTakenDays(
        for pill: NSManagedObject,
        pillID: UUID,
        activeFrom: Date,
        endDate: Date?,
        schedules: [PillScheduleVersion],
        today: Date,
        in context: NSManagedObjectContext
    ) throws -> Set<Date> {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today), activeFrom <= yesterday else {
            return []
        }

        var restoredDays = Set<Date>()
        for day in calendarDays(from: activeFrom, through: yesterday) where HistoryScheduleApplicability.isScheduled(
            on: day,
            startDate: activeFrom,
            endDate: endDate,
            from: schedules,
            calendar: calendar
        ) {
            let didChange = try upsertIntake(
                for: pill,
                pillID: pillID,
                on: day,
                source: .restore,
                in: context,
                updateWhen: { !$0.countsAsIntake && !$0.countsAsSkipped }
            )
            if didChange {
                restoredDays.insert(day)
            }
        }
        return restoredDays
    }

    private func restoreMinimumActiveFrom(archivedAt: Date, today: Date) -> Date {
        let editableStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        return max(calendar.startOfDay(for: archivedAt), calendar.startOfDay(for: editableStart))
    }

    private func deleteRelatedObjects(
        from owner: NSManagedObject,
        relationshipKey: String,
        in context: NSManagedObjectContext
    ) {
        let rows = (owner.mutableSetValue(forKey: relationshipKey).allObjects as? [NSManagedObject]) ?? []
        rows.forEach(context.delete)
    }

    private func calendarDays(from start: Date, through end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        while cursor <= normalizedEnd {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return days
    }

    private func explicitHistoryDates(
        for pill: NSManagedObject,
        pillID: UUID,
        from startDate: Date,
        through endDate: Date
    ) -> Set<Date> {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        let bucketDates = CoreDataHistoryBucketSupport.entries(
            from: pill,
            relationshipKey: "historyBuckets",
            ownerID: pillID,
            calendar: calendar
        ).map { calendar.startOfDay(for: $0.localDate) }
        let legacyDates = ((pill.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? [])
            .compactMap { $0.dateValue(forKey: "localDate") }
            .map { calendar.startOfDay(for: $0) }

        return Set((bucketDates + legacyDates).filter { $0 >= normalizedStart && $0 <= normalizedEnd })
    }

    private func applyAutomaticArchiveIfNeeded(
        for pill: NSManagedObject,
        pillID: UUID
    ) {
        guard let startDate = pill.dateValue(forKey: "startDate") else { return }
        let activeStartDate = ActiveCycleStartDate.value(
            for: pill,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        applyAutomaticArchiveIfNeeded(
            for: pill,
            pillID: pillID,
            startDate: activeStartDate,
            endDate: pill.dateValue(forKey: "endDate"),
            schedules: loadSchedules(for: pill, pillID: pillID),
            isFinalized: { day in
                guard
                    let context = pill.managedObjectContext,
                    let source = try? historySource(for: pillID, on: day, in: context)
                else {
                    return false
                }
                return source.countsAsIntake || source.countsAsSkipped
            }
        )
    }

    private func applyAutomaticArchiveIfNeeded(
        for pill: NSManagedObject,
        pillID: UUID,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        guard let startDate = pill.dateValue(forKey: "startDate") else { return }
        let activeStartDate = ActiveCycleStartDate.value(
            for: pill,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        applyAutomaticArchiveIfNeeded(
            for: pill,
            pillID: pillID,
            startDate: activeStartDate,
            endDate: pill.dateValue(forKey: "endDate"),
            schedules: loadSchedules(for: pill, pillID: pillID),
            positiveDays: positiveDays,
            skippedDays: skippedDays
        )
    }

    private func applyAutomaticArchiveIfNeeded(
        for pill: NSManagedObject,
        pillID: UUID,
        startDate: Date,
        endDate: Date?,
        schedules: [PillScheduleVersion],
        positiveDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        guard !pill.boolValue(forKey: "isArchived") else { return }
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })
        let finalizedDays = normalizedPositiveDays.union(normalizedSkippedDays)
        applyAutomaticArchiveIfNeeded(
            for: pill,
            pillID: pillID,
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            isFinalized: { finalizedDays.contains($0) }
        )
    }

    private func applyAutomaticArchiveIfNeeded(
        for pill: NSManagedObject,
        pillID: UUID,
        startDate: Date,
        endDate: Date?,
        schedules: [PillScheduleVersion],
        isFinalized: (Date) -> Bool
    ) {
        guard !pill.boolValue(forKey: "isArchived") else { return }
        guard ScheduleLifecycleSupport.shouldAutoArchive(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            isFinalized: isFinalized,
            calendar: calendar
        ) else {
            return
        }

        pill.setValue(true, forKey: "isArchived")
        pill.setValue(clock.now(), forKey: "archivedAt")
        pill.setValue(clock.now(), forKey: "updatedAt")
        overdueAnchorStore.clearAnchorDay(for: .pill, id: pillID)
    }

    private func resolvedScheduleEffectiveFrom(
        from draft: EditPillDraft,
        normalizedSelection: (positiveDays: Set<Date>, skippedDays: Set<Date>),
        now: Date
    ) -> Date {
        let normalizedToday = calendar.startOfDay(for: now)
        let activeStartDate = ActiveCycleStartDate.value(
            startDate: draft.startDate,
            activeFrom: draft.activeFrom,
            calendar: calendar
        )
        let minimumDate = max(normalizedToday, activeStartDate)
        let maximumDate = max(minimumDate, HistoryMonthWindow.endOfSecondNextMonth(from: normalizedToday, calendar: calendar))
        let selectedDate = draft.scheduleEffectiveFrom.map { calendar.startOfDay(for: $0) } ?? minimumDate
        let explicitDays = normalizedSelection.positiveDays.union(normalizedSelection.skippedDays)

        return ScheduleEffectiveFromResolver.resolve(
            scheduleRule: draft.scheduleRule,
            selectedDate: selectedDate,
            explicitDays: explicitDays,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
            calendar: calendar
        )?.resolvedDate ?? minimumDate
    }

    private func loadIntakes(for pillObject: NSManagedObject, pillID: UUID) -> [PillIntake] {
        let bucketIntakes = CoreDataHistoryBucketSupport.entries(
            from: pillObject,
            relationshipKey: "historyBuckets",
            ownerID: pillID,
            calendar: calendar
        ).map { entry in
            PillIntake(
                id: UUID(),
                pillID: pillID,
                localDate: entry.localDate,
                source: pillSource(for: entry.state),
                createdAt: entry.createdAt
            )
        }
        let legacyIntakes = CoreDataRelationshipLoadingSupport.compactHistoryModels(
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
        return mergedIntakes(bucketIntakes: bucketIntakes, legacyIntakes: legacyIntakes)
    }

    private func loadIntakes(
        for pillObject: NSManagedObject,
        pillID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [PillIntake]? {
        guard let bucketEntries = CoreDataHistoryBucketSupport.validatedEntries(
            from: pillObject,
            relationshipKey: "historyBuckets",
            area: "dashboard",
            invalidMessage: "Pill history bucket row is missing required fields or has overlapping masks.",
            report: &report,
            ownerID: pillID,
            calendar: calendar
        ) else {
            return nil
        }
        let bucketIntakes = bucketEntries.map { entry in
            PillIntake(
                id: UUID(),
                pillID: pillID,
                localDate: entry.localDate,
                source: pillSource(for: entry.state),
                createdAt: entry.createdAt
            )
        }
        let legacyIntakes = CoreDataRelationshipLoadingSupport.validatedHistoryModels(
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
        guard let legacyIntakes else {
            return nil
        }
        return mergedIntakes(bucketIntakes: bucketIntakes, legacyIntakes: legacyIntakes)
    }

    private func mergedIntakes(
        bucketIntakes: [PillIntake],
        legacyIntakes: [PillIntake]
    ) -> [PillIntake] {
        var byDay = Dictionary(uniqueKeysWithValues: bucketIntakes.map {
            (calendar.startOfDay(for: $0.localDate), $0)
        })
        for intake in legacyIntakes {
            let day = calendar.startOfDay(for: intake.localDate)
            guard byDay[day] == nil else { continue }
            byDay[day] = intake
        }
        return byDay.values.sorted { $0.localDate < $1.localDate }
    }

    private func initialCalendarMonthRange(startDate: Date, today: Date) -> ClosedRange<Date> {
        let displayMonth = HistoryMonthWindow.displayMonth(
            startDate: startDate,
            today: today,
            calendar: calendar
        )
        let displayMonthEnd = HistoryMonthWindow.endOfMonth(containing: displayMonth, calendar: calendar)
        return displayMonth ... displayMonthEnd
    }

    private func initialDetailsHistoryRange(startDate: Date, today: Date) -> ClosedRange<Date> {
        var lowerBound = initialCalendarMonthRange(startDate: startDate, today: today).lowerBound
        var upperBound = initialCalendarMonthRange(startDate: startDate, today: today).upperBound
        let editableDays = EditableHistoryWindow.dates(
            startDate: startDate,
            today: today,
            calendar: calendar
        )

        if let firstEditableDay = editableDays.min() {
            lowerBound = min(lowerBound, firstEditableDay)
        }
        if let lastEditableDay = editableDays.max() {
            upperBound = max(upperBound, lastEditableDay)
        }

        return lowerBound ... upperBound
    }

    private func loadSchedules(for pillObject: NSManagedObject, pillID: UUID) -> [PillScheduleVersion] {
        CoreDataRelationshipLoadingSupport.compactScheduleModels(
            from: pillObject,
            relationshipKey: "scheduleVersions"
        ) { scheduleID, rule, effectiveFrom, createdAt, version in
            PillScheduleVersion(
                id: scheduleID,
                pillID: pillID,
                rule: rule,
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
        ) { scheduleID, rule, effectiveFrom, createdAt, version in
            PillScheduleVersion(
                id: scheduleID,
                pillID: pillID,
                rule: rule,
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func makeDashboardProjection(
        from pillObject: NSManagedObject,
        now: Date,
        today: Date,
        report: inout IntegrityReportBuilder
    ) -> PillCardProjection? {
        guard
            let id = pillObject.uuidValue(forKey: "id"),
            let name = pillObject.stringValue(forKey: "name"),
            let dosage = pillObject.stringValue(forKey: "dosage"),
            let startDate = pillObject.dateValue(forKey: "startDate"),
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
            let historySnapshot = CoreDataHistoryBucketSupport.validatedSnapshot(
                from: pillObject,
                bucketRelationshipKey: "historyBuckets",
                rangeRelationshipKey: "historyRanges",
                rangeOwnerKey: "pillID",
                ownerID: id,
                legacyRelationshipKey: "intakes",
                area: "dashboard",
                invalidBucketMessage: "Pill history bucket row is missing required fields or has overlapping masks.",
                invalidRangeMessage: "Pill history range row is missing required fields or has invalid schedule/count.",
                invalidLegacyMessage: "Pill intake row is missing required fields or has invalid sourceRaw.",
                report: &report,
                legacySourceToState: bucketState(from:),
                calendar: calendar
            )
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
        let endDate = pillObject.dateValue(forKey: "endDate")
        let isArchived = pillObject.boolValue(forKey: "isArchived")
        let activeStartDate = ActiveCycleStartDate.value(
            for: pillObject,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        let hasStarted = activeStartDate <= today
        let todayState = historySnapshot.state(on: today, calendar: calendar)
        let isTakenToday = !isArchived && hasStarted && todayState == .positive
        let isSkippedToday = !isArchived && hasStarted && todayState == .skipped
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
        let reminderText = isArchived ? nil : validatedReminderTime?.formatted
        let isScheduledToday = !isArchived && HistoryScheduleApplicability.isScheduled(
            on: today,
            startDate: activeStartDate,
            endDate: endDate,
            from: schedules,
            calendar: calendar
        )
        let activeOverdueDay = isArchived ? nil : ScheduledOverdueState.activeOverdueDay(
            startDate: activeStartDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: validatedReminderTime,
            hasPositiveState: { historySnapshot.state(on: $0, calendar: calendar) == .positive },
            hasSkippedState: { historySnapshot.state(on: $0, calendar: calendar) == .skipped },
            now: now,
            calendar: calendar
        )
        let editableDays = EditableHistoryWindow.dates(startDate: activeStartDate, today: today, calendar: calendar)
        let editableSets = historySnapshot.daySets(
            from: editableDays.min() ?? today,
            through: editableDays.max() ?? today,
            calendar: calendar
        )

        return PillCardProjection(
            id: id,
            name: name,
            dosage: dosage,
            scheduleSummary: DashboardScheduleSummary.text(
                latestSchedule: latestSchedule,
                startDate: startDate,
                endDate: endDate,
                schedules: schedules,
                today: today,
                calendar: calendar
            ),
            totalTakenDays: historySnapshot.positiveCount,
            reminderText: reminderText,
            reminderHour: validatedReminderTime?.hour,
            reminderMinute: validatedReminderTime?.minute,
            isReminderScheduledToday: isScheduledToday,
            isScheduledToday: isScheduledToday,
            isTakenToday: isTakenToday,
            isSkippedToday: isSkippedToday,
            needsHistoryReview: !isArchived && needsHistoryReview(
                startDate: activeStartDate,
                endDate: endDate,
                schedules: schedules,
                positiveDays: editableSets.positiveDays,
                skippedDays: editableSets.skippedDays,
                today: today,
                activeOverdueDay: activeOverdueDay
            ),
            activeOverdueDay: activeOverdueDay,
            startsInFuture: !isArchived && !hasStarted,
            futureStartDate: isArchived || hasStarted ? nil : activeStartDate,
            isArchived: isArchived,
            sortOrder: Int(pillObject.int32Value(forKey: "sortOrder"))
        )
    }

    private func clearOverdueAnchorIfNeeded(for pillID: UUID, on day: Date) {
        guard
            let anchorDay = overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar),
            anchorDay == calendar.startOfDay(for: day)
        else {
            return
        }
        overdueAnchorStore.clearAnchorDay(for: .pill, id: pillID)
    }

    private func syncTodayOverdueAnchorAfterClearingDay(
        for pill: NSManagedObject,
        pillID: UUID,
        clearedDay: Date
    ) {
        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: clearedDay) == today else { return }

        func clearTodayAnchorIfPresent() {
            if overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar) == today {
                overdueAnchorStore.clearAnchorDay(for: .pill, id: pillID)
            }
        }

        guard let startDate = pill.dateValue(forKey: "startDate") else {
            clearTodayAnchorIfPresent()
            return
        }
        let activeStartDate = ActiveCycleStartDate.value(
            for: pill,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        guard activeStartDate <= today else {
            clearTodayAnchorIfPresent()
            return
        }

        let reminderEnabled = pill.boolValue(forKey: "reminderEnabled")
        var report = IntegrityReportBuilder()
        guard
            let reminderTime = ReminderValidation.validatedReminderTime(
                from: pill,
                reminderEnabled: reminderEnabled,
                area: "pill.clearDayState",
                report: &report
            )
        else {
            clearTodayAnchorIfPresent()
            return
        }

        guard
            let reminderDate = calendar.date(
                bySettingHour: reminderTime.hour,
                minute: reminderTime.minute,
                second: 0,
                of: today
            ),
            reminderDate <= now
        else {
            clearTodayAnchorIfPresent()
            return
        }

        let schedules = loadSchedules(for: pill, pillID: pillID)
        guard
            HistoryScheduleApplicability.isScheduled(
                on: today,
                startDate: activeStartDate,
                endDate: pill.dateValue(forKey: "endDate"),
                from: schedules,
                calendar: calendar
            )
        else {
            clearTodayAnchorIfPresent()
            return
        }

        overdueAnchorStore.setAnchorDay(today, for: .pill, id: pillID, calendar: calendar)
    }

    private func syncTodayOverdueAnchorAfterEdit(
        pillID: UUID,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [PillScheduleVersion],
        reminderTime: ReminderTime?,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        now: Date
    ) {
        let today = calendar.startOfDay(for: now)
        let isTodayDue = ScheduledOverdueState.isDueScheduledDay(
            today,
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            positiveDays: positiveDays,
            skippedDays: skippedDays,
            now: now,
            calendar: calendar
        )

        if isTodayDue {
            overdueAnchorStore.setAnchorDay(today, for: .pill, id: pillID, calendar: calendar)
        } else if overdueAnchorStore.anchorDay(for: .pill, id: pillID, calendar: calendar) == today {
            overdueAnchorStore.clearAnchorDay(for: .pill, id: pillID)
        }
    }

    private func needsHistoryReview(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [PillScheduleVersion],
        positiveDays: Set<Date>,
        skippedDays: Set<Date>,
        today: Date,
        activeOverdueDay: Date? = nil
    ) -> Bool {
        !EditableHistoryValidation.missingPastDays(
            editableDays: requiredPastScheduledDays(
                startDate: startDate,
                endDate: endDate,
                schedules: schedules,
                today: today,
                excluding: activeOverdueDay
            ),
            positiveDays: positiveDays,
            skippedDays: skippedDays,
            today: today,
            calendar: calendar
        ).isEmpty
    }

    private func requiredPastScheduledDays(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [PillScheduleVersion],
        today: Date,
        excluding excludedDay: Date? = nil
    ) -> Set<Date> {
        let editableDays = EditableHistoryWindow.dates(
            startDate: startDate,
            today: today,
            calendar: calendar
        )
        var requiredDays = HistoryScheduleApplicability.pastScheduledEditableDays(
            in: editableDays,
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            today: today,
            calendar: calendar
        )
        if let excludedDay {
            requiredDays.remove(calendar.startOfDay(for: excludedDay))
        }
        return requiredDays
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
