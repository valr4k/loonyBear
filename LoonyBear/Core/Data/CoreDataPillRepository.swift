import CoreData
import Foundation

struct CoreDataPillRepository: PillRepository {
    private let readContext: NSManagedObjectContext
    private let makeWriteContext: () -> NSManagedObjectContext

    init(
        context: NSManagedObjectContext,
        makeWriteContext: @escaping () -> NSManagedObjectContext
    ) {
        readContext = context
        self.makeWriteContext = makeWriteContext
    }

    func fetchDashboardPills() -> [PillCardProjection] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Pill")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]

        let pills = (try? readContext.fetch(request)) ?? []
        let today = Calendar.current.startOfDay(for: Date())

        return pills.compactMap { pillObject in
            guard
                let id = pillObject.value(forKey: "id") as? UUID,
                let name = pillObject.value(forKey: "name") as? String,
                let dosage = pillObject.value(forKey: "dosage") as? String
            else {
                return nil
            }

            let latestSchedule = loadSchedules(for: pillObject, pillID: id).sorted(by: isNewerSchedule).first
            let intakes = loadIntakes(for: pillObject, pillID: id)
            let isTakenToday = intakes.contains { Calendar.current.isDate($0.localDate, inSameDayAs: today) }
            let reminderEnabled = pillObject.value(forKey: "reminderEnabled") as? Bool ?? false
            let reminderHour = Int(pillObject.value(forKey: "reminderHour") as? Int16 ?? 0)
            let reminderMinute = Int(pillObject.value(forKey: "reminderMinute") as? Int16 ?? 0)
            let reminderText = reminderEnabled ? ReminderTime(hour: reminderHour, minute: reminderMinute).formatted : nil
            let isScheduledToday = latestSchedule?.weekdays.contains(Calendar.current.weekdaySet(for: today)) ?? false

            return PillCardProjection(
                id: id,
                name: name,
                dosage: dosage,
                scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
                totalTakenDays: Set(intakes.map { Calendar.current.startOfDay(for: $0.localDate) }).count,
                reminderText: reminderText,
                reminderHour: reminderEnabled ? reminderHour : nil,
                reminderMinute: reminderEnabled ? reminderMinute : nil,
                isReminderScheduledToday: isScheduledToday,
                isScheduledToday: isScheduledToday,
                isTakenToday: isTakenToday,
                sortOrder: Int(pillObject.value(forKey: "sortOrder") as? Int32 ?? 0)
            )
        }
        .sorted(by: pillDashboardSort)
    }

    func fetchPillDetails(id: UUID) -> PillDetailsProjection? {
        guard let pillObject = try? fetchPill(id: id, in: readContext) else { return nil }
        guard
            let name = pillObject.value(forKey: "name") as? String,
            let dosage = pillObject.value(forKey: "dosage") as? String,
            let startDate = pillObject.value(forKey: "startDate") as? Date
        else {
            return nil
        }

        let schedules = loadSchedules(for: pillObject, pillID: id)
        let latestSchedule = schedules.sorted(by: isNewerSchedule).first
        let intakes = loadIntakes(for: pillObject, pillID: id)
        let reminderEnabled = pillObject.value(forKey: "reminderEnabled") as? Bool ?? false
        let reminderHour = Int(pillObject.value(forKey: "reminderHour") as? Int16 ?? 0)
        let reminderMinute = Int(pillObject.value(forKey: "reminderMinute") as? Int16 ?? 0)

        return PillDetailsProjection(
            id: id,
            name: name,
            dosage: dosage,
            details: pillObject.value(forKey: "detailsText") as? String,
            startDate: startDate,
            scheduleSummary: latestSchedule?.weekdays.summary ?? "No days selected",
            scheduleDays: latestSchedule?.weekdays ?? .daily,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderEnabled ? ReminderTime(hour: reminderHour, minute: reminderMinute) : nil,
            totalTakenDays: Set(intakes.map { Calendar.current.startOfDay(for: $0.localDate) }).count,
            takenDays: Set(intakes.map { Calendar.current.startOfDay(for: $0.localDate) })
        )
    }

    func createPill(from draft: PillDraft) throws -> UUID {
        try performWrite { context in
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
        }
    }

    func updatePill(from draft: EditPillDraft) throws {
        try performWrite { context in
            guard let pill = try fetchPill(id: draft.id, in: context) else { return }

            pill.setValue(draft.trimmedName, forKey: "name")
            pill.setValue(draft.trimmedDosage, forKey: "dosage")
            pill.setValue(draft.normalizedDetails, forKey: "detailsText")
            pill.setValue(draft.reminderEnabled, forKey: "reminderEnabled")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.hour) : nil, forKey: "reminderHour")
            pill.setValue(draft.reminderEnabled ? Int16(draft.reminderTime.minute) : nil, forKey: "reminderMinute")
            pill.setValue(Date(), forKey: "updatedAt")

            let currentSchedule = loadLatestScheduleObject(for: pill)
            let currentWeekdayMask = Int(currentSchedule?.value(forKey: "weekdayMask") as? Int16 ?? 0)
            if currentWeekdayMask != draft.scheduleDays.rawValue {
                let schedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
                schedule.setValue(UUID(), forKey: "id")
                schedule.setValue(draft.id, forKey: "pillID")
                schedule.setValue(Int16(draft.scheduleDays.rawValue), forKey: "weekdayMask")
                schedule.setValue(Calendar.current.startOfDay(for: Date()), forKey: "effectiveFrom")
                schedule.setValue(Date(), forKey: "createdAt")
                schedule.setValue(Int32((currentSchedule?.value(forKey: "version") as? Int32 ?? 0) + 1), forKey: "version")
                schedule.setValue(pill, forKey: "pill")
            }

            let existingIntakeObjects = ((pill.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? [])
            let startDate = Calendar.current.startOfDay(for: draft.startDate)
            let today = Calendar.current.startOfDay(for: Date())
            let editableStart = max(startDate, Calendar.current.date(byAdding: .day, value: -29, to: today) ?? startDate)
            let editableDates = stride(from: 0, through: 29, by: 1).compactMap {
                Calendar.current.date(byAdding: .day, value: -$0, to: today).map { Calendar.current.startOfDay(for: $0) }
            }.filter { $0 >= editableStart && $0 <= today }

            let editableSet = Set(editableDates)
            let existingByDay = Dictionary(uniqueKeysWithValues: existingIntakeObjects.compactMap { object -> (Date, NSManagedObject)? in
                guard let localDate = object.value(forKey: "localDate") as? Date else { return nil }
                return (Calendar.current.startOfDay(for: localDate), object)
            })

            for day in editableSet {
                let shouldExist = draft.takenDays.contains(day)
                let existing = existingByDay[day]

                if shouldExist, existing == nil {
                    let intake = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
                    intake.setValue(UUID(), forKey: "id")
                    intake.setValue(draft.id, forKey: "pillID")
                    intake.setValue(day, forKey: "localDate")
                    intake.setValue(PillCompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
                    intake.setValue(Date(), forKey: "createdAt")
                    intake.setValue(pill, forKey: "pill")
                } else if !shouldExist, let existing {
                    context.delete(existing)
                }
            }

            try context.save()
        }
    }

    func deletePill(id: UUID) throws {
        try performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            context.delete(pill)
            try context.save()
        }
    }

    func markTakenToday(id: UUID) throws {
        try performWrite { context in
            guard let pill = try fetchPill(id: id, in: context) else { return }
            let today = Calendar.current.startOfDay(for: Date())
            if try fetchIntake(for: id, on: today, in: context) != nil { return }

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

    func unmarkTakenToday(id: UUID) throws {
        try performWrite { context in
            let today = Calendar.current.startOfDay(for: Date())
            guard let intake = try fetchIntake(for: id, on: today, in: context) else { return }
            context.delete(intake)
            try context.save()
        }
    }

    func movePills(from offsets: IndexSet, to destination: Int) throws {
        try performWrite { context in
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
            throw PillRepositoryError.internalFailure
        }

        return result
    }

    private func refreshReadContext() {
        readContext.performAndWait {
            readContext.refreshAllObjects()
        }
    }

    private func loadIntakes(for pillObject: NSManagedObject, pillID: UUID) -> [PillIntake] {
        let intakes = (pillObject.mutableSetValue(forKey: "intakes").allObjects as? [NSManagedObject]) ?? []
        return intakes.compactMap { intakeObject in
            guard
                let intakeID = intakeObject.value(forKey: "id") as? UUID,
                let localDate = intakeObject.value(forKey: "localDate") as? Date,
                let sourceRaw = intakeObject.value(forKey: "sourceRaw") as? String,
                let source = PillCompletionSource(rawValue: sourceRaw),
                let createdAt = intakeObject.value(forKey: "createdAt") as? Date
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

    private func loadSchedules(for pillObject: NSManagedObject, pillID: UUID) -> [PillScheduleVersion] {
        let schedules = (pillObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
        return schedules.compactMap { scheduleObject in
            guard
                let scheduleID = scheduleObject.value(forKey: "id") as? UUID,
                let effectiveFrom = scheduleObject.value(forKey: "effectiveFrom") as? Date,
                let createdAt = scheduleObject.value(forKey: "createdAt") as? Date
            else {
                return nil
            }

            let weekdayMask = Int(scheduleObject.value(forKey: "weekdayMask") as? Int16 ?? 0)
            let version = Int(scheduleObject.value(forKey: "version") as? Int32 ?? 1)

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

    private func loadLatestScheduleObject(for pillObject: NSManagedObject) -> NSManagedObject? {
        let schedules = (pillObject.mutableSetValue(forKey: "scheduleVersions").allObjects as? [NSManagedObject]) ?? []
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
