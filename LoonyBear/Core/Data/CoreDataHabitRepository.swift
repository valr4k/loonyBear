import CoreData
import Foundation

enum HabitRepositoryError: LocalizedError {
    case internalFailure

    var errorDescription: String? {
        switch self {
        case .internalFailure:
            return "Habit operation failed unexpectedly."
        }
    }
}

@MainActor
struct CoreDataHabitRepository: HabitRepository {
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

    func fetchDashboardHabits() throws -> [HabitCardProjection] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.sortDescriptors = [
            NSSortDescriptor(key: "typeRaw", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        let habits = try readContext.fetch(request)
        let today = calendar.startOfDay(for: clock.now())
        var report = IntegrityReportBuilder()
        var projections: [HabitCardProjection] = []

        for habitObject in habits {
            if let projection = makeDashboardProjection(
                from: habitObject,
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

        let today = calendar.startOfDay(for: clock.now())
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

        return HabitDetailsProjection(
            id: id,
            type: type,
            name: name,
            startDate: startDate,
            historyMode: historyMode,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            scheduleDays: latestSchedule?.weekdays ?? .daily,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            currentStreak: StreakEngine.currentStreak(
                completions: successfulCompletions,
                skippedCompletions: completions.filter { !$0.source.countsAsCompletion },
                schedules: scheduleHistory,
                today: today
            ),
            longestStreak: StreakEngine.longestStreak(completions: successfulCompletions, schedules: scheduleHistory),
            totalCompletedDays: Set(successfulCompletions.map { calendar.startOfDay(for: $0.localDate) }).count,
            completedDays: Set(successfulCompletions.map { calendar.startOfDay(for: $0.localDate) }),
            skippedDays: skippedDays
        )
    }

    func reconcilePastDays(today: Date) throws -> Int {
        try repositoryContext.performWrite({ context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            let habits = try context.fetch(request)
            let normalizedToday = calendar.startOfDay(for: today)
            var report = IntegrityReportBuilder()
            var insertedCount = 0

            for habitObject in habits {
                guard
                    let habitID = habitObject.uuidValue(forKey: "id"),
                    let startDate = habitObject.dateValue(forKey: "startDate"),
                    let historyMode = habitHistoryMode(for: habitObject)
                else {
                    report.append(
                        area: "reconciliation",
                        entityName: habitObject.entityName,
                        object: habitObject,
                        message: "Habit row is missing required fields for history reconciliation."
                    )
                    continue
                }

                guard
                    let completionModels = loadCompletions(for: habitObject, habitID: habitID, report: &report),
                    let scheduleHistory = loadSchedules(for: habitObject, habitID: habitID, report: &report)
                else {
                    report.append(
                        area: "reconciliation",
                        entityName: habitObject.entityName,
                        object: habitObject,
                        message: "Habit reconciliation failed because related rows are corrupted."
                    )
                    continue
                }

                let existingCompletionObjects = (habitObject.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
                let existingCompletionObjectsByDay = CoreDataHistorySupport.groupedHistoryObjectsByDay(existingCompletionObjects)
                insertedCount += insertMissingPastSkippedCompletions(
                    for: habitObject,
                    habitID: habitID,
                    startDate: startDate,
                    historyMode: historyMode,
                    schedules: scheduleHistory,
                    completionObjectsByDay: existingCompletionObjectsByDay,
                    completionModels: completionModels,
                    today: normalizedToday,
                    context: context
                )
            }

            if report.hasIssues {
                throw report.makeError(operation: "habit.reconcilePastDays")
            }

            if insertedCount > 0 {
                try context.save()
            }

            return insertedCount
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

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
            schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
            schedule.setValue(calendar.startOfDay(for: draft.startDate), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(habit, forKey: "habit")

            _ = insertMissingPastSkippedCompletions(
                for: habit,
                habitID: habitID,
                startDate: draft.startDate,
                historyMode: draft.useScheduleForHistory ? .scheduleBased : .everyDay,
                schedules: [
                    HabitScheduleVersion(
                        id: schedule.uuidValue(forKey: "id") ?? UUID(),
                        habitID: habitID,
                        weekdays: draft.scheduleDays,
                        effectiveFrom: calendar.startOfDay(for: draft.startDate),
                        createdAt: now,
                        version: 1
                    ),
                ],
                completionObjectsByDay: [:],
                completionModels: [],
                today: now,
                context: context
            )

            try context.save()
            return habitID
        }, missingResultError: HabitRepositoryError.internalFailure)
    }

    func completeHabitToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }

            let today = calendar.startOfDay(for: clock.now())
            let didChange = try upsertCompletion(
                for: habit,
                habitID: id,
                on: today,
                source: .swipe,
                in: context,
                updateWhen: { $0 == .skipped }
            )

            guard didChange else { return }
            try context.save()
        }
    }

    func skipHabitToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }

            let today = calendar.startOfDay(for: clock.now())
            let didChange = try upsertCompletion(
                for: habit,
                habitID: id,
                on: today,
                source: .skipped,
                in: context,
                updateWhen: { _ in false }
            )

            guard didChange else { return }
            try context.save()
        }
    }

    func clearHabitDayStateToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            let today = calendar.startOfDay(for: clock.now())
            let completions = try fetchCompletions(for: id, on: today, in: context)
            guard !completions.isEmpty else { return }

            for completion in completions {
                context.delete(completion)
            }
            try context.save()
        }
    }

    func deleteHabit(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }

            context.delete(habit)
            try context.save()
        }
    }

    func updateHabit(from draft: EditHabitDraft) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: draft.id, in: context) else { return }

            habit.setValue(draft.trimmedName, forKey: "name")
            habit.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            let now = clock.now()
            habit.setValue(now, forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: habit)
            let currentWeekdayMask = currentSchedule?.int16Value(forKey: "weekdayMask") ?? 0
            if currentWeekdayMask != draft.scheduleDays.rawValue {
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "habitID")
                schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
                schedule.setValue(calendar.startOfDay(for: now), forKey: "effectiveFrom")
                schedule.setValue(now, forKey: "createdAt")
                schedule.setValue(currentSchedule.map { $0.int32Value(forKey: "version") + 1 } ?? 1, forKey: "version")
                schedule.setValue(habit, forKey: "habit")
            }

            let normalizedToday = calendar.startOfDay(for: now)
            let existingCompletionObjects = (habit.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
            let editableSet = EditableHistoryWindow.dates(
                startDate: draft.startDate,
                today: normalizedToday,
                calendar: calendar
            )
            let requiredFinalizedDays = HistoryScheduleApplicability.pastRequiredEditableDays(
                in: editableSet,
                schedules: loadSchedules(for: habit, habitID: draft.id),
                historyMode: habitHistoryMode(for: habit) ?? .scheduleBased,
                today: normalizedToday,
                calendar: calendar
            )
            let normalizedSelection = EditableHistoryContract.normalizedSelection(
                positiveDays: draft.completedDays,
                skippedDays: draft.skippedDays,
                requiredFinalizedDays: requiredFinalizedDays,
                pastDefaultSelection: .skipped,
                today: normalizedToday,
                calendar: calendar
            )
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
                } else if day == normalizedToday, let existing {
                    context.delete(existing)
                }
            }

            try context.save()
        }
    }

    private func fetchHabit(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        try CoreDataFetchSupport.fetchObject(
            entityName: "Habit",
            id: id,
            in: context
        )
    }

    private func fetchCompletion(for habitID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        try CoreDataFetchSupport.fetchHistoryObject(
            entityName: "HabitCompletion",
            ownerKey: "habitID",
            ownerID: habitID,
            localDate: localDate,
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

    private func insertMissingPastSkippedCompletions(
        for habitObject: NSManagedObject,
        habitID: UUID,
        startDate: Date,
        historyMode: HabitHistoryMode,
        schedules: [HabitScheduleVersion],
        completionObjectsByDay: [Date: [NSManagedObject]],
        completionModels: [HabitCompletion],
        today: Date,
        context: NSManagedObjectContext
    ) -> Int {
        let normalizedToday = calendar.startOfDay(for: today)
        let completionDays = Set(completionModels.map { calendar.startOfDay(for: $0.localDate) })
        let skippedDays = Set(
            completionModels
                .filter { !$0.source.countsAsCompletion }
                .map { calendar.startOfDay(for: $0.localDate) }
        )
        let requiredFinalizedDays = HistoryScheduleApplicability.pastRequiredEditableDays(
            in: EditableHistoryWindow.dates(
                startDate: startDate,
                today: normalizedToday,
                calendar: calendar
            ),
            schedules: schedules,
            historyMode: historyMode,
            today: normalizedToday,
            calendar: calendar
        )

        var insertedCount = 0
        for day in requiredFinalizedDays.sorted() {
            guard !completionDays.contains(day) else { continue }
            guard !skippedDays.contains(day) else { continue }
            guard (completionObjectsByDay[day] ?? []).isEmpty else { continue }

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(habitID, forKey: "habitID")
            completion.setValue(day, forKey: "localDate")
            completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
            completion.setValue(clock.now(), forKey: "createdAt")
            completion.setValue(habitObject, forKey: "habit")
            insertedCount += 1
        }

        return insertedCount
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
        ) { scheduleID, weekdayMask, effectiveFrom, createdAt, version in
            HabitScheduleVersion(
                id: scheduleID,
                habitID: habitID,
                weekdays: WeekdaySet(rawValue: weekdayMask),
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
        ) { scheduleID, weekdayMask, effectiveFrom, createdAt, version in
            HabitScheduleVersion(
                id: scheduleID,
                habitID: habitID,
                weekdays: WeekdaySet(rawValue: weekdayMask),
                effectiveFrom: effectiveFrom,
                createdAt: createdAt,
                version: version
            )
        }
    }

    private func makeDashboardProjection(
        from habitObject: NSManagedObject,
        today: Date,
        report: inout IntegrityReportBuilder
    ) -> HabitCardProjection? {
        guard
            let id = habitObject.uuidValue(forKey: "id"),
            let typeRaw = habitObject.stringValue(forKey: "typeRaw"),
            let type = HabitType(rawValue: typeRaw),
            let name = habitObject.stringValue(forKey: "name")
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
        let latestSchedule = scheduleHistory.sorted(by: CoreDataScheduleSupport.isNewerSchedule).first
        let successfulCompletions = completionModels.filter { $0.source.countsAsCompletion }
        let isCompletedToday = successfulCompletions.contains { calendar.isDate($0.localDate, inSameDayAs: today) }
        let isSkippedToday = completionModels.contains {
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
        let scheduledToday = latestSchedule?.weekdays.contains(calendar.weekdaySet(for: today)) ?? false
        let reminderText: String?
        let displayReminderHour: Int?
        let displayReminderMinute: Int?

        if let validatedReminderTime {
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
            today: today
        )

        return HabitCardProjection(
            id: id,
            type: type,
            name: name,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            currentStreak: streak,
            reminderText: reminderText,
            reminderHour: displayReminderHour,
            reminderMinute: displayReminderMinute,
            isReminderScheduledToday: scheduledToday,
            isCompletedToday: isCompletedToday,
            isSkippedToday: isSkippedToday,
            sortOrder: sortOrder
        )
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
