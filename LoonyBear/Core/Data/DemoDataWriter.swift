import CoreData
import Foundation

enum DemoDataWriter {
    static func seedIfNeeded(into context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Habit")
        request.fetchLimit = 1

        let existingCount = (try? context.count(for: request)) ?? 0
        guard existingCount == 0 else { return }

        let now = Date()
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
            habit.setValue(Calendar.current.startOfDay(for: now), forKey: "startDate")
            habit.setValue(false, forKey: "reminderEnabled")
            habit.setValue(now, forKey: "createdAt")
            habit.setValue(now, forKey: "updatedAt")
            habit.setValue(Int32(1), forKey: "version")

            let schedule = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
            schedule.setValue(UUID(), forKey: "id")
            schedule.setValue(habitID, forKey: "habitID")
            schedule.setValue(Int16(weekdays.rawValue), forKey: "weekdayMask")
            schedule.setValue(Calendar.current.startOfDay(for: now), forKey: "effectiveFrom")
            schedule.setValue(now, forKey: "createdAt")
            schedule.setValue(Int32(1), forKey: "version")
            schedule.setValue(habit, forKey: "habit")

            let completion = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
            completion.setValue(UUID(), forKey: "id")
            completion.setValue(habitID, forKey: "habitID")
            completion.setValue(Calendar.current.startOfDay(for: now), forKey: "localDate")
            completion.setValue(CompletionSource.manualEdit.rawValue, forKey: "sourceRaw")
            completion.setValue(now, forKey: "createdAt")
            completion.setValue(habit, forKey: "habit")
        }

        try? context.save()
    }
}
