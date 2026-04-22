import Foundation

struct AppClock {
    let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = { Date() }
    ) {
        self.calendar = calendar
        nowProvider = now
    }

    func now() -> Date {
        nowProvider()
    }

    static let live = AppClock()
}
