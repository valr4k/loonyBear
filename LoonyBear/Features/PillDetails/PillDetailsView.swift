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
    @State private var isShowingSchedulePopover = false
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
                    AppFormSectionHeader(title: "Notifications")

                    AppCard {
                        AppValueRow(
                            title: "Schedule",
                            value: details.scheduleDays.compactSummary,
                            valueColor: AnyShapeStyle(.secondary),
                            showsChevron: true,
                            usesTintedChevron: true
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isShowingSchedulePopover = true
                        }
                        .popover(
                            isPresented: $isShowingSchedulePopover,
                            attachmentAnchor: .point(.trailing),
                            arrowEdge: .trailing
                        ) {
                            AppReadOnlySchedulePopoverContent(scheduleDays: details.scheduleDays)
                                .presentationBackground(.clear)
                        }

                        AppSectionDivider()
                        AppValueRow(title: "Reminder", value: details.reminderTime?.formatted ?? "Off")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "History")

                    AppCard {
                        AppValueRow(title: "Start Date", value: details.startDate.formatted(date: .abbreviated, time: .omitted))
                        AppSectionDivider()
                        AppValueRow(title: "Taken for", value: DayCountFormatter.compactDurationString(for: details.totalTakenDays), valueColor: AnyShapeStyle(.secondary))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Calendar")

                    if let calendarReviewMessage = calendarReviewMessage(for: details) {
                        AppHistoryReviewRow(message: calendarReviewMessage)
                    }

                    AppCard {
                        PillReadOnlyMonthCalendarView(
                            month: displayedMonth,
                            takenDays: details.takenDays,
                            skippedDays: details.skippedDays,
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
        .navigationTitle("Pill Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    AppToolbarIconLabel(systemName: "xmark")
                }
                .appAccentTint()
                .accessibilityLabel("Close")
            }

            if details != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isShowingEdit = true
                    } label: {
                        AppToolbarTextLabel(title: "Edit")
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

    private func reloadDetails() {
        isLoadingDetails = true
        switch pillAppState.loadPillDetailsState(id: pill.id) {
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

    private func availableMonths(for startDate: Date) -> [Date] {
        HistoryMonthWindow.months(from: startDate)
    }

    private func calendarReviewMessage(for details: PillDetailsProjection) -> String? {
        let missingPastDays = EditableHistoryValidation.missingPastDays(
            editableDays: details.requiredPastScheduledDays,
            positiveDays: details.takenDays,
            skippedDays: details.skippedDays
        )
        guard !missingPastDays.isEmpty else { return nil }

        if isOnlyActiveOverdueMissing(missingPastDays, activeOverdueDay: details.activeOverdueDay) {
            return AppCopy.overdueScheduledDayDetailsMessage(actionLabel: "Taken", days: missingPastDays)
        }
        return AppCopy.missingScheduledDaysDetailsMessage(actionLabel: "Taken", days: missingPastDays)
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
}
