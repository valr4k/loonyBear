import SwiftUI

struct PillDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState
    let pill: PillCardProjection

    @State private var details: PillDetailsProjection?
    @State private var detailErrorMessage: String?
    @State private var isIntegrityError = false
    @State private var isLoadingDetails = true
    @State private var needsReloadOnAppear = false
    @State private var isShowingEdit = false
    @State private var isShowingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isCalendarWarningDismissed = false
    @State private var displayedMonth: Date = {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    init(pill: PillCardProjection) {
        self.pill = pill
    }

    var body: some View {
        AppScreen(backgroundStyle: .pills, topPadding: 8) {
            if isLoadingDetails {
                AppCard {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 28)
                        Spacer()
                    }
                }
            } else if let details {
                AppCard {
                    VStack(alignment: .center, spacing: 8) {
                        Text(details.name)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Text(details.dosage)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 22)
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Streak")

                    AppCard {
                        AppPlainValueRow(
                            title: "Taken for",
                            value: DayCountFormatter.compactDurationString(for: details.totalTakenDays),
                            valueColor: AnyShapeStyle(.secondary)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Schedule")

                    AppCard {
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

                    AppCard {
                        AppPlainValueRow(title: "Start Date", value: details.startDate.formatted(date: .abbreviated, time: .omitted))
                        AppSectionDivider()
                        AppPlainValueRow(title: "End Date", value: endDateText(for: details.endDate))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Calendar")

                    AppCard {
                        PillReadOnlyMonthCalendarView(
                            month: displayedMonth,
                            takenDays: details.takenDays,
                            skippedDays: details.skippedDays,
                            scheduledDates: details.scheduledDates,
                            availableMonths: availableMonths(for: details.startDate),
                            onMonthChange: { displayedMonth = $0 }
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    }
                }

                if let description = details.details, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        AppFormSectionHeader(title: "Description")

                        AppCard {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 18)
                        }
                    }
                }

                if details.isArchived {
                    deleteButton
                }

                if let deleteErrorMessage {
                    AppValidationBanner(message: deleteErrorMessage)
                }
            } else if isIntegrityError {
                ContentUnavailableView(
                    "Pill data problem",
                    systemImage: "exclamationmark.triangle",
                    description: Text(detailErrorMessage ?? "This pill exists, but its details are corrupted.")
                )
            } else {
                ContentUnavailableView(
                    "Pill not found",
                    systemImage: "pills",
                    description: Text("This pill is no longer available.")
                )
            }
        }
        .overlay(alignment: .bottom) {
            floatingCalendarWarningBanner
        }
        .navigationTitle("Pill Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Pill?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deletePill()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This pill will be permanently deleted.")
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
                    .accessibilityLabel("Edit Pill")
                }
            }
        }
        .navigationDestination(isPresented: $isShowingEdit) {
            pillEditDestination
        }
        .onAppear {
            guard needsReloadOnAppear else { return }
            needsReloadOnAppear = false
            reloadDetails()
        }
        .task {
            reloadDetails()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pillStoreDidChange)) { _ in
            reloadDetails()
        }
        .onChange(of: floatingCalendarWarningMessage) { _, message in
            if message == nil {
                isCalendarWarningDismissed = false
            }
        }
        .animation(.easeInOut(duration: 0.18), value: floatingCalendarWarningMessage)
        .animation(.easeInOut(duration: 0.18), value: isCalendarWarningDismissed)
        .animation(.easeInOut(duration: 0.18), value: deleteErrorMessage)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isShowingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var pillEditDestination: some View {
        if let details {
            EditPillView(
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
            .environmentObject(pillAppState)
        } else {
            ContentUnavailableView(
                "Pill not found",
                systemImage: "pills",
                description: Text("This pill is no longer available.")
            )
        }
    }

    @ViewBuilder
    private var floatingCalendarWarningBanner: some View {
        if let message = floatingCalendarWarningMessage, !isCalendarWarningDismissed {
            AppFloatingWarningBanner(message: message) {
                isCalendarWarningDismissed = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .zIndex(1)
        }
    }

    private var floatingCalendarWarningMessage: String? {
        guard let details else { return nil }
        return calendarReviewMessage(for: details)
    }

    private func reloadDetails() {
        isLoadingDetails = true
        switch pillAppState.loadPillDetailsState(id: pill.id) {
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

    private func availableMonths(for startDate: Date) -> [Date] {
        HistoryMonthWindow.months(
            from: startDate,
            through: HistoryMonthWindow.detailsCalendarEndDate(startDate: startDate),
            calendar: Calendar.current
        )
    }

    private func scheduleDisplayText(for details: PillDetailsProjection) -> String {
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

    private func calendarReviewMessage(for details: PillDetailsProjection) -> String? {
        guard !details.isArchived else { return nil }
        let missingPastDays = EditableHistoryValidation.missingPastDays(
            editableDays: details.requiredPastScheduledDays,
            positiveDays: details.takenDays,
            skippedDays: details.skippedDays
        )
        guard !missingPastDays.isEmpty else { return nil }

        if isOnlyActiveOverdueMissing(missingPastDays, activeOverdueDay: details.activeOverdueDay) {
            return AppCopy.overdueScheduledDayDetailsMessage(actionLabel: "Taken")
        }
        return AppCopy.missingScheduledDaysDetailsMessage(actionLabel: "Taken")
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

    private func deletePill() {
        guard let details else { return }
        deleteErrorMessage = nil

        Task {
            await pillAppState.deletePill(id: details.id)
            if let errorMessage = pillAppState.actionErrorMessage {
                deleteErrorMessage = errorMessage
                return
            }

            dismiss()
        }
    }
}
