import CoreData
import Foundation
import UserNotifications

enum EventBadgeNotificationSupport {
    static let identifierPrefix = "event_badge_"

    static func fetchEvents(context: NSManagedObjectContext, calendar: Calendar) throws -> [EventCardProjection] {
        try NotificationConfigurationSupport.fetchConfigurations(
            entityName: "Event", operation: "notification.event.badge", context: context
        ) { object, report in
            guard let id = object.uuidValue(forKey: "id"),
                  let name = object.stringValue(forKey: "name"),
                  let rawMode = object.stringValue(forKey: "modeRaw"), let mode = EventMode(rawValue: rawMode),
                  let storedDate = object.dateValue(forKey: "eventDate") else {
                report.append(area: "event.badge", entityName: object.entityName, object: object, message: "Event is missing required fields.")
                return nil
            }
            let dateKey = object.stringValue(forKey: "dateKey") ?? EventLocalDate.legacyKey(for: storedDate, calendar: calendar)
            guard let date = EventLocalDate.date(for: dateKey, calendar: calendar) else {
                report.append(area: "event.badge", entityName: object.entityName, object: object, message: "Event has an invalid calendar date.")
                return nil
            }
            return EventCardProjection(id: id, name: name, mode: mode, date: date,
                sortOrder: Int(object.int32Value(forKey: "sortOrder")), acknowledgedAt: object.dateValue(forKey: "acknowledgedAt"))
        }
    }

    static func requests(events: [EventCardProjection], habits: [HabitReminderConfiguration],
                         pills: [PillReminderConfiguration], now: Date, calendar: Calendar,
                         limit: Int) -> [UNNotificationRequest] {
        let dates = Set(events.filter { $0.mode == .countdown && $0.acknowledgedAt == nil }
            .map { calendar.startOfDay(for: $0.date) }.filter { $0 > now }).sorted()
        return dates.prefix(max(0, limit)).map { date in
            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: ProjectedBadgeCountCalculator.projectedOverdueCount(
                at: date, habits: habits, pills: pills, events: events, calendar: calendar))
            content.userInfo = ["type": "event.badge"]
            // No timeZone on the trigger: midnight follows the device's local zone.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            return UNNotificationRequest(identifier: identifierPrefix + EventLocalDate.key(for: date, calendar: calendar),
                content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }
    }
}
