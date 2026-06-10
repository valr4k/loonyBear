import CoreData
import Foundation

enum HabitRepositoryError: LocalizedError {
    case internalFailure

    var errorDescription: String? {
        switch self {
        case .internalFailure:
            return "Something went wrong. Try again."
        }
    }
}

@MainActor
struct CoreDataHabitRepository: HabitRepository {
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

    func fetchDashboardHabits() throws -> [HabitCardProjection] {
        try PerformanceLog.measure("habit.dashboard.fetch") {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.sortDescriptors = [
            NSSortDescriptor(key: "typeRaw", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        let habits = try readContext.fetch(request)
        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        var report = IntegrityReportBuilder()
        var projections: [HabitCardProjection] = []

        for habitObject in habits {
            if let projection = makeDashboardProjection(
                from: habitObject,
                now: now,
                today: today,
                report: &report
            ) {
                projections.append(projection)
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: "fetchDashboardHabits")
        }

        return projections.sorted(by: habitDashboardSort)
        }
    }

    func fetchHabitDetails(id: UUID) throws -> HabitDetailsProjection? {
        try PerformanceLog.measure("habit.details.fetch", metadata: "id=\(id.uuidString)") {
        guard let habitObject = try fetchHabit(id: id, in: readContext) else {
            return nil
        }

        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        var report = IntegrityReportBuilder()
        guard
            let historySnapshot = CoreDataHistoryBucketSupport.validatedSnapshot(
                from: habitObject,
                bucketRelationshipKey: "historyBuckets",
                rangeRelationshipKey: "historyRanges",
                rangeOwnerKey: "habitID",
                ownerID: id,
                legacyRelationshipKey: "completions",
                area: "details",
                invalidBucketMessage: "Habit history bucket row is missing required fields or has overlapping masks.",
                invalidRangeMessage: "Habit history range row is missing required fields or has invalid schedule/count.",
                invalidLegacyMessage: "Habit completion row is missing required fields or has invalid sourceRaw.",
                report: &report,
                legacySourceToState: bucketState(from:),
                calendar: calendar
            ),
            let scheduleHistory = loadSchedules(for: habitObject, habitID: id, report: &report),
            let historyMode = habitHistoryMode(for: habitObject)
        else {
            report.append(
                area: "details",
                entityName: habitObject.entityName,
                object: habitObject,
                message: "Habit details failed because related rows are corrupted."
            )
            let error = report.makeError(operation: "fetchHabitDetails")
            ReliabilityLog.error("habit.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        let latestSchedule = scheduleHistory.sorted(by: CoreDataScheduleSupport.isNewerSchedule).first

        guard
            let typeRaw = habitObject.stringValue(forKey: "typeRaw"),
            let type = HabitType(rawValue: typeRaw),
            let name = habitObject.stringValue(forKey: "name"),
            let startDate = habitObject.dateValue(forKey: "startDate")
        else {
            report.append(
                area: "details",
                entityName: habitObject.entityName,
                object: habitObject,
                message: "Habit details row is missing required fields or has invalid typeRaw."
            )
            let error = report.makeError(operation: "fetchHabitDetails")
            ReliabilityLog.error("habit.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        let reminderEnabled = habitObject.boolValue(forKey: "reminderEnabled")
        let endDate = habitObject.dateValue(forKey: "endDate")
        let isArchived = habitObject.boolValue(forKey: "isArchived")
        let activeStartDate = ActiveCycleStartDate.value(
            for: habitObject,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        let displayRange = initialDetailsHistoryRange(startDate: activeStartDate, today: today)
        let historySets = historySnapshot.daySets(
            from: displayRange.lowerBound,
            through: displayRange.upperBound,
            calendar: calendar
        )
        let completedDays = historySets.positiveDays
        let skippedDays = historySets.skippedDays
        let archivedDays = historySets.archivedDays
        let reminderTime = ReminderValidation.validatedReminderTime(
            from: habitObject,
            reminderEnabled: reminderEnabled,
            area: "details",
            report: &report
        )
        guard !reminderEnabled || reminderTime != nil else {
            report.append(
                area: "details",
                entityName: habitObject.entityName,
                object: habitObject,
                message: "Habit details failed because reminder fields are corrupted."
            )
            let error = report.makeError(operation: "fetchHabitDetails")
            ReliabilityLog.error("habit.details integrity failure: \(error.localizedDescription)")
            throw error
        }

        let activeOverdueDay = isArchived ? nil : ScheduledOverdueState.activeOverdueDay(
            startDate: activeStartDate,
            endDate: endDate,
            schedules: scheduleHistory,
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
            schedules: scheduleHistory,
            calendar: calendar
        )

        return HabitDetailsProjection(
            id: id,
            type: type,
            name: name,
            startDate: startDate,
            activeFrom: habitObject.dateValue(forKey: "activeFrom"),
            endDate: endDate,
            historyMode: historyMode,
            scheduleSummary: latestSchedule?.rule.summary ?? "No days selected",
            scheduleDays: latestSchedule?.rule.weeklyDays ?? .daily,
            scheduleRule: latestSchedule?.rule ?? .weekly(.daily),
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            currentStreak: StreakEngine.currentStreak(
                earliestCompletionDate: historySnapshot.earliestPositiveDate,
                containsCompletion: { historySnapshot.state(on: $0, calendar: calendar) == .positive },
                containsSkippedCompletion: { historySnapshot.state(on: $0, calendar: calendar) == .skipped },
                schedules: scheduleHistory,
                startDate: startDate,
                today: today,
                seed: historySnapshot.positiveStreakSeed(calendar: calendar),
                calendar: calendar
            ),
            longestStreak: StreakEngine.longestStreak(
                earliestCompletionDate: historySnapshot.earliestPositiveDate,
                latestCompletionDate: historySnapshot.latestPositiveDate,
                containsCompletion: { historySnapshot.state(on: $0, calendar: calendar) == .positive },
                schedules: scheduleHistory,
                startDate: startDate,
                seed: historySnapshot.positiveStreakSeed(calendar: calendar),
                calendar: calendar
            ),
            totalCompletedDays: historySnapshot.positiveCount,
            completedDays: completedDays,
            skippedDays: skippedDays,
            archivedDays: archivedDays,
            historySnapshot: historySnapshot,
            scheduleHistory: scheduleHistory,
            scheduledDates: scheduledDates,
            needsHistoryReview: !isArchived && needsHistoryReview(
                startDate: activeStartDate,
                endDate: endDate,
                schedules: scheduleHistory,
                positiveDays: historySets.positiveDays,
                skippedDays: historySets.skippedDays,
                today: today,
                activeOverdueDay: activeOverdueDay
            ),
            requiredPastScheduledDays: isArchived ? [] : requiredPastScheduledDays(
                startDate: activeStartDate,
                endDate: endDate,
                schedules: scheduleHistory,
                today: today
            ),
            activeOverdueDay: activeOverdueDay,
            isArchived: isArchived,
            archivedAt: habitObject.dateValue(forKey: "archivedAt")
        )
        }
    }

    func reconcilePastDays(today: Date) throws -> Int { 0 }

    func createHabit(from draft: CreateHabitDraft) throws -> UUID {
        try PerformanceLog.measure("habit.create.save") {
        try repositoryContext.performWrite({ context in
            let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Habit")
            let totalHabits = try context.count(for: countRequest)
            guard totalHabits < 20 else {
                throw CreateHabitError.tooManyHabits
            }

            let sortOrderRequest = NSFetchRequest<NSDictionary>(entityName: "Habit")
            sortOrderRequest.resultType = .dictionaryResultType
            sortOrderRequest.propertiesToFetch = ["sortOrder"]
            sortOrderRequest.predicate = NSPredicate(format: "typeRaw == %@", draft.type.rawValue)
            sortOrderRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
            sortOrderRequest.fetchLimit = 1

            let maxSortOrder = try context.fetch(sortOrderRequest).first?["sortOrder"] as? Int32 ?? -1
            let now = clock.now()
            let habitID = UUID()

            let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
            habit.setValue(habitID, forKey: "id")
            habit.setValue(draft.type.rawValue, forKey: "typeRaw")
            habit.setValue(draft.trimmedName, forKey: "name")
            habit.setValue(maxSortOrder + 1, forKey: "sortOrder")
            habit.setValue(calendar.startOfDay(for: draft.startDate), forKey: "startDate")
            habit.setValue(draft.endDate.map { calendar.startOfDay(for: $0) }, forKey: "endDate")
            habit.setValue(false, forKey: "isArchived")
            habit.setValue(nil, forKey: "archivedAt")
            habit.setValue(
                draft.useScheduleForHistory ? HabitHistoryMode.scheduleBased.rawValue : HabitHistoryMode.everyDay.rawValue,
                forKey: "historyModeRaw"
            )
            habit.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            habit.setValue(now, forKey: "createdAt")
            habit.setValue(now, forKey: "updatedAt")
            habit.setValue(Int32(1), forKey: "version")

            let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
            schedule.setValue(UUID(), forKey: "id")
            schedule.setValue(habitID, forKey: "habitID")
            CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
            schedule.setValue(calendar.startOfDay(for: draft.startDate), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(habit, forKey: "habit")

            let initialCompletedPlan = CoreDataInitialHistoryPlanner.positiveHistoryPlan(
                startDate: draft.startDate,
                endDate: draft.endDate,
                scheduleRule: draft.scheduleRule,
                useScheduleForHistory: draft.useScheduleForHistory,
                today: now,
                calendar: calendar
            )
            try CoreDataHistoryRangeSupport.insertRange(
                owner: habit,
                ownerID: habitID,
                draft: initialCompletedPlan.coldRange,
                rangeEntityName: "HabitHistoryRange",
                ownerKey: "habitID",
                ownerRelationshipKey: "habit",
                in: context,
                now: now
            )
            try CoreDataHistoryBucketSupport.setStates(
                owner: habit,
                ownerID: habitID,
                plan: initialCompletedPlan.editableBucketPlan,
                state: .positive,
                bucketEntityName: "HabitHistoryBucket",
                ownerKey: "habitID",
                ownerRelationshipKey: "habit",
                legacyEntityName: "HabitCompletion",
                rangeEntityName: "HabitHistoryRange",
                in: context,
                calendar: calendar,
                now: now,
                shouldDeleteLegacyRows: false
            )

            applyAutomaticArchiveIfNeeded(
                for: habit,
                habitID: habitID,
                startDate: calendar.startOfDay(for: draft.startDate),
                endDate: draft.endDate,
                schedules: loadSchedules(for: habit, habitID: habitID),
                isFinalized: { initialCompletedPlan.contains($0, calendar: calendar) }
            )

            try context.save()
            return habitID
        }, missingResultError: HabitRepositoryError.internalFailure)
        }
    }

    func completeHabitToday(id: UUID) throws -> Bool {
        try completeHabitDay(id: id, on: clock.now())
    }

    func completeHabitDay(id: UUID, on day: Date) throws -> Bool {
        try repositoryContext.performWrite({ context in
            guard let habit = try fetchHabit(id: id, in: context) else { return false }
            guard !habit.boolValue(forKey: "isArchived") else { return false }

            let today = calendar.startOfDay(for: day)
            guard
                let startDate = habit.dateValue(forKey: "startDate"),
                today >= calendar.startOfDay(for: startDate)
            else {
                return false
            }
            let didChange = try upsertCompletion(
                for: habit,
                habitID: id,
                on: today,
                source: .swipe,
                in: context,
                updateWhen: { $0 == .skipped }
            )

            guard didChange else { return false }
            applyAutomaticArchiveIfNeeded(for: habit, habitID: id)
            try context.save()
            clearOverdueAnchorIfNeeded(for: id, on: today)
            return true
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

    func skipHabitToday(id: UUID) throws -> Bool {
        try skipHabitDay(id: id, on: clock.now())
    }

    func skipHabitDay(id: UUID, on day: Date) throws -> Bool {
        try repositoryContext.performWrite({ context in
            guard let habit = try fetchHabit(id: id, in: context) else { return false }
            guard !habit.boolValue(forKey: "isArchived") else { return false }

            let today = calendar.startOfDay(for: day)
            guard
                let startDate = habit.dateValue(forKey: "startDate"),
                today >= calendar.startOfDay(for: startDate)
            else {
                return false
            }
            let didChange = try upsertCompletion(
                for: habit,
                habitID: id,
                on: today,
                source: .skipped,
                in: context,
                updateWhen: { _ in false }
            )

            guard didChange else { return false }
            applyAutomaticArchiveIfNeeded(for: habit, habitID: id)
            try context.save()
            clearOverdueAnchorIfNeeded(for: id, on: today)
            return true
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

    func clearHabitDayStateToday(id: UUID) throws -> Bool {
        try clearHabitDayState(id: id, on: clock.now())
    }

    func clearHabitDayState(id: UUID, on day: Date) throws -> Bool {
        try repositoryContext.performWrite({ context in
            guard let habit = try fetchHabit(id: id, in: context) else { return false }
            guard !habit.boolValue(forKey: "isArchived") else { return false }
            let today = calendar.startOfDay(for: day)
            let didChange = try clearCompletion(for: habit, habitID: id, on: today, in: context)
            guard didChange else { return false }
            try context.save()
            syncTodayOverdueAnchorAfterClearingDay(for: habit, habitID: id, clearedDay: today)
            return true
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

    func deleteHabit(id: UUID) throws -> Bool {
        try repositoryContext.performWrite({ context in
            guard let habit = try fetchHabit(id: id, in: context) else { return false }

            context.delete(habit)
            try context.save()
            return true
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

    func setHabitArchived(id: UUID, isArchived: Bool) throws -> Bool {
        try repositoryContext.performWrite({ context in
            guard let habit = try fetchHabit(id: id, in: context) else { return false }
            guard habit.boolValue(forKey: "isArchived") != isArchived else { return false }

            habit.setValue(isArchived, forKey: "isArchived")
            habit.setValue(isArchived ? clock.now() : nil, forKey: "archivedAt")
            habit.setValue(clock.now(), forKey: "updatedAt")
            try context.save()

            if isArchived {
                overdueAnchorStore.clearAnchorDay(for: .habit, id: id)
            }
            return true
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

    func updateHabit(from draft: EditHabitDraft) throws {
        try PerformanceLog.measure("habit.update.save", metadata: "id=\(draft.id.uuidString)") {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: draft.id, in: context) else { return }
            let wasArchived = habit.boolValue(forKey: "isArchived")

            habit.setValue(draft.trimmedName, forKey: "name")
            habit.setValue(draft.endDate.map { calendar.startOfDay(for: $0) }, forKey: "endDate")
            habit.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            let now = clock.now()
            let normalizedToday = calendar.startOfDay(for: now)
            let activeStartDate = ActiveCycleStartDate.value(
                startDate: draft.startDate,
                activeFrom: draft.activeFrom,
                calendar: calendar
            )
            let normalizedSelection = EditableHistoryContract.normalizedSelection(
                positiveDays: draft.completedDays,
                skippedDays: draft.skippedDays,
                requiredFinalizedDays: [],
                pastDefaultSelection: .none,
                today: normalizedToday,
                calendar: calendar
            )
            habit.setValue(now, forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: habit)
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
                let scheduleRelationship = habit.mutableSetValue(forKey: "scheduleVersions")
                let nextVersion = CoreDataScheduleSupport.nextVersion(in: scheduleRelationship)
                CoreDataScheduleSupport.deleteScheduleObjects(
                    in: scheduleRelationship,
                    onOrAfter: effectiveFrom,
                    calendar: calendar,
                    context: context
                )
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "habitID")
                CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
                schedule.setValue(effectiveFrom, forKey: "effectiveFrom")
                schedule.setValue(now, forKey: "createdAt")
                schedule.setValue(nextVersion, forKey: "version")
                schedule.setValue(habit, forKey: "habit")
            }
            if wasArchived, let activeFrom = savedEffectiveFrom ?? requestedEffectiveFrom {
                habit.setValue(activeFrom, forKey: "activeFrom")
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
                schedules: loadSchedules(for: habit, habitID: draft.id),
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
                throw EditableHistoryValidationError.missingHabitPastDays(missingPastDays)
            }

            let existingByDay = try historySources(habitID: draft.id, on: editableSet, in: context)

            for day in editableSet {
                let shouldBeCompleted = normalizedSelection.positiveDays.contains(day)
                let shouldBeSkipped = normalizedSelection.skippedDays.contains(day)
                let existing = existingByDay[day]

                if shouldBeCompleted {
                    _ = try upsertCompletion(
                        for: habit,
                        habitID: draft.id,
                        on: day,
                        source: .manualEdit,
                        in: context,
                        updateWhen: { !$0.countsAsCompletion }
                    )
                } else if shouldBeSkipped {
                    _ = try upsertCompletion(
                        for: habit,
                        habitID: draft.id,
                        on: day,
                        source: .skipped,
                        in: context,
                        updateWhen: { $0 != .skipped }
                    )
                } else if existing != nil {
                    _ = try clearCompletion(for: habit, habitID: draft.id, on: day, in: context)
                }
            }

            applyAutomaticArchiveIfNeeded(
                for: habit,
                habitID: draft.id,
                positiveDays: normalizedSelection.positiveDays,
                skippedDays: normalizedSelection.skippedDays
            )

            try context.save()
            if !wasArchived {
                syncTodayOverdueAnchorAfterEdit(
                    habitID: draft.id,
                    startDate: activeStartDate,
                    endDate: draft.endDate,
                    schedules: loadSchedules(for: habit, habitID: draft.id),
                    reminderTime: draft.reminderEnabled ? draft.reminderTime : nil,
                    positiveDays: normalizedSelection.positiveDays,
                    skippedDays: normalizedSelection.skippedDays,
                    now: now
                )
            }
        }
        }
    }

    func restoreHabit(from draft: EditHabitDraft, historyMode: RestoreHistoryMode) throws -> Bool {
        try PerformanceLog.measure(
            "habit.restore.save",
            metadata: "id=\(draft.id.uuidString) historyMode=\(historyMode)"
        ) {
        try repositoryContext.performWrite({ context in
            guard let habit = try fetchHabit(id: draft.id, in: context) else { return false }
            guard habit.boolValue(forKey: "isArchived") else { return false }

            let now = clock.now()
            let today = calendar.startOfDay(for: now)
            let archivedAt = habit.dateValue(forKey: "archivedAt").map { calendar.startOfDay(for: $0) } ?? today
            let activeFrom = calendar.startOfDay(for: draft.restoreActiveFrom ?? today)
            let minimumActiveFrom = restoreMinimumActiveFrom(archivedAt: archivedAt, today: today)
            guard activeFrom >= minimumActiveFrom else {
                throw HabitRepositoryError.internalFailure
            }

            habit.setValue(draft.trimmedName, forKey: "name")
            habit.setValue(draft.endDate.map { calendar.startOfDay(for: $0) }, forKey: "endDate")
            habit.setValue(false, forKey: "isArchived")
            habit.setValue(nil, forKey: "archivedAt")
            habit.setValue(activeFrom, forKey: "activeFrom")
            habit.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            habit.setValue(now, forKey: "updatedAt")

            if historyMode == .startFresh {
                habit.setValue(activeFrom, forKey: "startDate")
                deleteRelatedObjects(from: habit, relationshipKey: "historyBuckets", in: context)
                deleteRelatedObjects(from: habit, relationshipKey: "historyRanges", in: context)
                deleteRelatedObjects(from: habit, relationshipKey: "completions", in: context)
                deleteRelatedObjects(from: habit, relationshipKey: "scheduleVersions", in: context)

                let scheduleID = UUID()
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
                schedule.setValue(scheduleID, forKey: "id")
                schedule.setValue(draft.id, forKey: "habitID")
                CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
                schedule.setValue(activeFrom, forKey: "effectiveFrom")
                schedule.setValue(now, forKey: "createdAt")
                schedule.setValue(Int32(1), forKey: "version")
                schedule.setValue(habit, forKey: "habit")

                try context.save()

                syncTodayOverdueAnchorAfterEdit(
                    habitID: draft.id,
                    startDate: activeFrom,
                    endDate: draft.endDate,
                    schedules: [
                        HabitScheduleVersion(
                            id: scheduleID,
                            habitID: draft.id,
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

            let scheduleRelationship = habit.mutableSetValue(forKey: "scheduleVersions")
            let nextVersion = CoreDataScheduleSupport.nextVersion(in: scheduleRelationship)
            CoreDataScheduleSupport.deleteScheduleObjects(
                in: scheduleRelationship,
                onOrAfter: activeFrom,
                calendar: calendar,
                context: context
            )
            let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
            schedule.setValue(UUID(), forKey: "id")
            schedule.setValue(draft.id, forKey: "habitID")
            CoreDataScheduleSupport.apply(draft.scheduleRule, to: schedule)
            schedule.setValue(activeFrom, forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(nextVersion, forKey: "version")
            schedule.setValue(habit, forKey: "habit")

            try clearArchivedHistoryOnOrAfter(
                for: habit,
                habitID: draft.id,
                activeFrom: activeFrom,
                in: context
            )

            try writeArchivedGap(
                for: habit,
                habitID: draft.id,
                archivedAt: archivedAt,
                activeFrom: activeFrom,
                in: context
            )

            try applyRestoreDraftHistorySelection(
                for: habit,
                habitID: draft.id,
                draft: draft,
                activeFrom: activeFrom,
                today: today,
                in: context
            )

            let schedules = loadSchedules(for: habit, habitID: draft.id)
            let restoredDays = try autoFillRestoredCompletedDays(
                for: habit,
                habitID: draft.id,
                activeFrom: activeFrom,
                endDate: draft.endDate,
                schedules: schedules,
                today: today,
                in: context
            )

            try context.save()

            let allCompletions = loadCompletions(for: habit, habitID: draft.id)
            let positiveDays = Set(
                allCompletions
                    .filter { $0.source.countsAsCompletion }
                    .map { calendar.startOfDay(for: $0.localDate) }
            ).union(restoredDays)
            let skippedDays = Set(
                allCompletions
                    .filter { $0.source.countsAsSkipped }
                    .map { calendar.startOfDay(for: $0.localDate) }
            )
            syncTodayOverdueAnchorAfterEdit(
                habitID: draft.id,
                startDate: activeFrom,
                endDate: draft.endDate,
                schedules: schedules,
                reminderTime: draft.reminderEnabled ? draft.reminderTime : nil,
                positiveDays: positiveDays,
                skippedDays: skippedDays,
                now: now
            )
            return true
        }, missingResultError: HabitRepositoryError.internalFailure)
        }
    }

    private func fetchHabit(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        try CoreDataFetchSupport.fetchObject(
            entityName: "Habit",
            id: id,
            in: context
        )
    }

    private func fetchCompletions(for habitID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        try CoreDataFetchSupport.fetchHistoryObjects(
            entityName: "HabitCompletion",
            ownerKey: "habitID",
            ownerID: habitID,
            localDate: localDate,
            in: context
        )
    }

    private func fetchCompletions(
        for habitID: UUID,
        on localDates: Set<Date>,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        try CoreDataFetchSupport.fetchHistoryObjects(
            entityName: "HabitCompletion",
            ownerKey: "habitID",
            ownerID: habitID,
            localDates: localDates,
            in: context
        )
    }

    private func primaryHistoryObject(in objects: [NSManagedObject]) -> NSManagedObject? {
        CoreDataHistorySupport.primaryHistoryObject(in: objects)
    }

    private func bucketState(for source: CompletionSource) -> CoreDataHistoryBucketState {
        if source.countsAsSkipped {
            return .skipped
        }
        if source == .archived {
            return .archived
        }
        return .positive
    }

    private func bucketState(from sourceRaw: String) -> CoreDataHistoryBucketState? {
        CompletionSource(rawValue: sourceRaw).map(bucketState(for:))
    }

    private func completionSource(for state: CoreDataHistoryBucketState) -> CompletionSource {
        switch state {
        case .positive: return .manualEdit
        case .skipped: return .skipped
        case .archived: return .archived
        }
    }

    private func historySource(for habitID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> CompletionSource? {
        try CoreDataHistoryBucketSupport.state(
            ownerID: habitID,
            localDate: localDate,
            bucketEntityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            legacyEntityName: "HabitCompletion",
            rangeEntityName: "HabitHistoryRange",
            legacySourceToState: bucketState(from:),
            in: context,
            calendar: calendar
        ).map(completionSource(for:))
    }

    private func explicitHistorySource(for habitID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> CompletionSource? {
        try CoreDataHistoryBucketSupport.state(
            ownerID: habitID,
            localDate: localDate,
            bucketEntityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            legacyEntityName: "HabitCompletion",
            legacySourceToState: bucketState(from:),
            in: context,
            calendar: calendar
        ).map(completionSource(for:))
    }

    private func historySources(
        habitID: UUID,
        on localDates: Set<Date>,
        in context: NSManagedObjectContext
    ) throws -> [Date: CompletionSource] {
        guard !localDates.isEmpty else { return [:] }

        let normalizedDates = Set(localDates.map { calendar.startOfDay(for: $0) })
        var sources: [Date: CompletionSource] = [:]
        for day in normalizedDates {
            if let source = try historySource(for: habitID, on: day, in: context) {
                sources[day] = source
            }
        }

        return sources
    }

    private func clearCompletion(
        for habit: NSManagedObject,
        habitID: UUID,
        on localDate: Date,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        try CoreDataHistoryBucketSupport.clearState(
            owner: habit,
            ownerID: habitID,
            localDate: localDate,
            bucketEntityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            ownerRelationshipKey: "habit",
            legacyEntityName: "HabitCompletion",
            rangeEntityName: "HabitHistoryRange",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
    }

    private func upsertCompletion(
        for habit: NSManagedObject,
        habitID: UUID,
        on localDate: Date,
        source desiredSource: CompletionSource,
        in context: NSManagedObjectContext,
        updateWhen shouldUpdate: (CompletionSource) -> Bool
    ) throws -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        guard let existingSource = try explicitHistorySource(for: habitID, on: normalizedDate, in: context) else {
            return try insertCompletion(
                for: habit,
                habitID: habitID,
                on: normalizedDate,
                source: desiredSource,
                in: context
            )
        }

        guard shouldUpdate(existingSource), existingSource != desiredSource else {
            return false
        }

        return try insertCompletion(
            for: habit,
            habitID: habitID,
            on: normalizedDate,
            source: desiredSource,
            in: context
        )
    }

    @discardableResult
    private func insertCompletion(
        for habit: NSManagedObject,
        habitID: UUID,
        on localDate: Date,
        source: CompletionSource,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        try CoreDataHistoryBucketSupport.setState(
            owner: habit,
            ownerID: habitID,
            localDate: localDate,
            state: bucketState(for: source),
            bucketEntityName: "HabitHistoryBucket",
            ownerKey: "habitID",
            ownerRelationshipKey: "habit",
            legacyEntityName: "HabitCompletion",
            rangeEntityName: "HabitHistoryRange",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
    }

    private func clearArchivedHistoryOnOrAfter(
        for habit: NSManagedObject,
        habitID: UUID,
        activeFrom: Date,
        in context: NSManagedObjectContext
    ) throws {
        try CoreDataHistoryRangeSupport.removeStateOnOrAfter(
            owner: habit,
            ownerID: habitID,
            startDate: activeFrom,
            state: .archived,
            rangeEntityName: "HabitHistoryRange",
            ownerKey: "habitID",
            ownerRelationshipKey: "habit",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
    }

    private func writeArchivedGap(
        for habit: NSManagedObject,
        habitID: UUID,
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
            owner: habit,
            ownerID: habitID,
            startDate: normalizedArchivedAt,
            endDate: end,
            state: .archived,
            excludedDays: explicitHistoryDates(
                for: habit,
                habitID: habitID,
                from: normalizedArchivedAt,
                through: end
            ),
            rangeEntityName: "HabitHistoryRange",
            ownerKey: "habitID",
            ownerRelationshipKey: "habit",
            in: context,
            calendar: calendar,
            now: clock.now()
        )
    }

    private func applyRestoreDraftHistorySelection(
        for habit: NSManagedObject,
        habitID: UUID,
        draft: EditHabitDraft,
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
            positiveDays: draft.completedDays,
            skippedDays: draft.skippedDays,
            requiredFinalizedDays: [],
            pastDefaultSelection: .none,
            today: today,
            calendar: calendar
        )
        let existingByDay = try historySources(habitID: habitID, on: editableSet, in: context)

        for day in editableSet {
            let shouldBeCompleted = normalizedSelection.positiveDays.contains(day)
            let shouldBeSkipped = normalizedSelection.skippedDays.contains(day)
            let existing = existingByDay[day]

            if shouldBeCompleted {
                _ = try upsertCompletion(
                    for: habit,
                    habitID: habitID,
                    on: day,
                    source: .manualEdit,
                    in: context,
                    updateWhen: { !$0.countsAsCompletion }
                )
            } else if shouldBeSkipped {
                _ = try upsertCompletion(
                    for: habit,
                    habitID: habitID,
                    on: day,
                    source: .skipped,
                    in: context,
                    updateWhen: { $0 != .skipped }
                )
            } else if existing != nil {
                _ = try clearCompletion(for: habit, habitID: habitID, on: day, in: context)
            }
        }
    }

    private func autoFillRestoredCompletedDays(
        for habit: NSManagedObject,
        habitID: UUID,
        activeFrom: Date,
        endDate: Date?,
        schedules: [HabitScheduleVersion],
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
            let didChange = try upsertCompletion(
                for: habit,
                habitID: habitID,
                on: day,
                source: .restore,
                in: context,
                updateWhen: { !$0.countsAsCompletion && !$0.countsAsSkipped }
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
        for habit: NSManagedObject,
        habitID: UUID,
        from startDate: Date,
        through endDate: Date
    ) -> Set<Date> {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        let bucketDates = CoreDataHistoryBucketSupport.entries(
            from: habit,
            relationshipKey: "historyBuckets",
            ownerID: habitID,
            calendar: calendar
        ).map { calendar.startOfDay(for: $0.localDate) }
        let legacyDates = ((habit.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? [])
            .compactMap { $0.dateValue(forKey: "localDate") }
            .map { calendar.startOfDay(for: $0) }

        return Set((bucketDates + legacyDates).filter { $0 >= normalizedStart && $0 <= normalizedEnd })
    }

    private func applyAutomaticArchiveIfNeeded(
        for habit: NSManagedObject,
        habitID: UUID
    ) {
        guard let startDate = habit.dateValue(forKey: "startDate") else { return }
        let activeStartDate = ActiveCycleStartDate.value(
            for: habit,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        applyAutomaticArchiveIfNeeded(
            for: habit,
            habitID: habitID,
            startDate: activeStartDate,
            endDate: habit.dateValue(forKey: "endDate"),
            schedules: loadSchedules(for: habit, habitID: habitID),
            isFinalized: { day in
                guard
                    let context = habit.managedObjectContext,
                    let source = try? historySource(for: habitID, on: day, in: context)
                else {
                    return false
                }
                return source.countsAsCompletion || source.countsAsSkipped
            }
        )
    }

    private func applyAutomaticArchiveIfNeeded(
        for habit: NSManagedObject,
        habitID: UUID,
        positiveDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        guard let startDate = habit.dateValue(forKey: "startDate") else { return }
        let activeStartDate = ActiveCycleStartDate.value(
            for: habit,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        applyAutomaticArchiveIfNeeded(
            for: habit,
            habitID: habitID,
            startDate: activeStartDate,
            endDate: habit.dateValue(forKey: "endDate"),
            schedules: loadSchedules(for: habit, habitID: habitID),
            positiveDays: positiveDays,
            skippedDays: skippedDays
        )
    }

    private func applyAutomaticArchiveIfNeeded(
        for habit: NSManagedObject,
        habitID: UUID,
        startDate: Date,
        endDate: Date?,
        schedules: [HabitScheduleVersion],
        positiveDays: Set<Date>,
        skippedDays: Set<Date>
    ) {
        guard !habit.boolValue(forKey: "isArchived") else { return }
        let normalizedPositiveDays = Set(positiveDays.map { calendar.startOfDay(for: $0) })
        let normalizedSkippedDays = Set(skippedDays.map { calendar.startOfDay(for: $0) })
        let finalizedDays = normalizedPositiveDays.union(normalizedSkippedDays)
        applyAutomaticArchiveIfNeeded(
            for: habit,
            habitID: habitID,
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            isFinalized: { finalizedDays.contains($0) }
        )
    }

    private func applyAutomaticArchiveIfNeeded(
        for habit: NSManagedObject,
        habitID: UUID,
        startDate: Date,
        endDate: Date?,
        schedules: [HabitScheduleVersion],
        isFinalized: (Date) -> Bool
    ) {
        guard !habit.boolValue(forKey: "isArchived") else { return }
        guard ScheduleLifecycleSupport.shouldAutoArchive(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            isFinalized: isFinalized,
            calendar: calendar
        ) else {
            return
        }

        habit.setValue(true, forKey: "isArchived")
        habit.setValue(clock.now(), forKey: "archivedAt")
        habit.setValue(clock.now(), forKey: "updatedAt")
        overdueAnchorStore.clearAnchorDay(for: .habit, id: habitID)
    }

    private func resolvedScheduleEffectiveFrom(
        from draft: EditHabitDraft,
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

    private func loadCompletions(for habitObject: NSManagedObject, habitID: UUID) -> [HabitCompletion] {
        let bucketCompletions = CoreDataHistoryBucketSupport.entries(
            from: habitObject,
            relationshipKey: "historyBuckets",
            ownerID: habitID,
            calendar: calendar
        ).map { entry in
            HabitCompletion(
                id: UUID(),
                habitID: habitID,
                localDate: entry.localDate,
                source: completionSource(for: entry.state),
                createdAt: entry.createdAt
            )
        }
        let legacyCompletions = CoreDataRelationshipLoadingSupport.compactHistoryModels(
            from: habitObject,
            relationshipKey: "completions"
        ) { completionID, localDate, source, createdAt in
            HabitCompletion(
                id: completionID,
                habitID: habitID,
                localDate: localDate,
                source: source,
                createdAt: createdAt
            )
        }
        return mergedCompletions(bucketCompletions: bucketCompletions, legacyCompletions: legacyCompletions)
    }

    private func loadCompletions(
        for habitObject: NSManagedObject,
        habitID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [HabitCompletion]? {
        guard let bucketEntries = CoreDataHistoryBucketSupport.validatedEntries(
            from: habitObject,
            relationshipKey: "historyBuckets",
            area: "dashboard",
            invalidMessage: "Habit history bucket row is missing required fields or has overlapping masks.",
            report: &report,
            ownerID: habitID,
            calendar: calendar
        ) else {
            return nil
        }
        let bucketCompletions = bucketEntries.map { entry in
            HabitCompletion(
                id: UUID(),
                habitID: habitID,
                localDate: entry.localDate,
                source: completionSource(for: entry.state),
                createdAt: entry.createdAt
            )
        }
        let legacyCompletions = CoreDataRelationshipLoadingSupport.validatedHistoryModels(
            from: habitObject,
            relationshipKey: "completions",
            area: "dashboard",
            invalidMessage: "Habit completion row is missing required fields or has invalid sourceRaw.",
            report: &report
        ) { completionID, localDate, source, createdAt in
            HabitCompletion(
                id: completionID,
                habitID: habitID,
                localDate: localDate,
                source: source,
                createdAt: createdAt
            )
        }
        guard let legacyCompletions else {
            return nil
        }
        return mergedCompletions(bucketCompletions: bucketCompletions, legacyCompletions: legacyCompletions)
    }

    private func mergedCompletions(
        bucketCompletions: [HabitCompletion],
        legacyCompletions: [HabitCompletion]
    ) -> [HabitCompletion] {
        var byDay = Dictionary(uniqueKeysWithValues: bucketCompletions.map {
            (calendar.startOfDay(for: $0.localDate), $0)
        })
        for completion in legacyCompletions {
            let day = calendar.startOfDay(for: completion.localDate)
            guard byDay[day] == nil else { continue }
            byDay[day] = completion
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

    private func loadSchedules(for habitObject: NSManagedObject, habitID: UUID) -> [HabitScheduleVersion] {
        CoreDataRelationshipLoadingSupport.compactScheduleModels(
            from: habitObject,
            relationshipKey: "scheduleVersions"
        ) { scheduleID, rule, effectiveFrom, createdAt, version in
            HabitScheduleVersion(
                id: scheduleID,
                habitID: habitID,
                rule: rule,
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func loadSchedules(
        for habitObject: NSManagedObject,
        habitID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [HabitScheduleVersion]? {
        CoreDataRelationshipLoadingSupport.validatedScheduleModels(
            from: habitObject,
            relationshipKey: "scheduleVersions",
            area: "dashboard",
            missingFieldsMessage: "Habit schedule row is missing required fields.",
            invalidMaskMessage: "Habit schedule row contains invalid weekdayMask.",
            report: &report
        ) { scheduleID, rule, effectiveFrom, createdAt, version in
            HabitScheduleVersion(
                id: scheduleID,
                habitID: habitID,
                rule: rule,
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func makeDashboardProjection(
        from habitObject: NSManagedObject,
        now: Date,
        today: Date,
        report: inout IntegrityReportBuilder
    ) -> HabitCardProjection? {
        guard
            let id = habitObject.uuidValue(forKey: "id"),
            let typeRaw = habitObject.stringValue(forKey: "typeRaw"),
            let type = HabitType(rawValue: typeRaw),
            let name = habitObject.stringValue(forKey: "name"),
            let startDate = habitObject.dateValue(forKey: "startDate")
        else {
            report.append(
                area: "dashboard",
                entityName: habitObject.entityName,
                object: habitObject,
                message: "Habit row is missing required fields or has invalid typeRaw."
            )
            return nil
        }

        guard
            let historySnapshot = CoreDataHistoryBucketSupport.validatedSnapshot(
                from: habitObject,
                bucketRelationshipKey: "historyBuckets",
                rangeRelationshipKey: "historyRanges",
                rangeOwnerKey: "habitID",
                ownerID: id,
                legacyRelationshipKey: "completions",
                area: "dashboard",
                invalidBucketMessage: "Habit history bucket row is missing required fields or has overlapping masks.",
                invalidRangeMessage: "Habit history range row is missing required fields or has invalid schedule/count.",
                invalidLegacyMessage: "Habit completion row is missing required fields or has invalid sourceRaw.",
                report: &report,
                legacySourceToState: bucketState(from:),
                calendar: calendar
            ),
            let scheduleHistory = loadSchedules(for: habitObject, habitID: id, report: &report)
        else {
            report.append(
                area: "dashboard",
                entityName: habitObject.entityName,
                object: habitObject,
                message: "Habit dashboard projection was skipped because related rows are corrupted."
            )
            return nil
        }

        let sortOrder = Int(habitObject.int32Value(forKey: "sortOrder"))
        let endDate = habitObject.dateValue(forKey: "endDate")
        let isArchived = habitObject.boolValue(forKey: "isArchived")
        let latestSchedule = scheduleHistory.sorted(by: CoreDataScheduleSupport.isNewerSchedule).first
        let activeStartDate = ActiveCycleStartDate.value(
            for: habitObject,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        let hasStarted = activeStartDate <= today
        let todayState = historySnapshot.state(on: today, calendar: calendar)
        let isCompletedToday = !isArchived && hasStarted && todayState == .positive
        let isSkippedToday = !isArchived && hasStarted && todayState == .skipped
        let reminderEnabled = habitObject.boolValue(forKey: "reminderEnabled")
        let validatedReminderTime = ReminderValidation.validatedReminderTime(
            from: habitObject,
            reminderEnabled: reminderEnabled,
            area: "dashboard",
            report: &report
        )
        guard !reminderEnabled || validatedReminderTime != nil else {
            report.append(
                area: "dashboard",
                entityName: habitObject.entityName,
                object: habitObject,
                message: "Habit dashboard projection was skipped because reminder fields are corrupted."
            )
            return nil
        }
        let scheduledToday = !isArchived && HistoryScheduleApplicability.isScheduled(
            on: today,
            startDate: activeStartDate,
            endDate: endDate,
            from: scheduleHistory,
            calendar: calendar
        )
        let reminderText: String?
        let displayReminderHour: Int?
        let displayReminderMinute: Int?

        if !isArchived, let validatedReminderTime {
            reminderText = validatedReminderTime.formatted
            displayReminderHour = validatedReminderTime.hour
            displayReminderMinute = validatedReminderTime.minute
        } else {
            reminderText = nil
            displayReminderHour = nil
            displayReminderMinute = nil
        }

        let streak = StreakEngine.currentStreak(
            earliestCompletionDate: historySnapshot.earliestPositiveDate,
            containsCompletion: { historySnapshot.state(on: $0, calendar: calendar) == .positive },
            containsSkippedCompletion: { historySnapshot.state(on: $0, calendar: calendar) == .skipped },
            schedules: scheduleHistory,
            startDate: startDate,
            today: today,
            seed: historySnapshot.positiveStreakSeed(calendar: calendar),
            calendar: calendar
        )
        let activeOverdueDay = isArchived ? nil : ScheduledOverdueState.activeOverdueDay(
            startDate: activeStartDate,
            endDate: endDate,
            schedules: scheduleHistory,
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

        return HabitCardProjection(
            id: id,
            type: type,
            name: name,
            scheduleSummary: DashboardScheduleSummary.text(
                latestSchedule: latestSchedule,
                startDate: startDate,
                endDate: endDate,
                schedules: scheduleHistory,
                today: today,
                calendar: calendar
            ),
            currentStreak: streak,
            reminderText: reminderText,
            reminderHour: displayReminderHour,
            reminderMinute: displayReminderMinute,
            isReminderScheduledToday: scheduledToday,
            isCompletedToday: isCompletedToday,
            isSkippedToday: isSkippedToday,
            needsHistoryReview: !isArchived && needsHistoryReview(
                startDate: activeStartDate,
                endDate: endDate,
                schedules: scheduleHistory,
                positiveDays: editableSets.positiveDays,
                skippedDays: editableSets.skippedDays,
                today: today,
                activeOverdueDay: activeOverdueDay
            ),
            activeOverdueDay: activeOverdueDay,
            startsInFuture: !isArchived && !hasStarted,
            futureStartDate: isArchived || hasStarted ? nil : activeStartDate,
            isArchived: isArchived,
            sortOrder: sortOrder
        )
    }

    private func clearOverdueAnchorIfNeeded(for habitID: UUID, on day: Date) {
        guard
            let anchorDay = overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar),
            anchorDay == calendar.startOfDay(for: day)
        else {
            return
        }
        overdueAnchorStore.clearAnchorDay(for: .habit, id: habitID)
    }

    private func syncTodayOverdueAnchorAfterClearingDay(
        for habit: NSManagedObject,
        habitID: UUID,
        clearedDay: Date
    ) {
        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: clearedDay) == today else { return }

        func clearTodayAnchorIfPresent() {
            if overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar) == today {
                overdueAnchorStore.clearAnchorDay(for: .habit, id: habitID)
            }
        }

        guard let startDate = habit.dateValue(forKey: "startDate") else {
            clearTodayAnchorIfPresent()
            return
        }
        let activeStartDate = ActiveCycleStartDate.value(
            for: habit,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        guard activeStartDate <= today else {
            clearTodayAnchorIfPresent()
            return
        }

        let reminderEnabled = habit.boolValue(forKey: "reminderEnabled")
        var report = IntegrityReportBuilder()
        guard
            let reminderTime = ReminderValidation.validatedReminderTime(
                from: habit,
                reminderEnabled: reminderEnabled,
                area: "habit.clearDayState",
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

        let schedules = loadSchedules(for: habit, habitID: habitID)
        guard
            HistoryScheduleApplicability.isScheduled(
                on: today,
                startDate: activeStartDate,
                endDate: habit.dateValue(forKey: "endDate"),
                from: schedules,
                calendar: calendar
            )
        else {
            clearTodayAnchorIfPresent()
            return
        }

        overdueAnchorStore.setAnchorDay(today, for: .habit, id: habitID, calendar: calendar)
    }

    private func syncTodayOverdueAnchorAfterEdit(
        habitID: UUID,
        startDate: Date,
        endDate: Date? = nil,
        schedules: [HabitScheduleVersion],
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
            overdueAnchorStore.setAnchorDay(today, for: .habit, id: habitID, calendar: calendar)
        } else if overdueAnchorStore.anchorDay(for: .habit, id: habitID, calendar: calendar) == today {
            overdueAnchorStore.clearAnchorDay(for: .habit, id: habitID)
        }
    }

    private func needsHistoryReview(
        startDate: Date,
        endDate: Date? = nil,
        schedules: [HabitScheduleVersion],
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
        schedules: [HabitScheduleVersion],
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

    private func loadLatestScheduleObject(for habitObject: NSManagedObject) -> NSManagedObject? {
        CoreDataScheduleSupport.latestScheduleObject(in: habitObject.mutableSetValue(forKey: "scheduleVersions"))
    }

    private func habitHistoryMode(for habitObject: NSManagedObject) -> HabitHistoryMode? {
        guard let rawValue = habitObject.stringValue(forKey: "historyModeRaw"), !rawValue.isEmpty else {
            return .scheduleBased
        }

        return HabitHistoryMode(rawValue: rawValue)
    }

    private func habitDashboardSort(_ lhs: HabitCardProjection, _ rhs: HabitCardProjection) -> Bool {
        if lhs.type != rhs.type {
            return lhs.type.rawValue < rhs.type.rawValue
        }

        let lhsReminder = reminderSortKey(for: lhs)
        let rhsReminder = reminderSortKey(for: rhs)
        if lhsReminder != rhsReminder {
            return lhsReminder < rhsReminder
        }

        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func reminderSortKey(for habit: HabitCardProjection) -> Int {
        guard
            let hour = habit.reminderHour,
            let minute = habit.reminderMinute
        else {
            return Int.max
        }

        return (hour * 60) + minute
    }
}
