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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)

                Text("Taken for: \(DayCountFormatter.compactDurationString(for: pill.totalTakenDays))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .overlay(alignment: .topTrailing) {
                    if let futureStartLabel {
                        Text(futureStartLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if pill.reminderText != nil || activeOverdueLabel != nil {
                        VStack(alignment: .trailing, spacing: 2) {
                            if let reminderText = pill.reminderText {
                                Text(reminderText)
                            }
                            if let activeOverdueLabel {
                                Text(activeOverdueLabel)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(isReminderOverdue ? .red : .secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .overlay(alignment: .trailing) {
                    if !pill.needsHistoryReview, pill.isTakenToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                    } else if !pill.needsHistoryReview, pill.isSkippedToday {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if pill.needsHistoryReview {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("History needs review")
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

    private var isReminderOverdue: Bool {
        pill.activeOverdueDay != nil
    }

    private var activeOverdueLabel: String? {
        guard let overdueDay = pill.activeOverdueDay else { return nil }
        return OverdueDayLabel.text(for: overdueDay, now: currentTime)
    }

    private var futureStartLabel: String? {
        guard pill.startsInFuture, let futureStartDate = pill.futureStartDate else { return nil }
        return FutureStartLabel.text(for: futureStartDate)
    }
}

struct PillHistoryCalendarView: View {
    let month: Date
    let editableDays: Set<Date>
    let scheduledDates: Set<Date>
    let archivedDays: Set<Date>
    let historySnapshot: CoreDataHistoryBucketSnapshot
    @Binding var takenDays: Set<Date>
    @Binding var skippedDays: Set<Date>
    let availableMonthRange: ClosedRange<Date>
    var isReadOnly = false
    let onMonthChange: (Date) -> Void

    private var calendar: Calendar {
        MonthCalendarSupport.defaultCalendar()
    }

    var body: some View {
        MonthCalendarView(
            month: month,
            availableMonthRange: availableMonthRange,
            calendar: calendar,
            headerSpacing: 12,
            onMonthChange: onMonthChange
        ) { date, cellSize in
            PillCalendarDayView(
                dayNumber: calendar.component(.day, from: date),
                style: dayStyle(for: date),
                isEditable: !isReadOnly && editableDays.contains(date) && !isArchived(date),
                isScheduled: isScheduled(date),
                cellSize: cellSize
            )
            .contentShape(Circle())
            .allowsHitTesting(!isReadOnly && editableDays.contains(date) && !isArchived(date))
            .onTapGesture {
                toggle(date)
            }
        }
    }

    private func toggle(_ date: Date) {
        guard !isReadOnly else { return }
        let normalizedDate = calendar.startOfDay(for: date)
        guard editableDays.contains(normalizedDate) else { return }
        guard !archivedDays.contains(normalizedDate) else { return }

        let currentSelection: EditableHistorySelection
        switch dayStyle(for: normalizedDate) {
        case .available:
            currentSelection = .none
        case .taken:
            currentSelection = .positive
        case .skipped:
            currentSelection = .skipped
        case .archived, .disabled:
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

    private func dayStyle(for date: Date) -> PillCalendarDayStyle {
        let normalizedDate = calendar.startOfDay(for: date)

        if takenDays.contains(normalizedDate) {
            return .taken
        } else if skippedDays.contains(normalizedDate) {
            return .skipped
        } else if archivedDays.contains(normalizedDate) {
            return .archived
        } else if editableDays.contains(normalizedDate) && !isReadOnly {
            return .available
        } else if let state = historySnapshot.state(on: normalizedDate, calendar: calendar) {
            switch state {
            case .positive:
                return .taken
            case .skipped:
                return .skipped
            case .archived:
                return .archived
            }
        } else if isReadOnly {
            return .disabled
        } else {
            return .disabled
        }
    }

    private func isScheduled(_ date: Date) -> Bool {
        scheduledDates.contains(calendar.startOfDay(for: date))
    }

    private func isArchived(_ date: Date) -> Bool {
        let normalizedDate = calendar.startOfDay(for: date)
        return archivedDays.contains(normalizedDate) ||
            historySnapshot.state(on: normalizedDate, calendar: calendar) == .archived
    }
}

struct PillReadOnlyMonthCalendarView: View {
    let month: Date
    let takenDays: Set<Date>
    let skippedDays: Set<Date>
    let archivedDays: Set<Date>
    let historySnapshot: CoreDataHistoryBucketSnapshot
    let scheduledDates: Set<Date>
    let availableMonthRange: ClosedRange<Date>
    let onMonthChange: (Date) -> Void

    private var calendar: Calendar {
        MonthCalendarSupport.defaultCalendar()
    }

    var body: some View {
        MonthCalendarView(
            month: month,
            availableMonthRange: availableMonthRange,
            calendar: calendar,
            headerSpacing: 10,
            onMonthChange: onMonthChange
        ) { date, cellSize in
            PillReadOnlyCalendarDayView(
                dayNumber: calendar.component(.day, from: date),
                style: dayStyle(for: date),
                isScheduled: isScheduled(date),
                cellSize: cellSize
            )
        }
        .padding(.vertical, 4)
    }

    private func dayStyle(for date: Date) -> PillReadOnlyDayStyle {
        let normalizedDate = calendar.startOfDay(for: date)
        if takenDays.contains(normalizedDate) {
            return .taken
        }
        if skippedDays.contains(normalizedDate) {
            return .skipped
        }
        if archivedDays.contains(normalizedDate) {
            return .archived
        }
        if let state = historySnapshot.state(on: normalizedDate, calendar: calendar) {
            switch state {
            case .positive:
                return .taken
            case .skipped:
                return .skipped
            case .archived:
                return .archived
            }
        }
        return .disabled
    }

    private func isScheduled(_ date: Date) -> Bool {
        scheduledDates.contains(calendar.startOfDay(for: date))
    }
}

private enum PillCalendarDayStyle {
    case available
    case taken
    case skipped
    case archived
    case disabled
}

private struct PillCalendarDayView: View {
    let dayNumber: Int
    let style: PillCalendarDayStyle
    let isEditable: Bool
    let isScheduled: Bool
    let cellSize: CGFloat
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    var body: some View {
        ZStack {
            if style == .taken || style == .skipped || style == .archived {
                Circle()
                    .fill(backgroundColor)
                    .overlay {
                        Circle()
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    }
                    .frame(width: markerSize, height: markerSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
                .frame(width: markerSize, height: markerSize)

            if isScheduled {
                Circle()
                    .fill(scheduleIndicatorColor)
                    .frame(width: scheduleIndicatorSize, height: scheduleIndicatorSize)
                    .offset(y: scheduleIndicatorOffset)
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var foreground: Color {
        switch style {
        case .taken:
            return appTint.accentColor
        case .skipped:
            return .red
        case .archived:
            return Color(uiColor: .tertiaryLabel)
        case .available:
            return .primary
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .taken:
            return appTint.accentColor.opacity(markedBackgroundOpacity)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(markedBackgroundOpacity)
        case .archived:
            return Color(uiColor: .systemGray).opacity(0.14)
        case .available, .disabled:
            return .clear
        }
    }

    private var borderColor: Color {
        guard isEditable else { return .clear }

        switch style {
        case .taken:
            return appTint.accentColor.opacity(0.45)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(0.45)
        case .archived, .available, .disabled:
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        isEditable ? 1 : 0
    }

    private var markedBackgroundOpacity: Double {
        isEditable ? 0.22 : 0.18
    }

    private var markerSize: CGFloat {
        min(cellSize, 40)
    }

    private var scheduleIndicatorSize: CGFloat {
        4
    }

    private var scheduleIndicatorOffset: CGFloat {
        markerSize / 2 - scheduleIndicatorSize - 2
    }

    private var scheduleIndicatorColor: Color {
        Color(uiColor: .tertiaryLabel)
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
    }
}

private enum PillReadOnlyDayStyle {
    case taken
    case skipped
    case archived
    case disabled
}

private struct PillReadOnlyCalendarDayView: View {
    let dayNumber: Int
    let style: PillReadOnlyDayStyle
    let isScheduled: Bool
    let cellSize: CGFloat
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    var body: some View {
        ZStack {
            if style == .taken || style == .skipped || style == .archived {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: markerSize, height: markerSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
                .frame(width: markerSize, height: markerSize)

            if isScheduled {
                Circle()
                    .fill(scheduleIndicatorColor)
                    .frame(width: scheduleIndicatorSize, height: scheduleIndicatorSize)
                    .offset(y: scheduleIndicatorOffset)
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var foreground: Color {
        switch style {
        case .taken:
            return appTint.accentColor
        case .skipped:
            return .red
        case .archived:
            return Color(uiColor: .tertiaryLabel)
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .taken:
            return appTint.accentColor.opacity(0.18)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(0.18)
        case .archived:
            return Color(uiColor: .systemGray).opacity(0.14)
        case .disabled:
            return .clear
        }
    }

    private var markerSize: CGFloat {
        min(cellSize, 40)
    }

    private var scheduleIndicatorSize: CGFloat {
        4
    }

    private var scheduleIndicatorOffset: CGFloat {
        markerSize / 2 - scheduleIndicatorSize
    }

    private var scheduleIndicatorColor: Color {
        Color(uiColor: .tertiaryLabel)
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
    }
}
