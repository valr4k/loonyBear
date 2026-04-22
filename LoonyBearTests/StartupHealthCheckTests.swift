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

        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillNotificationService = PillNotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        do {
            try AppStartupHealthCheck.run(
                context: context,
                habitRepository: repository,
                pillRepository: pillRepository,
                habitNotificationService: notificationService,
                pillNotificationService: pillNotificationService
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

        let repository = CoreDataHabitRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillRepository = CoreDataPillRepository(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let notificationService = NotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )
        let pillNotificationService = PillNotificationService(
            context: context,
            makeWriteContext: persistence.makeBackgroundContext
        )

        do {
            try AppStartupHealthCheck.run(
                context: context,
                habitRepository: repository,
                pillRepository: pillRepository,
                habitNotificationService: notificationService,
                pillNotificationService: pillNotificationService
            )
            Issue.record("Expected startup health check to fail for corrupted history rows.")
        } catch let error as DataIntegrityError {
            #expect(error.operation == "app.startup.healthCheck")
            #expect(error.report.issues.contains { $0.message.contains("invalid sourceRaw") })
        }
    }
}
