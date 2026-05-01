import SwiftUI

struct MonthCalendarView<DayContent: View>: View {
    private let calendarSpacing: CGFloat = 6
    private let fullMonthWeekCount: CGFloat = 6
    private let weekdayRowHeight: CGFloat = 20

    let month: Date
    let availableMonths: [Date]
    let calendar: Calendar
    let headerSpacing: CGFloat
    let onMonthChange: (Date) -> Void
    let dayContent: (Date, CGFloat) -> DayContent

    @State private var availableWidth: CGFloat = 0

    init(
        month: Date,
        availableMonths: [Date],
        calendar: Calendar = MonthCalendarSupport.defaultCalendar(),
        headerSpacing: CGFloat = 10,
        onMonthChange: @escaping (Date) -> Void,
        @ViewBuilder dayContent: @escaping (Date, CGFloat) -> DayContent
    ) {
        self.month = month
        self.availableMonths = availableMonths
        self.calendar = calendar
        self.headerSpacing = headerSpacing
        self.onMonthChange = onMonthChange
        self.dayContent = dayContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))

                Spacer()

                HStack(spacing: 28) {
                    Button {
                        changeMonth(step: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(MonthCalendarArrowButtonStyle())
                    .disabled(!canGoBackward)
                    .foregroundStyle(canGoBackward ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))

                    Button {
                        changeMonth(step: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(MonthCalendarArrowButtonStyle())
                    .disabled(!canGoForward)
                    .foregroundStyle(canGoForward ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }

            VStack(spacing: calendarSpacing) {
                HStack(spacing: calendarSpacing) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: cellSize, height: weekdayRowHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: weekRowSpacing) {
                    ForEach(dayRows.indices, id: \.self) { rowIndex in
                        HStack(spacing: calendarSpacing) {
                            ForEach(dayRows[rowIndex], id: \.id) { day in
                                if let date = day.date {
                                    dayContent(date, cellSize)
                                } else {
                                    Color.clear
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(height: fixedDayGridHeight)
            }
        }
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: MonthCalendarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(MonthCalendarWidthPreferenceKey.self) { width in
            availableWidth = width
        }
    }

    private var dayRows: [[MonthCalendarCell]] {
        MonthCalendarSupport.dayRows(for: month, calendar: calendar)
    }

    private var weekdaySymbols: [String] {
        MonthCalendarSupport.weekdaySymbols(calendar: calendar)
    }

    private var cellSize: CGFloat {
        guard availableWidth > 0 else { return 40 }
        let raw = floor((availableWidth - calendarSpacing * 6) / 7)
        return min(max(raw, 35), 40)
    }

    private var fixedDayGridHeight: CGFloat {
        cellSize * fullMonthWeekCount + calendarSpacing * (fullMonthWeekCount - 1)
    }

    private var weekRowSpacing: CGFloat {
        let visibleRows = CGFloat(max(dayRows.count, 1))
        guard visibleRows > 1 else { return 0 }

        let remainingHeight = fixedDayGridHeight - cellSize * visibleRows
        return max(0, remainingHeight / (visibleRows - 1))
    }

    private var canGoBackward: Bool {
        guard let first = availableMonths.first else { return false }
        return month > first
    }

    private var canGoForward: Bool {
        guard let last = availableMonths.last else { return false }
        return month < last
    }

    private func changeMonth(step: Int) {
        guard let currentIndex = availableMonths.firstIndex(of: month) else { return }
        let nextIndex = currentIndex + step
        guard availableMonths.indices.contains(nextIndex) else { return }
        onMonthChange(availableMonths[nextIndex])
    }
}

private struct MonthCalendarArrowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct MonthCalendarCell: Identifiable {
    let id: Date
    let date: Date?
}

enum MonthCalendarSupport {
    static func defaultCalendar() -> Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale.autoupdatingCurrent
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let firstWeekdayIndex = max(calendar.firstWeekday - 1, 0)
        let prefix = Array(symbols[firstWeekdayIndex...])
        let suffix = Array(symbols[..<firstWeekdayIndex])
        return (prefix + suffix).map { $0.uppercased() }
    }

    static func dayRows(for month: Date, calendar: Calendar) -> [[MonthCalendarCell]] {
        days(for: month, calendar: calendar).chunked(into: 7)
    }

    private static func days(for month: Date, calendar: Calendar) -> [MonthCalendarCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthInterval.start),
            let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else {
            return []
        }

        var result: [MonthCalendarCell] = []
        var cursor = calendar.startOfDay(for: firstWeekInterval.start)
        let end = calendar.startOfDay(for: lastWeekInterval.end)

        while cursor < end {
            let isInDisplayedMonth = calendar.isDate(cursor, equalTo: month, toGranularity: .month)
            result.append(MonthCalendarCell(id: cursor, date: isInDisplayedMonth ? cursor : nil))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }
}

private struct MonthCalendarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }

        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start ..< Swift.min(start + size, count)])
        }
    }
}
