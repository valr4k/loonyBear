import Foundation

enum DayCountFormatter {
    private static let daysPerMonth = 30
    private static let daysPerYear = 365

    static func compactDurationString(for totalDays: Int) -> String {
        guard totalDays > 0 else { return "0 days" }

        var remainingDays = totalDays
        let years = remainingDays / daysPerYear
        remainingDays %= daysPerYear

        let months = remainingDays / daysPerMonth
        remainingDays %= daysPerMonth

        switch (years, months, remainingDays) {
        case let (y, m, d) where y > 0:
            return "\(y)yr \(m)mo \(d)d"
        case let (_, m, d) where m > 0:
            return "\(m)mo \(d)d"
        default:
            return remainingDays == 1 ? "1 day" : "\(remainingDays) days"
        }
    }
}
