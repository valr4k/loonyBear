import CoreData
import Foundation
import Testing

@testable import LoonyBear

@MainActor
struct StartupHealthCheckTests {
    @Test
    func startupHealthCheckCoordinatorSwallowsIntegrityIssuesAndRunsOnlyOnce() async {
        var invocationCount = 0
        let coordinator = AppStartupHealthCheckCoordinator {
            invocationCount += 1
            throw DataIntegrityError(
                operation: "app.startup.healthCheck",
                report: DataIntegrityReport(issues: [
                    DataIntegrityIssue(
                        area: "startup.habitHistory",
                        entityName: "HabitCompletion",
                        objectIdentifier: "duplicate",
                        message: "Duplicate history row detected."
                    ),
                ])
            )
        }

        await coordinator.runIfNeeded()
        await coordinator.runIfNeeded()

        #expect(invocationCount == 1)
    }

    @Test
    func startupHealthCheckFailsOnCorruptedReminderFields() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        let habitID = UUID()

        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Broken reminder", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(Date(timeIntervalSince1970: 0), forKey: "startDate")
        habit.setValue(HabitHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        habit.setValue(true, forKey: "reminderEnabled")
        habit.setValue(nil, forKey: "reminderHour")
        habit.setValue(Int16(30), forKey: "reminderMinute")
        habit.setValue(Date(timeIntervalSince1970: 0), forKey: "createdAt")
        habit.setValue(Date(timeIntervalSince1970: 0), forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        schedule.setValue(UUID(), forKey: "id")
        schedule.setValue(habitID, forKey: "habitID")
        schedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        schedule.setValue(Date(timeIntervalSince1970: 0), forKey: "effectiveFrom")
        schedule.setValue(Date(timeIntervalSince1970: 0), forKey: "createdAt")
        schedule.setValue(Int32(1), forKey: "version")
        schedule.setValue(habit, forKey: "habit")

        try context.save()

        do {
            try AppStartupHealthCheck.run(
                makeContext: persistence.makeBackgroundContext
            )
            Issue.record("Expected startup health check to fail for corrupted reminder fields.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "app.startup.healthCheck")
            #expect(!error.report.isEmpty)
        }
    }

    @Test
    func startupHealthCheckFailsOnCorruptedHistorySource() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 0)
        let habitID = UUID()

        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Walk", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(now, forKey: "startDate")
        habit.setValue(HabitHistoryMode.everyDay.rawValue, forKey: "historyModeRaw")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(now, forKey: "createdAt")
        habit.setValue(now, forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
        completion.setValue(UUID(), forKey: "id")
        completion.setValue(habitID, forKey: "habitID")
        completion.setValue(now, forKey: "localDate")
        completion.setValue("broken-source", forKey: "sourceRaw")
        completion.setValue(now, forKey: "createdAt")
        completion.setValue(habit, forKey: "habit")

        try context.save()

        do {
            try AppStartupHealthCheck.run(
                makeContext: persistence.makeBackgroundContext
            )
            Issue.record("Expected startup health check to fail for corrupted history rows.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "app.startup.healthCheck")
            #expect(error.report.issues.contains { $0.message.contains("invalid sourceRaw") })
        }
    }

    @Test
    func startupHealthCheckFailsOnCorruptedOldScheduleVersions() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 0)
        let later = Date(timeIntervalSince1970: 86_400)
        let invalidMask = Int16(999)

        let habitID = UUID()
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Walk", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(now, forKey: "startDate")
        habit.setValue(HabitHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(now, forKey: "createdAt")
        habit.setValue(now, forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let oldHabitSchedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        oldHabitSchedule.setValue(UUID(), forKey: "id")
        oldHabitSchedule.setValue(habitID, forKey: "habitID")
        oldHabitSchedule.setValue(invalidMask, forKey: "weekdayMask")
        oldHabitSchedule.setValue(now, forKey: "effectiveFrom")
        oldHabitSchedule.setValue(now, forKey: "createdAt")
        oldHabitSchedule.setValue(Int32(1), forKey: "version")
        oldHabitSchedule.setValue(habit, forKey: "habit")

        let latestHabitSchedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        latestHabitSchedule.setValue(UUID(), forKey: "id")
        latestHabitSchedule.setValue(habitID, forKey: "habitID")
        latestHabitSchedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        latestHabitSchedule.setValue(later, forKey: "effectiveFrom")
        latestHabitSchedule.setValue(later, forKey: "createdAt")
        latestHabitSchedule.setValue(Int32(2), forKey: "version")
        latestHabitSchedule.setValue(habit, forKey: "habit")

        let pillID = UUID()
        let pill = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
        pill.setValue(pillID, forKey: "id")
        pill.setValue("Vitamin", forKey: "name")
        pill.setValue("1 pill", forKey: "dosage")
        pill.setValue(Int32(0), forKey: "sortOrder")
        pill.setValue(now, forKey: "startDate")
        pill.setValue(PillHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        pill.setValue(false, forKey: "reminderEnabled")
        pill.setValue(now, forKey: "createdAt")
        pill.setValue(now, forKey: "updatedAt")
        pill.setValue(Int32(1), forKey: "version")

        let oldPillSchedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
        oldPillSchedule.setValue(UUID(), forKey: "id")
        oldPillSchedule.setValue(pillID, forKey: "pillID")
        oldPillSchedule.setValue(invalidMask, forKey: "weekdayMask")
        oldPillSchedule.setValue(now, forKey: "effectiveFrom")
        oldPillSchedule.setValue(now, forKey: "createdAt")
        oldPillSchedule.setValue(Int32(1), forKey: "version")
        oldPillSchedule.setValue(pill, forKey: "pill")

        let latestPillSchedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
        latestPillSchedule.setValue(UUID(), forKey: "id")
        latestPillSchedule.setValue(pillID, forKey: "pillID")
        latestPillSchedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        latestPillSchedule.setValue(later, forKey: "effectiveFrom")
        latestPillSchedule.setValue(later, forKey: "createdAt")
        latestPillSchedule.setValue(Int32(2), forKey: "version")
        latestPillSchedule.setValue(pill, forKey: "pill")

        try context.save()

        do {
            try AppStartupHealthCheck.run(
                makeContext: persistence.makeBackgroundContext
            )
            Issue.record("Expected startup health check to fail for corrupted old schedule rows.")
        } catch let error as DataIntegrityError {
            let weekdayIssues = error.report.issues.filter { $0.message.contains("weekdayMask") }
            #expect(weekdayIssues.count >= 2)
        }
    }

    @Test
    func startupHealthCheckFailsOnCorruptedHistoryRanges() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 0)
        let rangeEnd = Date(timeIntervalSince1970: 86_400 * 2)

        let habitID = UUID()
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Walk", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(now, forKey: "startDate")
        habit.setValue(HabitHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(now, forKey: "createdAt")
        habit.setValue(now, forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let habitSchedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        habitSchedule.setValue(UUID(), forKey: "id")
        habitSchedule.setValue(habitID, forKey: "habitID")
        habitSchedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        habitSchedule.setValue(now, forKey: "effectiveFrom")
        habitSchedule.setValue(now, forKey: "createdAt")
        habitSchedule.setValue(Int32(1), forKey: "version")
        habitSchedule.setValue(habit, forKey: "habit")

        let habitRange = NSEntityDescription.insertNewObject(forEntityName: "HabitHistoryRange", into: context)
        habitRange.setValue(UUID(), forKey: "id")
        habitRange.setValue(habitID, forKey: "habitID")
        habitRange.setValue(now, forKey: "startDate")
        habitRange.setValue(rangeEnd, forKey: "endDate")
        habitRange.setValue(CoreDataHistoryBucketState.positive.storageRaw, forKey: "stateRaw")
        habitRange.setValue(true, forKey: "useScheduleForHistory")
        habitRange.setValue(ScheduleRule.Kind.weekly.rawValue, forKey: "scheduleKindRaw")
        habitRange.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        habitRange.setValue(Int16(ScheduleRule.defaultIntervalDays), forKey: "intervalDays")
        habitRange.setValue(now, forKey: "anchorDate")
        habitRange.setValue(Int32(99), forKey: "count")
        habitRange.setValue(now, forKey: "createdAt")
        habitRange.setValue(now, forKey: "updatedAt")
        habitRange.setValue(habit, forKey: "habit")

        let pillID = UUID()
        let pill = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
        pill.setValue(pillID, forKey: "id")
        pill.setValue("Vitamin", forKey: "name")
        pill.setValue("1 pill", forKey: "dosage")
        pill.setValue(Int32(0), forKey: "sortOrder")
        pill.setValue(now, forKey: "startDate")
        pill.setValue(PillHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        pill.setValue(false, forKey: "reminderEnabled")
        pill.setValue(now, forKey: "createdAt")
        pill.setValue(now, forKey: "updatedAt")
        pill.setValue(Int32(1), forKey: "version")

        let pillSchedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
        pillSchedule.setValue(UUID(), forKey: "id")
        pillSchedule.setValue(pillID, forKey: "pillID")
        pillSchedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        pillSchedule.setValue(now, forKey: "effectiveFrom")
        pillSchedule.setValue(now, forKey: "createdAt")
        pillSchedule.setValue(Int32(1), forKey: "version")
        pillSchedule.setValue(pill, forKey: "pill")

        let pillRange = NSEntityDescription.insertNewObject(forEntityName: "PillHistoryRange", into: context)
        pillRange.setValue(UUID(), forKey: "id")
        pillRange.setValue(pillID, forKey: "pillID")
        pillRange.setValue(now, forKey: "startDate")
        pillRange.setValue(rangeEnd, forKey: "endDate")
        pillRange.setValue(CoreDataHistoryBucketState.positive.storageRaw, forKey: "stateRaw")
        pillRange.setValue(true, forKey: "useScheduleForHistory")
        pillRange.setValue(ScheduleRule.Kind.weekly.rawValue, forKey: "scheduleKindRaw")
        pillRange.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        pillRange.setValue(Int16(ScheduleRule.defaultIntervalDays), forKey: "intervalDays")
        pillRange.setValue(now, forKey: "anchorDate")
        pillRange.setValue(Int32(99), forKey: "count")
        pillRange.setValue(now, forKey: "createdAt")
        pillRange.setValue(now, forKey: "updatedAt")
        pillRange.setValue(pill, forKey: "pill")

        try context.save()

        do {
            try AppStartupHealthCheck.run(
                makeContext: persistence.makeBackgroundContext
            )
            Issue.record("Expected startup health check to fail for corrupted history range rows.")
        } catch let error as DataIntegrityError {
            #expect(error.report.issues.contains { $0.area == "startup.habitHistoryRanges" })
            #expect(error.report.issues.contains { $0.area == "startup.pillHistoryRanges" })
        }
    }

    @Test
    func startupHealthCheckFailsOnHistoryBucketsWithImpossibleMonthDays() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 0)
        let impossibleFebruaryThirtyFirstMask = Int64(1) << 30

        let habitID = UUID()
        let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
        habit.setValue(habitID, forKey: "id")
        habit.setValue(HabitType.build.rawValue, forKey: "typeRaw")
        habit.setValue("Walk", forKey: "name")
        habit.setValue(Int32(0), forKey: "sortOrder")
        habit.setValue(now, forKey: "startDate")
        habit.setValue(HabitHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        habit.setValue(false, forKey: "reminderEnabled")
        habit.setValue(now, forKey: "createdAt")
        habit.setValue(now, forKey: "updatedAt")
        habit.setValue(Int32(1), forKey: "version")

        let habitSchedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
        habitSchedule.setValue(UUID(), forKey: "id")
        habitSchedule.setValue(habitID, forKey: "habitID")
        habitSchedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        habitSchedule.setValue(now, forKey: "effectiveFrom")
        habitSchedule.setValue(now, forKey: "createdAt")
        habitSchedule.setValue(Int32(1), forKey: "version")
        habitSchedule.setValue(habit, forKey: "habit")

        let habitBucket = NSEntityDescription.insertNewObject(forEntityName: "HabitHistoryBucket", into: context)
        habitBucket.setValue(UUID(), forKey: "id")
        habitBucket.setValue(habitID, forKey: "habitID")
        habitBucket.setValue(Int32(202602), forKey: "yearMonthKey")
        habitBucket.setValue(impossibleFebruaryThirtyFirstMask, forKey: "positiveMask")
        habitBucket.setValue(Int64(0), forKey: "skippedMask")
        habitBucket.setValue(Int64(0), forKey: "archivedMask")
        habitBucket.setValue(Int32(1), forKey: "positiveCount")
        habitBucket.setValue(Int32(0), forKey: "skippedCount")
        habitBucket.setValue(Int32(0), forKey: "archivedCount")
        habitBucket.setValue(now, forKey: "createdAt")
        habitBucket.setValue(now, forKey: "updatedAt")
        habitBucket.setValue(habit, forKey: "habit")

        let pillID = UUID()
        let pill = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
        pill.setValue(pillID, forKey: "id")
        pill.setValue("Vitamin", forKey: "name")
        pill.setValue("1 pill", forKey: "dosage")
        pill.setValue(Int32(0), forKey: "sortOrder")
        pill.setValue(now, forKey: "startDate")
        pill.setValue(PillHistoryMode.scheduleBased.rawValue, forKey: "historyModeRaw")
        pill.setValue(false, forKey: "reminderEnabled")
        pill.setValue(now, forKey: "createdAt")
        pill.setValue(now, forKey: "updatedAt")
        pill.setValue(Int32(1), forKey: "version")

        let pillSchedule = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
        pillSchedule.setValue(UUID(), forKey: "id")
        pillSchedule.setValue(pillID, forKey: "pillID")
        pillSchedule.setValue(Int16(WeekdaySet.daily.rawValue), forKey: "weekdayMask")
        pillSchedule.setValue(now, forKey: "effectiveFrom")
        pillSchedule.setValue(now, forKey: "createdAt")
        pillSchedule.setValue(Int32(1), forKey: "version")
        pillSchedule.setValue(pill, forKey: "pill")

        let pillBucket = NSEntityDescription.insertNewObject(forEntityName: "PillHistoryBucket", into: context)
        pillBucket.setValue(UUID(), forKey: "id")
        pillBucket.setValue(pillID, forKey: "pillID")
        pillBucket.setValue(Int32(202602), forKey: "yearMonthKey")
        pillBucket.setValue(impossibleFebruaryThirtyFirstMask, forKey: "positiveMask")
        pillBucket.setValue(Int64(0), forKey: "skippedMask")
        pillBucket.setValue(Int64(0), forKey: "archivedMask")
        pillBucket.setValue(Int32(1), forKey: "positiveCount")
        pillBucket.setValue(Int32(0), forKey: "skippedCount")
        pillBucket.setValue(Int32(0), forKey: "archivedCount")
        pillBucket.setValue(now, forKey: "createdAt")
        pillBucket.setValue(now, forKey: "updatedAt")
        pillBucket.setValue(pill, forKey: "pill")

        try context.save()

        do {
            try AppStartupHealthCheck.run(
                makeContext: persistence.makeBackgroundContext
            )
            Issue.record("Expected startup health check to fail for corrupted history bucket rows.")
        } catch let error as DataIntegrityError {
            #expect(error.report.issues.contains { $0.area == "startup.habitHistoryBuckets" })
            #expect(error.report.issues.contains { $0.area == "startup.pillHistoryBuckets" })
        }
    }
}
