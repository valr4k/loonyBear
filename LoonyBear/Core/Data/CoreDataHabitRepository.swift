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

    func fetchHabitDetails(id: UUID) throws -> HabitDetailsProjection? {
        guard let habitObject = try fetchHabit(id: id, in: readContext) else {
            return nil
        }

        let now = clock.now()
        let today = calendar.startOfDay(for: now)
        var report = IntegrityReportBuilder()
        guard
            let completions = loadCompletions(for: habitObject, habitID: id, report: &report),
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

        let successfulCompletions = completions.filter { $0.source.countsAsCompletion }
        let completedDays = Set(successfulCompletions.map { calendar.startOfDay(for: $0.localDate) })
        let skippedDays = Set(
            completions
                .filter { !$0.source.countsAsCompletion }
                .map { calendar.startOfDay(for: $0.localDate) }
        )
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
            positiveDays: completedDays,
            skippedDays: skippedDays,
            now: now,
            calendar: calendar
        )
        let scheduledDates = HistoryScheduleApplicability.scheduledDays(
            startDate: activeStartDate,
            through: HistoryMonthWindow.detailsCalendarEndDate(startDate: startDate, today: today, calendar: calendar),
            limitingTo: endDate,
            schedules: scheduleHistory,
            calendar: calendar
        )

        return HabitDetailsProjection(
            id: id,
            type: type,
            name: name,
            startDate: startDate,
            endDate: endDate,
            historyMode: historyMode,
            scheduleSummary: latestSchedule?.rule.summary ?? "No days selected",
            scheduleDays: latestSchedule?.rule.weeklyDays ?? .daily,
            scheduleRule: latestSchedule?.rule ?? .weekly(.daily),
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            currentStreak: StreakEngine.currentStreak(
                completions: successfulCompletions,
                skippedCompletions: completions.filter { !$0.source.countsAsCompletion },
                schedules: scheduleHistory,
                startDate: startDate,
                today: today
            ),
            longestStreak: StreakEngine.longestStreak(
                completions: successfulCompletions,
                schedules: scheduleHistory,
                startDate: startDate
            ),
            totalCompletedDays: completedDays.count,
            completedDays: completedDays,
            skippedDays: skippedDays,
            scheduleHistory: scheduleHistory,
            scheduledDates: scheduledDates,
            needsHistoryReview: !isArchived && needsHistoryReview(
                startDate: activeStartDate,
                endDate: endDate,
                schedules: scheduleHistory,
                positiveDays: completedDays,
                skippedDays: skippedDays,
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
            isArchived: isArchived
        )
    }

    func reconcilePastDays(today: Date) throws -> Int { 0 }

    func createHabit(from draft: CreateHabitDraft) throws -> UUID {
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

            let initialCompletedDays = generatedInitialCompletedDays(from: draft, today: now)
            for day in initialCompletedDays {
                insertCompletion(
                    for: habit,
                    habitID: habitID,
                    on: day,
                    source: .autoFill,
                    in: context
                )
            }

            applyAutomaticArchiveIfNeeded(
                for: habit,
                habitID: habitID,
                startDate: calendar.startOfDay(for: draft.startDate),
                endDate: draft.endDate,
                schedules: loadSchedules(for: habit, habitID: habitID),
                positiveDays: Set(initialCompletedDays),
                skippedDays: []
            )

            try context.save()
            return habitID
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

    func completeHabitToday(id: UUID) throws {
        try completeHabitDay(id: id, on: clock.now())
    }

    func completeHabitDay(id: UUID, on day: Date) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }
            guard !habit.boolValue(forKey: "isArchived") else { return }

            let today = calendar.startOfDay(for: day)
            guard
                let startDate = habit.dateValue(forKey: "startDate"),
                today >= calendar.startOfDay(for: startDate)
            else {
                return
            }
            let didChange = try upsertCompletion(
                for: habit,
                habitID: id,
                on: today,
                source: .swipe,
                in: context,
                updateWhen: { $0 == .skipped }
            )

            guard didChange else { return }
            applyAutomaticArchiveIfNeeded(for: habit, habitID: id)
            try context.save()
            clearOverdueAnchorIfNeeded(for: id, on: today)
        }
    }

    func skipHabitToday(id: UUID) throws {
        try skipHabitDay(id: id, on: clock.now())
    }

    func skipHabitDay(id: UUID, on day: Date) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }
            guard !habit.boolValue(forKey: "isArchived") else { return }

            let today = calendar.startOfDay(for: day)
            guard
                let startDate = habit.dateValue(forKey: "startDate"),
                today >= calendar.startOfDay(for: startDate)
            else {
                return
            }
            let didChange = try upsertCompletion(
                for: habit,
                habitID: id,
                on: today,
                source: .skipped,
                in: context,
                updateWhen: { _ in false }
            )

            guard didChange else { return }
            applyAutomaticArchiveIfNeeded(for: habit, habitID: id)
            try context.save()
            clearOverdueAnchorIfNeeded(for: id, on: today)
        }
    }

    func clearHabitDayStateToday(id: UUID) throws {
        try clearHabitDayState(id: id, on: clock.now())
    }

    func clearHabitDayState(id: UUID, on day: Date) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }
            guard !habit.boolValue(forKey: "isArchived") else { return }
            let today = calendar.startOfDay(for: day)
            let completions = try fetchCompletions(for: id, on: today, in: context)
            guard !completions.isEmpty else { return }

            for completion in completions {
                context.delete(completion)
            }
            try context.save()
            syncTodayOverdueAnchorAfterClearingDay(for: habit, habitID: id, clearedDay: today)
        }
    }

    func deleteHabit(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }

            context.delete(habit)
            try context.save()
        }
    }

    func setHabitArchived(id: UUID, isArchived: Bool) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }
            guard habit.boolValue(forKey: "isArchived") != isArchived else { return }

            habit.setValue(isArchived, forKey: "isArchived")
            habit.setValue(clock.now(), forKey: "updatedAt")
            try context.save()

            if isArchived {
                overdueAnchorStore.clearAnchorDay(for: .habit, id: id)
            }
        }
    }

    func updateHabit(from draft: EditHabitDraft) throws {
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
                startDate: draft.startDate,
                today: normalizedToday,
                calendar: calendar
            )
            let scheduledEditableSet = HistoryScheduleApplicability.pastScheduledEditableDays(
                in: editableSet,
                startDate: draft.startDate,
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

            let existingCompletionObjects = try fetchCompletions(for: draft.id, on: editableSet, in: context)
            let existingByDay = CoreDataHistorySupport.groupedHistoryObjectsByDay(existingCompletionObjects)

            for day in editableSet {
                let shouldBeCompleted = normalizedSelection.positiveDays.contains(day)
                let shouldBeSkipped = normalizedSelection.skippedDays.contains(day)
                let existingObjects = existingByDay[day] ?? []
                let existing = primaryHistoryObject(in: existingObjects)

                for duplicate in existingObjects where duplicate != existing {
                    context.delete(duplicate)
                }

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
                } else if let existing {
                    context.delete(existing)
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
                    startDate: draft.startDate,
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

    private func upsertCompletion(
        for habit: NSManagedObject,
        habitID: UUID,
        on localDate: Date,
        source desiredSource: CompletionSource,
        in context: NSManagedObjectContext,
        updateWhen shouldUpdate: (CompletionSource) -> Bool
    ) throws -> Bool {
        let normalizedDate = calendar.startOfDay(for: localDate)
        let existingObjects = try fetchCompletions(for: habitID, on: normalizedDate, in: context)
        let existing = primaryHistoryObject(in: existingObjects)
        let duplicateObjects = existingObjects.filter { $0 != existing }

        for duplicate in duplicateObjects {
            context.delete(duplicate)
        }

        guard let existing else {
            insertCompletion(
                for: habit,
                habitID: habitID,
                on: normalizedDate,
                source: desiredSource,
                in: context
            )
            return true
        }

        guard
            let sourceRaw = existing.stringValue(forKey: "sourceRaw"),
            let existingSource = CompletionSource(rawValue: sourceRaw)
        else {
            return !duplicateObjects.isEmpty
        }

        guard shouldUpdate(existingSource), existingSource != desiredSource else {
            return !duplicateObjects.isEmpty
        }

        existing.setValue(desiredSource.rawValue, forKey: "sourceRaw")
        existing.setValue(clock.now(), forKey: "createdAt")
        existing.setValue(habit, forKey: "habit")
        return true
    }

    private func insertCompletion(
        for habit: NSManagedObject,
        habitID: UUID,
        on localDate: Date,
        source: CompletionSource,
        in context: NSManagedObjectContext
    ) {
        let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
        completion.setValue(UUID(), forKey: "id")
        completion.setValue(habitID, forKey: "habitID")
        completion.setValue(localDate, forKey: "localDate")
        completion.setValue(source.rawValue, forKey: "sourceRaw")
        completion.setValue(clock.now(), forKey: "createdAt")
        completion.setValue(habit, forKey: "habit")
    }

    private func applyAutomaticArchiveIfNeeded(
        for habit: NSManagedObject,
        habitID: UUID
    ) {
        let completions = loadCompletions(for: habit, habitID: habitID)
        let positiveDays = Set(
            completions
                .filter { $0.source.countsAsCompletion }
                .map { calendar.startOfDay(for: $0.localDate) }
        )
        let skippedDays = Set(
            completions
                .filter { !$0.source.countsAsCompletion }
                .map { calendar.startOfDay(for: $0.localDate) }
        )

        applyAutomaticArchiveIfNeeded(
            for: habit,
            habitID: habitID,
            positiveDays: positiveDays,
            skippedDays: skippedDays
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
        guard ScheduleLifecycleSupport.shouldAutoArchive(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            positiveDays: positiveDays,
            skippedDays: skippedDays,
            calendar: calendar
        ) else {
            return
        }

        habit.setValue(true, forKey: "isArchived")
        habit.setValue(clock.now(), forKey: "updatedAt")
        overdueAnchorStore.clearAnchorDay(for: .habit, id: habitID)
    }

    private func resolvedScheduleEffectiveFrom(
        from draft: EditHabitDraft,
        normalizedSelection: (positiveDays: Set<Date>, skippedDays: Set<Date>),
        now: Date
    ) -> Date {
        let normalizedToday = calendar.startOfDay(for: now)
        let minimumDate = max(normalizedToday, calendar.startOfDay(for: draft.startDate))
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

    private func generatedInitialCompletedDays(from draft: CreateHabitDraft, today: Date) -> [Date] {
        let startDate = calendar.startOfDay(for: draft.startDate)
        let normalizedToday = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: normalizedToday) else {
            return []
        }
        let endDate = draft.endDate
            .map { min(calendar.startOfDay(for: yesterday), calendar.startOfDay(for: $0)) }
            ?? calendar.startOfDay(for: yesterday)
        guard startDate <= endDate else { return [] }

        var completedDays: [Date] = []
        var cursor = startDate

        while cursor <= endDate {
            if shouldGenerateInitialCompletion(on: cursor, for: draft) {
                completedDays.append(cursor)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return completedDays
    }

    private func shouldGenerateInitialCompletion(on day: Date, for draft: CreateHabitDraft) -> Bool {
        guard draft.useScheduleForHistory else { return true }
        return draft.scheduleRule.isScheduled(on: day, anchorDate: draft.startDate, calendar: calendar)
    }

    private func loadCompletions(for habitObject: NSManagedObject, habitID: UUID) -> [HabitCompletion] {
        CoreDataRelationshipLoadingSupport.compactHistoryModels(
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
    }

    private func loadCompletions(
        for habitObject: NSManagedObject,
        habitID: UUID,
        report: inout IntegrityReportBuilder
    ) -> [HabitCompletion]? {
        CoreDataRelationshipLoadingSupport.validatedHistoryModels(
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
            let completionModels = loadCompletions(for: habitObject, habitID: id, report: &report),
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
        let successfulCompletions = completionModels.filter { $0.source.countsAsCompletion }
        let completedDays = Set(successfulCompletions.map { calendar.startOfDay(for: $0.localDate) })
        let skippedDays = Set(
            completionModels
                .filter { !$0.source.countsAsCompletion }
                .map { calendar.startOfDay(for: $0.localDate) }
        )
        let activeStartDate = ActiveCycleStartDate.value(
            for: habitObject,
            fallbackStartDate: startDate,
            calendar: calendar
        )
        let hasStarted = activeStartDate <= today
        let isCompletedToday = !isArchived && hasStarted && successfulCompletions.contains { calendar.isDate($0.localDate, inSameDayAs: today) }
        let isSkippedToday = !isArchived && hasStarted && completionModels.contains {
            !$0.source.countsAsCompletion && calendar.isDate($0.localDate, inSameDayAs: today)
        }
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
            completions: successfulCompletions,
            skippedCompletions: completionModels.filter { !$0.source.countsAsCompletion },
            schedules: scheduleHistory,
            startDate: startDate,
            today: today
        )
        let activeOverdueDay = isArchived ? nil : ScheduledOverdueState.activeOverdueDay(
            startDate: activeStartDate,
            endDate: endDate,
            schedules: scheduleHistory,
            reminderTime: validatedReminderTime,
            positiveDays: completedDays,
            skippedDays: skippedDays,
            now: now,
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
                positiveDays: completedDays,
                skippedDays: skippedDays,
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
        let dueDays = ScheduledOverdueState.dueScheduledDays(
            startDate: startDate,
            endDate: endDate,
            schedules: schedules,
            reminderTime: reminderTime,
            positiveDays: positiveDays,
            skippedDays: skippedDays,
            now: now,
            calendar: calendar
        )

        if dueDays.contains(today) {
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
