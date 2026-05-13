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
    @State private var isShowingEdit = false
    @State private var isShowingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isCalendarWarningDismissed = false
    @State private var isNotFoundWarningDismissed = false
    @State private var displayedMonth: Date = {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    init(habit: HabitCardProjection) {
        self.habit = habit
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
                    AppFormSectionHeader(title: "Streaks")

                    DetailsCard {
                        AppPlainValueRow(
                            title: "Current streak",
                            value: DayCountFormatter.compactDurationString(for: details.currentStreak),
                            valueColor: AnyShapeStyle(.secondary)
                        )
                        AppSectionDivider()
                        AppPlainValueRow(
                            title: "Best streak",
                            value: DayCountFormatter.compactDurationString(for: details.longestStreak),
                            valueColor: AnyShapeStyle(.secondary)
                        )
                        AppSectionDivider()
                        AppPlainValueRow(
                            title: "Completed for",
                            value: DayCountFormatter.compactDurationString(for: details.totalCompletedDays),
                            valueColor: AnyShapeStyle(.secondary)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Schedule")

                    DetailsCard {
                        AppPlainValueRow(title: "Reminder", value: details.reminderTime?.formatted ?? "Off")
                        AppSectionDivider()
                        AppPlainValueRow(
                            title: "Repeat",
                            value: scheduleDisplayText(for: details),
                            valueColor: AnyShapeStyle(.secondary)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "History")

                    DetailsCard {
                        AppPlainValueRow(title: "Start Date", value: details.startDate.formatted(date: .abbreviated, time: .omitted))
                        AppSectionDivider()
                        AppPlainValueRow(title: "End Date", value: endDateText(for: details.endDate))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Calendar")

                    DetailsCard {
                        HabitHeatmapView(
                            startDate: details.startDate,
                            endDate: details.endDate,
                            completedDays: details.completedDays,
                            skippedDays: details.skippedDays,
                            archivedDays: details.archivedDays,
                            historySnapshot: details.historySnapshot,
                            scheduleHistory: details.scheduleHistory,
                            displayedMonth: $displayedMonth
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    }
                }

                if details.isArchived {
                    deleteButton
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
                    systemImage: "checklist"
                )
            }
        }
        .overlay(alignment: .bottom) {
            floatingBottomBanners
        }
        .navigationTitle(details?.type.sectionTitle ?? "Habit")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Permanently delete this Habit?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteHabit()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This Habit will be permanently deleted.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    AppToolbarIconLabel("Close", systemName: "xmark")
                }
                .appAccentTint()
            }

            if details?.isArchived == false {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        isShowingEdit = true
                    }
                    .appAccentTint()
                    .accessibilityLabel("Edit Habit")
                }
            }
        }
        .navigationDestination(isPresented: $isShowingEdit) {
            habitEditDestination
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
        .onChange(of: floatingCalendarWarningMessage) { _, message in
            if message == nil {
                isCalendarWarningDismissed = false
            }
        }
        .animation(.easeInOut(duration: 0.18), value: floatingCalendarWarningMessage)
        .animation(.easeInOut(duration: 0.18), value: isCalendarWarningDismissed)
        .animation(.easeInOut(duration: 0.18), value: isNotFoundWarningDismissed)
        .animation(.easeInOut(duration: 0.18), value: deleteErrorMessage)
    }

    private var deleteButton: some View {
        Button {
            isShowingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppMaterialCapsuleActionButtonStyle())
        .tint(.red)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var habitEditDestination: some View {
        if let details {
            EditHabitView(
                details: details,
                showsCloseButton: false,
                onSaveSuccess: {
                    reloadDetails()
                },
                onDeleteSuccess: {
                    dismiss()
                },
                onArchiveSuccess: {
                    dismiss()
                }
            )
            .appTintedBackButton()
            .environmentObject(appState)
        } else {
            ContentUnavailableView(
                "Habit not found",
                systemImage: "checklist"
            )
        }
    }

    @ViewBuilder
    private var floatingBottomBanners: some View {
        if shouldShowFloatingBottomBanners {
            VStack(spacing: 10) {
                if let message = notFoundWarningMessage, !isNotFoundWarningDismissed {
                    AppFloatingWarningBanner(message: message) {
                        isNotFoundWarningDismissed = true
                    }
                }

                if let message = floatingCalendarWarningMessage, !isCalendarWarningDismissed {
                    AppFloatingWarningBanner(message: message) {
                        isCalendarWarningDismissed = true
                    }
                }

                if let deleteErrorMessage {
                    AppFloatingWarningBanner(message: deleteErrorMessage) {
                        self.deleteErrorMessage = nil
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .zIndex(1)
        }
    }

    private var shouldShowFloatingBottomBanners: Bool {
        (notFoundWarningMessage != nil && !isNotFoundWarningDismissed)
            || (floatingCalendarWarningMessage != nil && !isCalendarWarningDismissed)
            || deleteErrorMessage != nil
    }

    private var notFoundWarningMessage: String? {
        guard !isLoadingDetails, details == nil, !isIntegrityError else { return nil }
        return "This habit is no longer available."
    }

    private var floatingCalendarWarningMessage: String? {
        guard let details else { return nil }
        return calendarReviewMessage(for: details)
    }

    private func reloadDetails() {
        isLoadingDetails = true
        switch appState.loadHabitDetailsState(id: habit.id) {
        case .found(let loadedDetails):
            details = loadedDetails
            displayedMonth = HistoryMonthWindow.displayMonth(startDate: loadedDetails.startDate)
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

    private func scheduleDisplayText(for details: HabitDetailsProjection) -> String {
        DashboardScheduleSummary.text(
            latestSchedule: details.scheduleHistory.sorted(by: CoreDataScheduleSupport.isNewerSchedule).first,
            startDate: details.startDate,
            endDate: details.endDate,
            schedules: details.scheduleHistory,
            today: Calendar.current.startOfDay(for: Date()),
            calendar: Calendar.current
        )
    }

    private func endDateText(for endDate: Date?) -> String {
        endDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
    }

    private func calendarReviewMessage(for details: HabitDetailsProjection) -> String? {
        guard !details.isArchived else { return nil }
        let missingPastDays = EditableHistoryValidation.missingPastDays(
            editableDays: details.requiredPastScheduledDays,
            positiveDays: details.completedDays,
            skippedDays: details.skippedDays
        )
        guard !missingPastDays.isEmpty else { return nil }

        if isOnlyActiveOverdueMissing(missingPastDays, activeOverdueDay: details.activeOverdueDay) {
            return AppCopy.overdueScheduledDayDetailsMessage(actionLabel: "Completed")
        }
        return AppCopy.missingScheduledDaysDetailsMessage(actionLabel: "Completed")
    }

    private func isOnlyActiveOverdueMissing(_ missingPastDays: [Date], activeOverdueDay: Date?) -> Bool {
        guard
            missingPastDays.count == 1,
            let activeOverdueDay
        else {
            return false
        }
        return Calendar.current.isDate(missingPastDays[0], inSameDayAs: activeOverdueDay)
    }

    private func deleteHabit() {
        guard let details else { return }
        deleteErrorMessage = nil

        Task {
            await appState.deleteHabit(id: details.id)
            if let errorMessage = appState.actionErrorMessage {
                deleteErrorMessage = errorMessage
                return
            }

            dismiss()
        }
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
    let endDate: Date?
    let completedDays: Set<Date>
    let skippedDays: Set<Date>
    let archivedDays: Set<Date>
    let historySnapshot: CoreDataHistoryBucketSnapshot
    let scheduleHistory: [HabitScheduleVersion]
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
                archivedDays: archivedDays,
                historySnapshot: historySnapshot,
                scheduledDates: visibleScheduledDates,
                availableMonthRange: displayMonthRange,
                onMonthChange: { displayedMonth = $0 }
            )
        }
        .padding(.vertical, 4)
    }

    private var displayMonthRange: ClosedRange<Date> {
        let firstMonth = HistoryMonthWindow.monthStart(containing: startDate, calendar: calendar)
        let lastMonth = HistoryMonthWindow.monthStart(
            containing: HistoryMonthWindow.detailsCalendarEndDate(startDate: startDate, today: Date(), calendar: calendar),
            calendar: calendar
        )
        return firstMonth ... max(firstMonth, lastMonth)
    }

    private var visibleScheduledDates: Set<Date> {
        HistoryScheduleApplicability.scheduledDays(
            in: displayedMonthRange,
            startDate: startDate,
            limitingTo: endDate,
            schedules: scheduleHistory,
            calendar: calendar
        )
    }

    private var displayedMonthRange: ClosedRange<Date> {
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayedMonth)
        ) ?? calendar.startOfDay(for: displayedMonth)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
        return monthStart ... monthEnd
    }
}

private struct ReadOnlyMonthCalendarView: View {
    let month: Date
    let completedDays: Set<Date>
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
            HabitCalendarDayView(
                dayNumber: calendar.component(.day, from: date),
                style: dayStyle(for: date),
                isEditable: false,
                isScheduled: isScheduled(date),
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
        if archivedDays.contains(normalizedDate) {
            return .archived
        }
        if let state = historySnapshot.state(on: normalizedDate, calendar: calendar) {
            switch state {
            case .positive:
                return .completed
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
