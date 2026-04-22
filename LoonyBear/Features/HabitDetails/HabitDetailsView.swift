import SwiftUI

struct HabitDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState
    let habit: HabitCardProjection
    let onEdit: (UUID) -> Void
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

    init(habit: HabitCardProjection, onEdit: @escaping (UUID) -> Void = { _ in }) {
        self.habit = habit
        self.onEdit = onEdit
    }

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
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Notifications")

                    DetailsCard {
                        NavigationLink {
                            AppReadOnlyScheduleView(
                                scheduleDays: details.scheduleDays,
                                backgroundStyle: .habits
                            )
                        } label: {
                            AppValueRow(
                                title: "Schedule",
                                value: details.scheduleDays.compactSummary,
                                valueColor: AnyShapeStyle(.secondary),
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)

                        AppSectionDivider()
                        AppValueRow(title: "Reminder", value: details.reminderTime?.formatted ?? "Off")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "History")

                    DetailsCard {
                        AppValueRow(title: "Start Date", value: details.startDate.formatted(date: .abbreviated, time: .omitted))
                        AppSectionDivider()
                        AppValueRow(title: "Current streak", value: DayCountFormatter.compactDurationString(for: details.currentStreak), valueColor: AnyShapeStyle(.secondary))
                        AppSectionDivider()
                        AppValueRow(title: "Best streak", value: DayCountFormatter.compactDurationString(for: details.longestStreak), valueColor: AnyShapeStyle(.secondary))
                        AppSectionDivider()
                        AppValueRow(title: "Completed for", value: DayCountFormatter.compactDurationString(for: details.totalCompletedDays), valueColor: AnyShapeStyle(.secondary))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Calendar")

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

            if details != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        onEdit(habit.id)
                    }
                    .accessibilityLabel("Edit Habit")
                }
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
        HistoryMonthWindow.months(from: startDate, through: Date(), calendar: calendar)
    }
}

private struct ReadOnlyMonthCalendarView: View {
    let month: Date
    let completedDays: Set<Date>
    let skippedDays: Set<Date>
    let availableMonths: [Date]
    let onMonthChange: (Date) -> Void

    private var calendar: Calendar {
        MonthCalendarSupport.defaultCalendar()
    }

    var body: some View {
        MonthCalendarView(
            month: month,
            availableMonths: availableMonths,
            calendar: calendar,
            headerSpacing: 10,
            onMonthChange: onMonthChange
        ) { date, cellSize in
            HabitCalendarDayView(
                dayNumber: calendar.component(.day, from: date),
                style: dayStyle(for: date),
                cellSize: cellSize
            )
        }
        .padding(.vertical, 4)
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
