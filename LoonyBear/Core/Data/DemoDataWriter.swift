import CoreData
import Foundation

enum DemoDataWriter {
    static func seedIfNeeded(into context: NSManagedObjectContext, clock: AppClock = AppClock()) {
        let calendar = clock.calendar
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Habit")
        request.fetchLimit = 1

        let existingCount = (try? context.count(for: request)) ?? 0
        guard existingCount == 0 else { return }

        let now = clock.now()
        let habits: [(HabitType, String, WeekdaySet, Int)] = [
            (.build, "Morning walk", .daily, 0),
            (.build, "Read 10 pages", .weekdays, 1),
            (.quit, "No sugar drinks", .daily, 0),
        ]

        for (type, name, weekdays, sortOrder) in habits {
            let habit = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
            let habitID = UUID()

            habit.setValue(habitID, forKey: "id")
            habit.setValue(type.rawValue, forKey: "typeRaw")
            habit.setValue(name, forKey: "name")
            habit.setValue(Int32(sortOrder), forKey: "sortOrder")
            habit.setValue(calendar.startOfDay(for: now), forKey: "startDate")
            habit.setValue(false, forKey: "isArchived")
            habit.setValue(false, forKey: "reminderEnabled")
            habit.setValue(now, forKey: "createdAt")
            habit.setValue(now, forKey: "updatedAt")
            habit.setValue(Int32(1), forKey: "version")

            let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
            schedule.setValue(UUID(), forKey: "id")
            schedule.setValue(habitID, forKey: "habitID")
            schedule.setValue(Int16(weekdays.rawValue), forKey: "weekdayMask")
            schedule.setValue(calendar.startOfDay(for: now), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(habit, forKey: "habit")

            _ = try? CoreDataHistoryBucketSupport.setState(
                owner: habit,
                ownerID: habitID,
                localDate: calendar.startOfDay(for: now),
                state: .positive,
                bucketEntityName: "HabitHistoryBucket",
                ownerKey: "habitID",
                ownerRelationshipKey: "habit",
                legacyEntityName: "HabitCompletion",
                in: context,
                calendar: calendar,
                now: now
            )
        }

        try? context.save()
    }
}
