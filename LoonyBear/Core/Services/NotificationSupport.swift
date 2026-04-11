import CoreData
import Foundation
import UserNotifications

extension Notification.Name {
    static let habitStoreDidChange = Notification.Name("habit_store_did_change")
    static let pillStoreDidChange = Notification.Name("pill_store_did_change")
    static let openMyHabitsTab = Notification.Name("open_my_habits_tab")
    static let openMyPillsTab = Notification.Name("open_my_pills_tab")
}

struct NotificationStoreContext {
    let readContext: NSManagedObjectContext
    let makeWriteContext: () -> NSManagedObjectContext

    func performRead<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>?
        readContext.performAndWait {
            do {
                result = .success(try work(readContext))
            } catch {
                readContext.rollback()
                result = .failure(error)
            }
        }

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw DataIntegrityError(
                operation: "notification.performRead",
                report: DataIntegrityReport(issues: [])
            )
        }
    }

    func performWrite<T>(_ work: (NSManagedObjectContext) throws -> T, refreshReadContext: Bool = true) -> T? {
        let context = makeWriteContext()
        var result: Result<T, Error>?

        context.performAndWait {
            do {
                result = .success(try work(context))
            } catch {
                context.rollback()
                result = .failure(error)
            }
        }

        switch result {
        case .success(let value):
            if refreshReadContext {
                self.refreshReadContext()
            }
            return value
        case .failure, .none:
            return nil
        }
    }

    func refreshReadContext() {
        readContext.performAndWait {
            readContext.refreshAllObjects()
        }
    }
}

enum LocalNotificationSupport {
    static func ensureAuthorizationIfNeeded(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }

    static func cleanupStaleDeliveredNotifications(
        center: UNUserNotificationCenter,
        calendar: Calendar,
        today: Date = Date()
    ) {
        let normalizedToday = calendar.startOfDay(for: today)
        center.getDeliveredNotifications { notifications in
            let staleIdentifiers = notifications.compactMap { notification -> String? in
                let notificationDay = calendar.startOfDay(for: notification.date)
                return notificationDay < normalizedToday ? notification.request.identifier : nil
            }
            center.removeDeliveredNotifications(withIdentifiers: staleIdentifiers)
        }
    }

    static func removeDeliveredAggregatedNotifications(
        center: UNUserNotificationCenter,
        calendar: Calendar,
        type: String,
        on localDate: Date
    ) {
        let normalizedDay = calendar.startOfDay(for: localDate)

        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                guard notification.request.content.userInfo["type"] as? String == type else {
                    return nil
                }

                let deliveredDay = calendar.startOfDay(for: notification.date)
                return deliveredDay == normalizedDay ? notification.request.identifier : nil
            }

            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    static func removePendingNotifications(
        center: UNUserNotificationCenter,
        prefix: String,
        completion: @escaping () -> Void
    ) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            completion()
        }
    }

    static func removePendingNotifications(
        center: UNUserNotificationCenter,
        matching predicate: @escaping (UNNotificationRequest) -> Bool,
        completion: @escaping () -> Void
    ) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter(predicate)
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            completion()
        }
    }

    static func timestampString(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d%02d%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    static func localDateIdentifier(for localDate: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: localDate))
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func parseLocalDateIdentifier(_ identifier: String, calendar: Calendar) -> Date? {
        guard identifier.count == 8 else { return nil }
        guard let year = Int(identifier.prefix(4)),
              let month = Int(identifier.dropFirst(4).prefix(2)),
              let day = Int(identifier.suffix(2)) else {
            return nil
        }

        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }
}
