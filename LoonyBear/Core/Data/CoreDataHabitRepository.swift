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

    func fetchDashboardHabits() throws -> [HabitCardProjection] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.sortDescriptors = [
            NSSortDescriptor(key: "typeRaw", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        let habits = try readContext.fetch(request)
        let today = Calendar.current.startOfDay(for: Date())
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

        let today = Calendar.current.startOfDay(for: Date())
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
                .map { Calendar.current.startOfDay(for: $0.localDate) }
        )
        let latestSchedule = scheduleHistory.sorted(by: isNewerSchedule).first

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
            currentStreak: StreakEngine.currentStreak(completions: successfulCompletions, schedules: scheduleHistory, today: today),
            longestStreak: StreakEngine.longestStreak(completions: successfulCompletions, schedules: scheduleHistory),
            totalCompletedDays: Set(successfulCompletions.map { Calendar.current.startOfDay(for: $0.localDate) }).count,
            completedDays: Set(successfulCompletions.map { Calendar.current.startOfDay(for: $0.localDate) }),
            skippedDays: skippedDays
        )
    }

    func reconcilePastDays(today: Date = Date()) throws -> Int {
        try repositoryContext.performWrite({ context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            let habits = try context.fetch(request)
            let normalizedToday = Calendar.current.startOfDay(for: today)
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
                let existingCompletionObjectsByDay = groupedHistoryObjectsByDay(existingCompletionObjects)
                insertedCount += autoFillMissingCompletedCompletions(
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
            let now = Date()
            let habitID = UUID()

            let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
            habit.setValue(habitID, forKey: "id")
            habit.setValue(draft.type.rawValue, forKey: "typeRaw")
            habit.setValue(draft.trimmedName, forKey: "name")
            habit.setValue(maxSortOrder + 1, forKey: "sortOrder")
            habit.setValue(Calendar.current.startOfDay(for: draft.startDate), forKey: "startDate")
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
            schedule.setValue(Calendar.current.startOfDay(for: draft.startDate), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(habit, forKey: "habit")

            _ = autoFillMissingCompletedCompletions(
                for: habit,
                habitID: habitID,
                startDate: draft.startDate,
                historyMode: draft.useScheduleForHistory ? .scheduleBased : .everyDay,
                schedules: [
                    HabitScheduleVersion(
                        id: schedule.uuidValue(forKey: "id") ?? UUID(),
                        habitID: habitID,
                        weekdays: draft.scheduleDays,
                        effectiveFrom: Calendar.current.startOfDay(for: draft.startDate),
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

            let today = Calendar.current.startOfDay(for: Date())
            if let existingCompletion = try fetchCompletion(for: id, on: today, in: context) {
                guard
                    let sourceRaw = existingCompletion.value(forKey: "sourceRaw") as? String,
                    let source = CompletionSource(rawValue: sourceRaw)
                else {
                    return
                }

                if source == .skipped {
                    existingCompletion.setValue(CompletionSource.swipe.rawValue, forKey: "sourceRaw")
                    existingCompletion.setValue(Date(), forKey: "createdAt")
                    try context.save()
                }
                return
            }

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(id, forKey: "habitID")
            completion.setValue(today, forKey: "localDate")
            completion.setValue(CompletionSource.swipe.rawValue, forKey: "sourceRaw")
            completion.setValue(Date(), forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")

            try context.save()
        }
    }

    func skipHabitToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }

            let today = Calendar.current.startOfDay(for: Date())
            if let existingCompletion = try fetchCompletion(for: id, on: today, in: context) {
                guard
                    let sourceRaw = existingCompletion.value(forKey: "sourceRaw") as? String,
                    let source = CompletionSource(rawValue: sourceRaw)
                else {
                    return
                }

                guard source == .skipped else { return }
                return
            }

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(id, forKey: "habitID")
            completion.setValue(today, forKey: "localDate")
            completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
            completion.setValue(Date(), forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")

            try context.save()
        }
    }

    func clearHabitDayStateToday(id: UUID) throws {
        try repositoryContext.performWrite { context in
            let today = Calendar.current.startOfDay(for: Date())
            guard let completion = try fetchCompletion(for: id, on: today, in: context) else { return }

            context.delete(completion)
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
            habit.setValue(draft.historyMode.rawValue, forKey: "historyModeRaw")
            habit.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            habit.setValue(Date(), forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: habit)
            let currentWeekdayMask = currentSchedule?.int16Value(forKey: "weekdayMask") ?? 0
            if currentWeekdayMask != draft.scheduleDays.rawValue {
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "habitID")
                schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
                schedule.setValue(Calendar.current.startOfDay(for: Date()), forKey: "effectiveFrom")
                schedule.setValue(Date(), forKey: "createdAt")
                schedule.setValue(currentSchedule.map { $0.int32Value(forKey: "version") + 1 } ?? 1, forKey: "version")
                schedule.setValue(habit, forKey: "habit")
            }

            let existingCompletionObjects = (habit.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
            let editableSet = EditableHistoryWindow.dates(startDate: draft.startDate)
            let schedules = loadSchedules(for: habit, habitID: draft.id)
            let requiredFinalizedDays = HistoryScheduleApplicability.pastRequiredEditableDays(
                in: editableSet,
                schedules: schedules,
                historyMode: draft.historyMode
            )
            let normalizedSelection = EditableHistoryContract.normalizedSelection(
                positiveDays: draft.completedDays,
                skippedDays: draft.skippedDays,
                requiredFinalizedDays: requiredFinalizedDays,
                pastDefaultSelection: .positive
            )
            let existingByDay = groupedHistoryObjectsByDay(existingCompletionObjects)
            let normalizedToday = Calendar.current.startOfDay(for: Date())

            for day in editableSet {
                let shouldBeCompleted = normalizedSelection.positiveDays.contains(day)
                let shouldBeSkipped = normalizedSelection.skippedDays.contains(day)
                let existingObjects = existingByDay[day] ?? []
                let existing = primaryHistoryObject(in: existingObjects)

                for duplicate in existingObjects where duplicate != existing {
                    context.delete(duplicate)
                }

                if shouldBeCompleted, existing == nil {
                    let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
                    completion.setValue(UUID(), forKey: "id")
                    completion.setValue(draft.id, forKey: "habitID")
                    completion.setValue(day, forKey: "localDate")
                    completion.setValue(CompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                    completion.setValue(Date(), forKey: "createdAt")
                    completion.setValue(habit, forKey: "habit")
                } else if shouldBeCompleted, let existing {
                    guard
                        let sourceRaw = existing.stringValue(forKey: "sourceRaw"),
                        let source = CompletionSource(rawValue: sourceRaw)
                    else {
                        continue
                    }

                    if !source.countsAsCompletion {
                        existing.setValue(CompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                        existing.setValue(Date(), forKey: "createdAt")
                    }
                } else if shouldBeSkipped, existing == nil {
                    let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
                    completion.setValue(UUID(), forKey: "id")
                    completion.setValue(draft.id, forKey: "habitID")
                    completion.setValue(day, forKey: "localDate")
                    completion.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
                    completion.setValue(Date(), forKey: "createdAt")
                    completion.setValue(habit, forKey: "habit")
                } else if shouldBeSkipped, let existing {
                    guard
                        let sourceRaw = existing.stringValue(forKey: "sourceRaw"),
                        let source = CompletionSource(rawValue: sourceRaw)
                    else {
                        continue
                    }

                    if source != .skipped {
                        existing.setValue(CompletionSource.skipped.rawValue, forKey: "sourceRaw")
                        existing.setValue(Date(), forKey: "createdAt")
                    }
                } else if day == normalizedToday, let existing {
                    context.delete(existing)
                }
            }

            try context.save()
        }
    }

    private func fetchHabit(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchCompletion(for habitID: UUID, on localDate: Date, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "habitID == %@", habitID as CVarArg),
            NSPredicate(format: "localDate == %@", localDate as CVarArg),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func groupedHistoryObjectsByDay(
        _ objects: [NSManagedObject],
        calendar: Calendar = .current
    ) -> [Date: [NSManagedObject]] {
        Dictionary(grouping: objects.compactMap { object -> (Date, NSManagedObject)? in
            guard let localDate = object.dateValue(forKey: "localDate") else { return nil }
            return (calendar.startOfDay(for: localDate), object)
        }, by: \.0).mapValues { entries in
            entries.map(\.1)
        }
    }

    private func primaryHistoryObject(in objects: [NSManagedObject]) -> NSManagedObject? {
        objects.max { lhs, rhs in
            let lhsCreatedAt = lhs.dateValue(forKey: "createdAt") ?? .distantPast
            let rhsCreatedAt = rhs.dateValue(forKey: "createdAt") ?? .distantPast
            if lhsCreatedAt != rhsCreatedAt {
                return lhsCreatedAt < rhsCreatedAt
            }
            return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
        }
    }

    private func autoFillMissingCompletedCompletions(
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
        let calendar = Calendar.current
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
            completion.setValue(CompletionSource.autoFill.rawValue, forKey: "sourceRaw")
            completion.setValue(Date(), forKey: "createdAt")
            completion.setValue(habitObject, forKey: "habit")
            insertedCount += 1
        }

        return insertedCount
    }

    private func loadCompletions(for habitObject: NSManagedObject, habitID: UUID) -> [HabitCompletion] {
        let completions = (habitObject.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
        return completions.compactMap { completionObject in
            guard
                let completionID = completionObject.uuidValue(forKey: "id"),
                let localDate = completionObject.dateValue(forKey: "localDate"),
                let sourceRaw = completionObject.stringValue(forKey: "sourceRaw"),
                let source = CompletionSource(rawValue: sourceRaw),
                let createdAt = completionObject.dateValue(forKey: "createdAt")
            else {
                return nil
            }

            return HabitCompletion(
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
        let completions = (habitObject.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
        var models: [HabitCompletion] = []

        for completionObject in completions {
            guard
                let completionID = completionObject.uuidValue(forKey: "id"),
                let localDate = completionObject.dateValue(forKey: "localDate"),
                let sourceRaw = completionObject.stringValue(forKey: "sourceRaw"),
                let source = CompletionSource(rawValue: sourceRaw),
                let createdAt = completionObject.dateValue(forKey: "createdAt")
            else {
                report.append(
                    area: "dashboard",
                    entityName: completionObject.entityName,
                    object: completionObject,
                    message: "Habit completion row is missing required fields or has invalid sourceRaw."
                )
                return nil
            }

            models.append(
                HabitCompletion(
                    id: completionID,
                    habitID: habitID,
                    localDate: localDate,
                    source: source,
                    createdAt: createdAt
                )
            )
        }

        return models
    }

    private func loadSchedules(for habitObject: NSManagedObject, habitID: UUID) -> [HabitScheduleVersion] {
        let schedules = (habitObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        return schedules
            .compactMap { scheduleObject -> HabitScheduleVersion? in
                guard
                    let scheduleID = scheduleObject.uuidValue(forKey: "id"),
                    let effectiveFrom = scheduleObject.dateValue(forKey: "effectiveFrom"),
                    let createdAt = scheduleObject.dateValue(forKey: "createdAt")
                else {
                    return nil
                }

                let weekdayMask = scheduleObject.int16Value(forKey: "weekdayMask")
                let version = Int(scheduleObject.int32Value(forKey: "version", default: 1))

                return HabitScheduleVersion(
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
        let schedules = (habitObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        var models: [HabitScheduleVersion] = []

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
                    message: "Habit schedule row is missing required fields."
                )
                return nil
            }
            let weekdayMask = Int(scheduleObject.int16Value(forKey: "weekdayMask"))
            guard WeekdayValidation.isValidMask(weekdayMask) else {
                report.append(
                    area: "dashboard",
                    entityName: scheduleObject.entityName,
                    object: scheduleObject,
                    message: "Habit schedule row contains invalid weekdayMask."
                )
                return nil
            }

            models.append(
                HabitScheduleVersion(
                    id: scheduleID,
                    habitID: habitID,
                    weekdays: WeekdaySet(rawValue: weekdayMask),
                    effectiveFrom: effectiveFrom,
                    createdAt: createdAt,
                    version: Int(scheduleObject.int32Value(forKey: "version", default: 1))
                )
            )
        }

        return models
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
        let latestSchedule = scheduleHistory.sorted(by: isNewerSchedule).first
        let successfulCompletions = completionModels.filter { $0.source.countsAsCompletion }
        let isCompletedToday = successfulCompletions.contains { Calendar.current.isDate($0.localDate, inSameDayAs: today) }
        let isSkippedToday = completionModels.contains {
            !$0.source.countsAsCompletion && Calendar.current.isDate($0.localDate, inSameDayAs: today)
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
        let scheduledToday = latestSchedule?.weekdays.contains(Calendar.current.weekdaySet(for: today)) ?? false
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

    private func isNewerSchedule(_ lhs: HabitScheduleVersion, _ rhs: HabitScheduleVersion) -> Bool {
        if lhs.effectiveFrom != rhs.effectiveFrom {
            return lhs.effectiveFrom > rhs.effectiveFrom
        }
        if lhs.version != rhs.version {
            return lhs.version > rhs.version
        }
        return lhs.createdAt > rhs.createdAt
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
