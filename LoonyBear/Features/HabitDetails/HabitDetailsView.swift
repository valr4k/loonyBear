import SwiftUI

struct HabitDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState
    let habit: HabitCardProjection
    @State private var details: HabitDetailsProjection?
    @State private var detailErrorMessage: String?
    @State private var isIntegrityError = false
    @State private var isLoadingDetails = true
    @State private var needsReloadOnAppear = false
    @State private var displayedMonth: Date = {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    var body: some View {
        AppScreen(backgroundStyle: .habits, topPadding: 8) {
            if let details {
                DetailsCard {
                    Text(details.name)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 22)
                    AppSectionDivider()
                    AppValueRow(title: "Start Date", value: details.startDate.formatted(date: .abbreviated, time: .omitted))
                    AppSectionDivider()
                    AppValueRow(title: "Plan", value: details.scheduleSummary)
                    AppSectionDivider()
                    AppValueRow(title: "Reminder", value: details.reminderTime?.formatted ?? "Off")
                }

                DetailsCard {
                    AppValueRow(title: "Current streak", value: DayCountFormatter.compactDurationString(for: details.currentStreak), valueColor: AnyShapeStyle(.primary))
                    AppSectionDivider()
                    AppValueRow(title: "Best streak", value: DayCountFormatter.compactDurationString(for: details.longestStreak), valueColor: AnyShapeStyle(.primary))
                    AppSectionDivider()
                    AppValueRow(title: "Completed for", value: DayCountFormatter.compactDurationString(for: details.totalCompletedDays), valueColor: AnyShapeStyle(.primary))
                }

                DetailsCard {
                    HabitHeatmapView(
                        startDate: details.startDate,
                        completedDays: details.completedDays,
                        skippedDays: details.skippedDays,
                        displayedMonth: $displayedMonth
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
            } else if isLoadingDetails {
                DetailsCard {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 28)
                        Spacer()
                    }
                }
            } else if isIntegrityError {
                ContentUnavailableView(
                    "Habit data problem",
                    systemImage: "exclamationmark.triangle",
                    description: Text(detailErrorMessage ?? "This habit exists, but its details are corrupted.")
                )
            } else {
                ContentUnavailableView(
                    "Habit not found",
                    systemImage: "checklist",
                    description: Text("This habit is no longer available.")
                )
            }
        }
        .navigationTitle(details?.type.sectionTitle ?? "Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
        .onAppear {
            guard needsReloadOnAppear else { return }
            needsReloadOnAppear = false
            reloadDetails()
        }
        .task {
            reloadDetails()
        }
        .onReceive(NotificationCenter.default.publisher(for: .habitStoreDidChange)) { _ in
            reloadDetails()
        }
    }

    private func reloadDetails() {
        isLoadingDetails = true
        switch appState.loadHabitDetailsState(id: habit.id) {
        case .found(let loadedDetails):
            details = loadedDetails
            detailErrorMessage = nil
            isIntegrityError = false
        case .notFound:
            details = nil
            detailErrorMessage = nil
            isIntegrityError = false
        case .integrityError(let message):
            details = nil
            detailErrorMessage = message
            isIntegrityError = true
        }
        isLoadingDetails = false
    }
}

private struct DetailsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct HabitHeatmapView: View {
    let startDate: Date
    let completedDays: Set<Date>
    let skippedDays: Set<Date>
    @Binding var displayedMonth: Date

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReadOnlyMonthCalendarView(
                month: displayedMonth,
                completedDays: completedDays,
                skippedDays: skippedDays,
                availableMonths: displayMonths,
                onMonthChange: { displayedMonth = $0 }
            )
        }
        .padding(.vertical, 4)
    }

    private var displayMonths: [Date] {
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        guard start <= today else { return [] }

        var months: [Date] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let lastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today

        while cursor <= lastMonth {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return months
    }
}

private struct ReadOnlyMonthCalendarView: View {
    private let calendarSpacing: CGFloat = 6
    private let weekdayRowHeight: CGFloat = 20
    let month: Date
    let completedDays: Set<Date>
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
                                HabitCalendarDayView(
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
                    .preference(key: HabitCalendarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(HabitCalendarWidthPreferenceKey.self) { width in
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

    private var days: [ReadOnlyCalendarDayCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthInterval.start),
            let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else {
            return []
        }

        var result: [ReadOnlyCalendarDayCell] = []
        var cursor = calendar.startOfDay(for: firstWeekInterval.start)
        let end = calendar.startOfDay(for: lastWeekInterval.end)

        while cursor < end {
            let isInDisplayedMonth = calendar.isDate(cursor, equalTo: month, toGranularity: .month)
            result.append(ReadOnlyCalendarDayCell(id: cursor, date: isInDisplayedMonth ? cursor : nil))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    private var dayRows: [[ReadOnlyCalendarDayCell]] {
        days.chunked(into: 7)
    }

    private var cellSize: CGFloat {
        guard availableWidth > 0 else { return 40 }
        let raw = floor((availableWidth - calendarSpacing * 6) / 7)
        return min(max(raw, 35), 40)
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

    private func dayStyle(for date: Date) -> HabitCalendarDayStyle {
        let normalizedDate = calendar.startOfDay(for: date)
        if completedDays.contains(normalizedDate) {
            return .completed
        }
        if skippedDays.contains(normalizedDate) {
            return .skipped
        }
        return .disabled
    }
}

private struct ReadOnlyCalendarDayCell: Identifiable {
    let id: Date
    let date: Date?
}

private struct HabitCalendarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    NavigationStack {
        HabitDetailsView(
            habit: HabitCardProjection(
                id: UUID(),
                type: .build,
                name: "Morning walk",
                scheduleSummary: "Daily",
                currentStreak: 4,
                reminderText: "8:00 PM",
                reminderHour: 20,
                reminderMinute: 0,
                isReminderScheduledToday: true,
                isCompletedToday: true,
                isSkippedToday: false,
                sortOrder: 0
            )
        )
        .environmentObject(AppEnvironment.preview.appState)
    }
}
