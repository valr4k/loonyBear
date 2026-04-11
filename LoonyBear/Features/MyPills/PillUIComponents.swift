import SwiftUI

enum PillRowPosition {
    case single
    case first
    case middle
    case last

    @ViewBuilder
    var backgroundShape: some InsettableShape {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
    }

    private var cornerRadii: RectangleCornerRadii {
        switch self {
        case .single:
            .init(topLeading: 22, bottomLeading: 22, bottomTrailing: 22, topTrailing: 22)
        case .first:
            .init(topLeading: 22, bottomLeading: 0, bottomTrailing: 0, topTrailing: 22)
        case .middle:
            .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
        case .last:
            .init(topLeading: 0, bottomLeading: 22, bottomTrailing: 22, topTrailing: 0)
        }
    }
}

struct PillCardView: View {
    let pill: PillCardProjection
    let position: PillRowPosition
    let currentTime: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pill.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(pill.dosage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(pill.scheduleSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Taken for: \(DayCountFormatter.compactDurationString(for: pill.totalTakenDays))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .overlay(alignment: .topTrailing) {
                    if let reminderText = pill.reminderText {
                        Text(reminderText)
                            .font(.caption)
                            .foregroundStyle(isReminderOverdueToday ? .red : .secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .overlay(alignment: .trailing) {
                    if pill.isTakenToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                    } else if pill.isSkippedToday {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                }
            .frame(width: 44)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            position.backgroundShape
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var isReminderOverdueToday: Bool {
        guard pill.isReminderScheduledToday else { return false }
        guard !pill.isTakenToday else { return false }
        guard !pill.isSkippedToday else { return false }
        guard let reminderHour = pill.reminderHour, let reminderMinute = pill.reminderMinute else {
            return false
        }

        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: currentTime)
        guard let scheduledDateTime = calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: normalizedDay
        ) else {
            return false
        }

        return scheduledDateTime < currentTime
    }
}

struct PillHistoryCalendarView: View {
    private let calendarSpacing: CGFloat = 6
    private let weekdayRowHeight: CGFloat = 20
    let month: Date
    let editableDays: Set<Date>
    @Binding var takenDays: Set<Date>
    @Binding var skippedDays: Set<Date>
    let availableMonths: [Date]
    let onMonthChange: (Date) -> Void
    @State private var availableWidth: CGFloat = 0
    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        changeMonth(step: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBackward)
                    .foregroundStyle(canGoBackward ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))

                    Button {
                        changeMonth(step: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
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

                ForEach(dayRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: calendarSpacing) {
                        ForEach(dayRows[rowIndex], id: \.id) { day in
                            Group {
                                if let date = day.date {
                                    PillCalendarDayView(
                                        dayNumber: calendar.component(.day, from: date),
                                        style: dayStyle(for: date),
                                        cellSize: cellSize
                                    )
                                    .contentShape(Circle())
                                    .allowsHitTesting(editableDays.contains(date))
                                    .onTapGesture {
                                        toggle(date)
                                    }
                                } else {
                                    Color.clear
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: PillCalendarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(PillCalendarWidthPreferenceKey.self) { width in
            availableWidth = width
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -50 {
                        changeMonth(step: 1)
                    } else if value.translation.width > 50 {
                        changeMonth(step: -1)
                    }
                }
        )
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Calendar.autoupdatingCurrent.locale ?? Locale.autoupdatingCurrent
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        return (Array(symbols[1...]) + [symbols[0]]).map { $0.uppercased() }
    }

    private var days: [PillCalendarDayCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthInterval.start),
            let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else {
            return []
        }

        var result: [PillCalendarDayCell] = []
        var cursor = calendar.startOfDay(for: firstWeekInterval.start)
        let end = calendar.startOfDay(for: lastWeekInterval.end)

        while cursor < end {
            let isInDisplayedMonth = calendar.isDate(cursor, equalTo: month, toGranularity: .month)
            result.append(PillCalendarDayCell(id: cursor, date: isInDisplayedMonth ? cursor : nil))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    private var cellSize: CGFloat {
        guard availableWidth > 0 else { return 40 }
        let raw = floor((availableWidth - calendarSpacing * 6) / 7)
        return min(max(raw, 35), 40)
    }

    private var dayRows: [[PillCalendarDayCell]] {
        days.chunked(into: 7)
    }

    private var canGoBackward: Bool {
        guard let first = availableMonths.first else { return false }
        return month > first
    }

    private var canGoForward: Bool {
        guard let last = availableMonths.last else { return false }
        return month < last
    }

    private func toggle(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        guard editableDays.contains(normalizedDate) else { return }

        let currentSelection: EditableHistorySelection
        switch dayStyle(for: normalizedDate) {
        case .available:
            currentSelection = .none
        case .taken:
            currentSelection = .positive
        case .skipped:
            currentSelection = .skipped
        case .disabled:
            return
        }

        let nextSelection = EditableHistoryStateMachine.nextSelection(
            current: currentSelection,
            for: normalizedDate,
            today: Date(),
            calendar: calendar
        )

        takenDays.remove(normalizedDate)
        skippedDays.remove(normalizedDate)

        switch nextSelection {
        case .none:
            break
        case .positive:
            takenDays.insert(normalizedDate)
        case .skipped:
            skippedDays.insert(normalizedDate)
        }
    }

    private func changeMonth(step: Int) {
        guard let currentIndex = availableMonths.firstIndex(of: month) else { return }
        let nextIndex = currentIndex + step
        guard availableMonths.indices.contains(nextIndex) else { return }
        onMonthChange(availableMonths[nextIndex])
    }

    private func dayStyle(for date: Date) -> PillCalendarDayStyle {
        guard editableDays.contains(date) else {
            return .disabled
        }
        if takenDays.contains(date) {
            return .taken
        } else if skippedDays.contains(date) {
            return .skipped
        } else {
            return .available
        }
    }
}

struct PillReadOnlyMonthCalendarView: View {
    private let calendarSpacing: CGFloat = 6
    private let weekdayRowHeight: CGFloat = 20
    let month: Date
    let takenDays: Set<Date>
    let skippedDays: Set<Date>
    let availableMonths: [Date]
    let onMonthChange: (Date) -> Void
    @State private var availableWidth: CGFloat = 0
    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        changeMonth(step: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBackward)
                    .foregroundStyle(canGoBackward ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))

                    Button {
                        changeMonth(step: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
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

                ForEach(dayRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: calendarSpacing) {
                        ForEach(dayRows[rowIndex], id: \.id) { day in
                            if let date = day.date {
                                PillReadOnlyCalendarDayView(
                                    dayNumber: calendar.component(.day, from: date),
                                    style: dayStyle(for: date),
                                    cellSize: cellSize
                                )
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: PillCalendarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(PillCalendarWidthPreferenceKey.self) { width in
            availableWidth = width
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -50 {
                        changeMonth(step: 1)
                    } else if value.translation.width > 50 {
                        changeMonth(step: -1)
                    }
                }
        )
    }

    private var cellSize: CGFloat {
        guard availableWidth > 0 else { return 40 }
        let raw = floor((availableWidth - calendarSpacing * 6) / 7)
        return min(max(raw, 35), 40)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Calendar.autoupdatingCurrent.locale ?? Locale.autoupdatingCurrent
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        return (Array(symbols[1...]) + [symbols[0]]).map { $0.uppercased() }
    }

    private var days: [PillCalendarDayCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthInterval.start),
            let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else {
            return []
        }

        var result: [PillCalendarDayCell] = []
        var cursor = calendar.startOfDay(for: firstWeekInterval.start)
        let end = calendar.startOfDay(for: lastWeekInterval.end)

        while cursor < end {
            let isInDisplayedMonth = calendar.isDate(cursor, equalTo: month, toGranularity: .month)
            result.append(PillCalendarDayCell(id: cursor, date: isInDisplayedMonth ? cursor : nil))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    private var dayRows: [[PillCalendarDayCell]] {
        days.chunked(into: 7)
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

    private func dayStyle(for date: Date) -> PillReadOnlyDayStyle {
        let normalizedDate = calendar.startOfDay(for: date)
        if takenDays.contains(normalizedDate) {
            return .taken
        }
        if skippedDays.contains(normalizedDate) {
            return .skipped
        }
        return .disabled
    }
}

private struct PillCalendarDayCell: Identifiable {
    let id: Date
    let date: Date?
}

private struct PillCalendarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum PillCalendarDayStyle {
    case available
    case taken
    case skipped
    case disabled
}

private struct PillCalendarDayView: View {
    let dayNumber: Int
    let style: PillCalendarDayStyle
    let cellSize: CGFloat

    var body: some View {
        ZStack {
            if style == .taken || style == .skipped {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: markerSize, height: markerSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
                .frame(width: markerSize, height: markerSize)
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var foreground: Color {
        switch style {
        case .taken:
            return .blue
        case .skipped:
            return .red
        case .available:
            return .primary
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .taken:
            return Color(uiColor: .systemBlue).opacity(0.2)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(0.18)
        case .available, .disabled:
            return .clear
        }
    }

    private var markerSize: CGFloat {
        min(cellSize, 40)
    }
}

private enum PillReadOnlyDayStyle {
    case taken
    case skipped
    case disabled
}

private struct PillReadOnlyCalendarDayView: View {
    let dayNumber: Int
    let style: PillReadOnlyDayStyle
    let cellSize: CGFloat

    var body: some View {
        ZStack {
            if style == .taken || style == .skipped {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: markerSize, height: markerSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
                .frame(width: markerSize, height: markerSize)
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var foreground: Color {
        switch style {
        case .taken:
            return .blue
        case .skipped:
            return .red
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .taken:
            return Color(uiColor: .systemBlue).opacity(0.2)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(0.18)
        case .disabled:
            return .clear
        }
    }

    private var markerSize: CGFloat {
        min(cellSize, 40)
    }
}
