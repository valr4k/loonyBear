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

struct CoreDataHabitRepository: HabitRepository {
    private let readContext: NSManagedObjectContext
    private let makeWriteContext: () -> NSManagedObjectContext

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext
    ) {
        readContext = context
        self.makeWriteContext = makeWriteContext
    }

    func fetchDashboardHabits() -> [HabitCardProjection] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        request.sortDescriptors = [
            NSSortDescriptor(key: "typeRaw", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        let habits = (try? readContext.fetch(request)) ?? []
        let today = Calendar.current.startOfDay(for: Date())

        return habits.compactMap { habitObject -> HabitCardProjection? in
            guard
                let id = habitObject.value(forKey: "id") as? UUID,
                let typeRaw = habitObject.value(forKey: "typeRaw") as? String,
                let type = HabitType(rawValue: typeRaw),
                let name = habitObject.value(forKey: "name") as? String
            else {
                return nil
            }
            let sortOrder = Int(habitObject.value(forKey: "sortOrder") as? Int32 ?? 0)

            let completions = (habitObject.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
            let completionModels: [HabitCompletion] = completions.compactMap { completionObject in
                guard
                    let completionID = completionObject.value(forKey: "id") as? UUID,
                    let localDate = completionObject.value(forKey: "localDate") as? Date,
                    let sourceRaw = completionObject.value(forKey: "sourceRaw") as? String,
                    let source = CompletionSource(rawValue: sourceRaw),
                    let createdAt = completionObject.value(forKey: "createdAt") as? Date
                else {
                    return nil
                }

                return HabitCompletion(
                    id: completionID,
                    habitID: id,
                    localDate: localDate,
                    source: source,
                    createdAt: createdAt
                )
            }

            let scheduleHistory = loadSchedules(for: habitObject, habitID: id)
            let latestSchedule = scheduleHistory.sorted(by: isNewerSchedule).first
            let isCompletedToday = completionModels.contains { Calendar.current.isDate($0.localDate, inSameDayAs: today) }
            let reminderEnabled = habitObject.value(forKey: "reminderEnabled") as? Bool ?? false
            let reminderHour = Int(habitObject.value(forKey: "reminderHour") as? Int16 ?? 0)
            let reminderMinute = Int(habitObject.value(forKey: "reminderMinute") as? Int16 ?? 0)
            let scheduledToday = latestSchedule?.weekdays.contains(Calendar.current.weekdaySet(for: today)) ?? false
            let reminderText: String?
            let displayReminderHour: Int?
            let displayReminderMinute: Int?

            if reminderEnabled {
                let reminderTime = ReminderTime(hour: reminderHour, minute: reminderMinute)
                reminderText = reminderTime.formatted
                displayReminderHour = reminderHour
                displayReminderMinute = reminderMinute
            } else {
                reminderText = nil
                displayReminderHour = nil
                displayReminderMinute = nil
            }

            let streak = StreakEngine.currentStreak(
                completions: completionModels,
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
                sortOrder: sortOrder
            )
        }
    }

    func fetchHabitDetails(id: UUID) -> HabitDetailsProjection? {
        guard let habitObject = try? fetchHabit(id: id, in: readContext) else {
            return nil
        }

        let today = Calendar.current.startOfDay(for: Date())
        let completions = loadCompletions(for: habitObject, habitID: id)
        let scheduleHistory = loadSchedules(for: habitObject, habitID: id)
        let latestSchedule = scheduleHistory.sorted(by: isNewerSchedule).first

        guard
            let typeRaw = habitObject.value(forKey: "typeRaw") as? String,
            let type = HabitType(rawValue: typeRaw),
            let name = habitObject.value(forKey: "name") as? String,
            let startDate = habitObject.value(forKey: "startDate") as? Date
        else {
            return nil
        }

        let reminderEnabled = habitObject.value(forKey: "reminderEnabled") as? Bool ?? false
        let reminderHour = Int(habitObject.value(forKey: "reminderHour") as? Int16 ?? 20)
        let reminderMinute = Int(habitObject.value(forKey: "reminderMinute") as? Int16 ?? 0)
        let reminderTime = reminderEnabled ? ReminderTime(hour: reminderHour, minute: reminderMinute) : nil

        return HabitDetailsProjection(
            id: id,
            type: type,
            name: name,
            startDate: startDate,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            scheduleDays: latestSchedule?.weekdays ?? .daily,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderTime,
            currentStreak: StreakEngine.currentStreak(completions: completions, schedules: scheduleHistory, today: today),
            longestStreak: StreakEngine.longestStreak(completions: completions, schedules: scheduleHistory),
            totalCompletedDays: completions.count,
            completedDays: Set(completions.map { Calendar.current.startOfDay(for: $0.localDate) })
        )
    }

    func createHabit(from draft: CreateHabitDraft) throws -> UUID {
        try performWrite { context in
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

            try context.save()
            return habitID
        }
    }

    func completeHabitToday(id: UUID) throws {
        try performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }

            let today = Calendar.current.startOfDay(for: Date())
            if try fetchCompletion(for: id, on: today, in: context) != nil {
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

    func removeHabitCompletionToday(id: UUID) throws {
        try performWrite { context in
            let today = Calendar.current.startOfDay(for: Date())
            guard let completion = try fetchCompletion(for: id, on: today, in: context) else { return }

            context.delete(completion)
            try context.save()
        }
    }

    func deleteHabit(id: UUID) throws {
        try performWrite { context in
            guard let habit = try fetchHabit(id: id, in: context) else { return }

            context.delete(habit)
            try context.save()
        }
    }

    func moveHabits(of type: HabitType, from offsets: IndexSet, to destination: Int) throws {
        try performWrite { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            request.predicate = NSPredicate(format: "typeRaw == %@", type.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

            let habits = reorderedItems(try context.fetch(request), from: offsets, to: destination)

            for (index, habit) in habits.enumerated() {
                habit.setValue(Int32(index), forKey: "sortOrder")
            }

            try context.save()
        }
    }

    func updateHabit(from draft: EditHabitDraft) throws {
        try performWrite { context in
            guard let habit = try fetchHabit(id: draft.id, in: context) else { return }

            habit.setValue(draft.trimmedName, forKey: "name")
            habit.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            habit.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            habit.setValue(Date(), forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: habit)
            let currentWeekdayMask = Int(currentSchedule?.value(forKey: "weekdayMask") as? Int16 ?? 0)
            if currentWeekdayMask != draft.scheduleDays.rawValue {
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "habitID")
                schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
                schedule.setValue(Calendar.current.startOfDay(for: Date()), forKey: "effectiveFrom")
                schedule.setValue(Date(), forKey: "createdAt")
                schedule.setValue(Int32((currentSchedule?.value(forKey: "version") as? Int32 ?? 0) + 1), forKey: "version")
                schedule.setValue(habit, forKey: "habit")
            }

            let existingCompletionObjects = ((habit.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? [])
            let startDate = Calendar.current.startOfDay(for: draft.startDate)
            let today = Calendar.current.startOfDay(for: Date())
            let editableStart = max(startDate, Calendar.current.date(byAdding: .day, value: -29, to: today) ?? startDate)
            let editableDates = stride(from: 0, through: 29, by: 1).compactMap {
                Calendar.current.date(byAdding: .day, value: -$0, to: today).map { Calendar.current.startOfDay(for: $0) }
            }.filter { $0 >= editableStart && $0 <= today }

            let editableSet = Set(editableDates)
            let existingByDay = Dictionary(uniqueKeysWithValues: existingCompletionObjects.compactMap { object -> (Date, NSManagedObject)? in
                guard let localDate = object.value(forKey: "localDate") as? Date else { return nil }
                return (Calendar.current.startOfDay(for: localDate), object)
            })

            for day in editableSet {
                let shouldExist = draft.completedDays.contains(day)
                let existing = existingByDay[day]

                if shouldExist, existing == nil {
                    let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
                    completion.setValue(UUID(), forKey: "id")
                    completion.setValue(draft.id, forKey: "habitID")
                    completion.setValue(day, forKey: "localDate")
                    completion.setValue(CompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                    completion.setValue(Date(), forKey: "createdAt")
                    completion.setValue(habit, forKey: "habit")
                } else if !shouldExist, let existing {
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

    private func performWrite(_ work: (NSManagedObjectContext) throws -> Void) throws {
        let context = makeWriteContext()
        var thrownError: Error?

        context.performAndWait {
            do {
                try work(context)
            } catch {
                context.rollback()
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }

        refreshReadContext()
    }

    private func performWrite<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        let context = makeWriteContext()
        var result: T?
        var thrownError: Error?

        context.performAndWait {
            do {
                result = try work(context)
            } catch {
                context.rollback()
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }

        refreshReadContext()

        guard let result else {
            throw HabitRepositoryError.internalFailure
        }

        return result
    }

    private func refreshReadContext() {
        readContext.performAndWait {
            readContext.refreshAllObjects()
        }
    }

    private func loadCompletions(for habitObject: NSManagedObject, habitID: UUID) -> [HabitCompletion] {
        let completions = (habitObject.mutableSetValue(forKey: "completions").allObjects as? [NSManagedObject]) ?? []
        return completions.compactMap { completionObject in
            guard
                let completionID = completionObject.value(forKey: "id") as? UUID,
                let localDate = completionObject.value(forKey: "localDate") as? Date,
                let sourceRaw = completionObject.value(forKey: "sourceRaw") as? String,
                let source = CompletionSource(rawValue: sourceRaw),
                let createdAt = completionObject.value(forKey: "createdAt") as? Date
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

    private func loadSchedules(for habitObject: NSManagedObject, habitID: UUID) -> [HabitScheduleVersion] {
        let schedules = (habitObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        return schedules
            .compactMap { scheduleObject -> HabitScheduleVersion? in
                guard
                    let scheduleID = scheduleObject.value(forKey: "id") as? UUID,
                    let effectiveFrom = scheduleObject.value(forKey: "effectiveFrom") as? Date,
                    let createdAt = scheduleObject.value(forKey: "createdAt") as? Date
                else {
                    return nil
                }

                let weekdayMask = Int(scheduleObject.value(forKey: "weekdayMask") as? Int16 ?? 0)
                let version = Int(scheduleObject.value(forKey: "version") as? Int32 ?? 1)

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

    private func loadLatestScheduleObject(for habitObject: NSManagedObject) -> NSManagedObject? {
        let schedules = (habitObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        return schedules.sorted {
            let lhs = $0.value(forKey: "effectiveFrom") as? Date ?? .distantPast
            let rhs = $1.value(forKey: "effectiveFrom") as? Date ?? .distantPast
            if lhs != rhs {
                return lhs > rhs
            }

            let lhsVersion = $0.value(forKey: "version") as? Int32 ?? 0
            let rhsVersion = $1.value(forKey: "version") as? Int32 ?? 0
            if lhsVersion != rhsVersion {
                return lhsVersion > rhsVersion
            }

            let lhsCreatedAt = $0.value(forKey: "createdAt") as? Date ?? .distantPast
            let rhsCreatedAt = $1.value(forKey: "createdAt") as? Date ?? .distantPast
            return lhsCreatedAt > rhsCreatedAt
        }.first
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
}

private extension Calendar {
    func weekdaySet(for date: Date) -> WeekdaySet {
        switch component(.weekday, from: date) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }
}
