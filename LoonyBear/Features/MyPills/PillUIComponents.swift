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
                            .foregroundStyle(.green)
                    } else if pill.isSkippedToday {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
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
    let month: Date
    let editableDays: Set<Date>
    @Binding var selectedDays: Set<Date>
    let availableMonths: [Date]
    let onMonthChange: (Date) -> Void
    @State private var availableWidth: CGFloat = 0
    @State private var transitionDirection: PillCalendarTransitionDirection = .forward
    @State private var renderedMonth: Date
    @State private var outgoingMonth: Date?
    @State private var incomingOffset: CGFloat = 0
    @State private var outgoingOffset: CGFloat = 0

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    init(
        month: Date,
        editableDays: Set<Date>,
        selectedDays: Binding<Set<Date>>,
        availableMonths: [Date],
        onMonthChange: @escaping (Date) -> Void
    ) {
        self.month = month
        self.editableDays = editableDays
        self._selectedDays = selectedDays
        self.availableMonths = availableMonths
        self.onMonthChange = onMonthChange
        _renderedMonth = State(initialValue: month)
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

            ZStack {
                if let outgoingMonth {
                    monthGridContent(for: outgoingMonth)
                        .frame(width: availableWidth == 0 ? nil : availableWidth, alignment: .top)
                        .offset(x: outgoingOffset)
                }

                monthGridContent(for: renderedMonth)
                    .frame(width: availableWidth == 0 ? nil : availableWidth, alignment: .top)
                    .offset(x: incomingOffset)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
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
        .onChange(of: month) {
            animateMonthChange(to: month)
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

    private func monthGridContent(for displayMonth: Date) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(dayRows(for: displayMonth).indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(dayRows(for: displayMonth)[rowIndex]) { day in
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
                                    .frame(maxWidth: .infinity, minHeight: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Calendar.autoupdatingCurrent.locale ?? Locale.autoupdatingCurrent
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        return (Array(symbols[1...]) + [symbols[0]]).map { $0.uppercased() }
    }

    private func days(for displayMonth: Date) -> [PillCalendarDayCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayMonth),
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
            let isInDisplayedMonth = calendar.isDate(cursor, equalTo: displayMonth, toGranularity: .month)
            result.append(PillCalendarDayCell(id: cursor, date: isInDisplayedMonth ? cursor : nil))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    private var cellSize: CGFloat {
        let raw = floor((availableWidth - 8 * 6) / 7)
        return min(max(raw, 35), 40)
    }

    private func dayRows(for displayMonth: Date) -> [[PillCalendarDayCell]] {
        days(for: displayMonth).chunked(into: 7)
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

        if selectedDays.contains(normalizedDate) {
            selectedDays.remove(normalizedDate)
        } else {
            selectedDays.insert(normalizedDate)
        }
    }

    private func changeMonth(step: Int) {
        guard let currentIndex = availableMonths.firstIndex(of: month) else { return }
        let nextIndex = currentIndex + step
        guard availableMonths.indices.contains(nextIndex) else { return }
        transitionDirection = step > 0 ? .forward : .backward
        onMonthChange(availableMonths[nextIndex])
    }

    private func animateMonthChange(to newMonth: Date) {
        guard newMonth != renderedMonth else { return }
        guard availableWidth > 0 else {
            renderedMonth = newMonth
            outgoingMonth = nil
            return
        }

        let width = availableWidth
        let incomingStart = transitionDirection == .forward ? width : -width
        let outgoingEnd = -incomingStart

        outgoingMonth = renderedMonth
        renderedMonth = newMonth
        incomingOffset = incomingStart
        outgoingOffset = 0

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.24)) {
                incomingOffset = 0
                outgoingOffset = outgoingEnd
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard renderedMonth == newMonth else { return }
            outgoingMonth = nil
            incomingOffset = 0
            outgoingOffset = 0
        }
    }

    private func dayStyle(for date: Date) -> PillCalendarDayStyle {
        if editableDays.contains(date), selectedDays.contains(date) {
            return .selected
        } else if editableDays.contains(date) {
            return .available
        } else {
            return .disabled
        }
    }
}

struct PillReadOnlyMonthCalendarView: View {
    let month: Date
    let takenDays: Set<Date>
    let availableMonths: [Date]
    let onMonthChange: (Date) -> Void
    @State private var availableWidth: CGFloat = 0
    @State private var transitionDirection: PillCalendarTransitionDirection = .forward
    @State private var renderedMonth: Date
    @State private var outgoingMonth: Date?
    @State private var incomingOffset: CGFloat = 0
    @State private var outgoingOffset: CGFloat = 0

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    init(
        month: Date,
        takenDays: Set<Date>,
        availableMonths: [Date],
        onMonthChange: @escaping (Date) -> Void
    ) {
        self.month = month
        self.takenDays = takenDays
        self.availableMonths = availableMonths
        self.onMonthChange = onMonthChange
        _renderedMonth = State(initialValue: month)
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

            ZStack {
                if let outgoingMonth {
                    monthGridContent(for: outgoingMonth)
                        .frame(width: availableWidth == 0 ? nil : availableWidth, alignment: .top)
                        .offset(x: outgoingOffset)
                }

                monthGridContent(for: renderedMonth)
                    .frame(width: availableWidth == 0 ? nil : availableWidth, alignment: .top)
                    .offset(x: incomingOffset)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
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
        .onChange(of: month) {
            animateMonthChange(to: month)
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

    private func monthGridContent(for displayMonth: Date) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(dayRows(for: displayMonth).indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(dayRows(for: displayMonth)[rowIndex]) { day in
                        if let date = day.date {
                            PillReadOnlyCalendarDayView(
                                dayNumber: calendar.component(.day, from: date),
                                isSelected: takenDays.contains(calendar.startOfDay(for: date)),
                                cellSize: cellSize
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: cellSize)
                        }
                    }
                }
            }
        }
    }

    private var cellSize: CGFloat {
        let raw = floor((availableWidth - 8 * 6) / 7)
        return min(max(raw, 35), 40)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Calendar.autoupdatingCurrent.locale ?? Locale.autoupdatingCurrent
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        return (Array(symbols[1...]) + [symbols[0]]).map { $0.uppercased() }
    }

    private func days(for displayMonth: Date) -> [PillCalendarDayCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayMonth),
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
            let isInDisplayedMonth = calendar.isDate(cursor, equalTo: displayMonth, toGranularity: .month)
            result.append(PillCalendarDayCell(id: cursor, date: isInDisplayedMonth ? cursor : nil))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    private func dayRows(for displayMonth: Date) -> [[PillCalendarDayCell]] {
        days(for: displayMonth).chunked(into: 7)
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
        transitionDirection = step > 0 ? .forward : .backward
        onMonthChange(availableMonths[nextIndex])
    }

    private func animateMonthChange(to newMonth: Date) {
        guard newMonth != renderedMonth else { return }
        guard availableWidth > 0 else {
            renderedMonth = newMonth
            outgoingMonth = nil
            return
        }

        let width = availableWidth
        let incomingStart = transitionDirection == .forward ? width : -width
        let outgoingEnd = -incomingStart

        outgoingMonth = renderedMonth
        renderedMonth = newMonth
        incomingOffset = incomingStart
        outgoingOffset = 0

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.24)) {
                incomingOffset = 0
                outgoingOffset = outgoingEnd
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard renderedMonth == newMonth else { return }
            outgoingMonth = nil
            incomingOffset = 0
            outgoingOffset = 0
        }
    }
}

private enum PillCalendarTransitionDirection {
    case forward
    case backward
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
    case selected
    case disabled
}

private struct PillCalendarDayView: View {
    let dayNumber: Int
    let style: PillCalendarDayStyle
    let cellSize: CGFloat

    private var selectionSize: CGFloat {
        min(cellSize, 42)
    }

    var body: some View {
        ZStack {
            if style == .selected {
                Circle()
                    .fill(Color(uiColor: .systemBlue).opacity(0.2))
                    .frame(width: selectionSize, height: selectionSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
        }
        .frame(width: cellSize, height: cellSize)
        .frame(maxWidth: .infinity, minHeight: cellSize)
    }

    private var foreground: Color {
        switch style {
        case .selected:
            return .blue
        case .available:
            return .primary
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }
}

private struct PillReadOnlyCalendarDayView: View {
    let dayNumber: Int
    let isSelected: Bool
    let cellSize: CGFloat

    private var selectionSize: CGFloat {
        min(cellSize, 42)
    }

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color(uiColor: .systemBlue).opacity(0.2))
                    .frame(width: selectionSize, height: selectionSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(isSelected ? Color.blue : Color(uiColor: .tertiaryLabel))
        }
        .frame(width: cellSize, height: cellSize)
        .frame(maxWidth: .infinity, minHeight: selectionSize)
    }
}
