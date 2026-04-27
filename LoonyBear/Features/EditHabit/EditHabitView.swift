import SwiftUI

struct EditHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState

    private let onSaveSuccess: () -> Void
    private let onDeleteSuccess: () -> Void
    private let showsCloseButton: Bool
    private let requiredPastScheduledDays: Set<Date>
    private let activeOverdueDay: Date?
    @State private var draft: EditHabitDraft
    @State private var validationMessage: String?
    @State private var historyValidationMessage: String?
    @State private var displayedMonth: Date
    @State private var isSaving = false
    @State private var isShowingDeleteConfirmation = false

    init(
        details: HabitDetailsProjection,
        showsCloseButton: Bool = true,
        onSaveSuccess: @escaping () -> Void = {},
        onDeleteSuccess: @escaping () -> Void = {}
    ) {
        self.onSaveSuccess = onSaveSuccess
        self.onDeleteSuccess = onDeleteSuccess
        self.showsCloseButton = showsCloseButton
        requiredPastScheduledDays = details.requiredPastScheduledDays
        activeOverdueDay = details.activeOverdueDay
        _draft = State(initialValue: EditHabitDraft(
            id: details.id,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            completedDays: details.completedDays,
            skippedDays: details.skippedDays
        ))
        _displayedMonth = State(initialValue: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date())
    }

    var body: some View {
        AppScreen(backgroundStyle: .habits, topPadding: 8) {
            nameSection
            notificationsSection
            historySection

            VStack(alignment: .leading, spacing: 8) {
                AppFormSectionHeader(title: "Calendar")

                if let currentHistoryReviewMessage {
                    AppHistoryReviewRow(message: currentHistoryReviewMessage)
                } else if let historyValidationMessage {
                    AppCompactValidationBanner(message: historyValidationMessage)
                }

                AppCard {
                    HabitHistoryCalendarView(
                        month: displayedMonth,
                        editableDays: editableHistoryDays,
                        completedDays: $draft.completedDays,
                        skippedDays: $draft.skippedDays,
                        availableMonths: availableMonths,
                        onMonthChange: { displayedMonth = $0 }
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }

                HabitHistoryLegend()
                AppHelperText(text: AppCopy.habitHistoryHint)
            }

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Text("Delete")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isSaving)
            .confirmationDialog("Delete Habit?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
                Button("Yes", role: .destructive) {
                    deleteHabit()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This habit will be permanently deleted.")
            }

            if let validationMessage {
                AppValidationBanner(message: validationMessage)
            }
        }
        .navigationTitle(draft.type.sectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark")
                }
                .fontWeight(.semibold)
                .accessibilityLabel("Save")
                .disabled(!isFormValid || hasMissingPastDays || isSaving)
            }
        }
        .onChange(of: draft.reminderEnabled) { _, isEnabled in
            guard isEnabled else { return }

            Task {
                let granted = await appState.requestNotificationAuthorizationIfNeeded()
                if !granted {
                    validationMessage = AppCopy.notificationsRequired
                    draft.reminderEnabled = false
                }
            }
        }
        .onChange(of: draft.completedDays) { _, _ in
            historyValidationMessage = nil
        }
        .onChange(of: draft.skippedDays) { _, _ in
            historyValidationMessage = nil
        }
        .animation(.easeInOut(duration: 0.18), value: validationMessage)
        .animation(.easeInOut(duration: 0.18), value: historyValidationMessage)
    }

    private var nameSection: some View {
        AppHabitNameCard(text: $draft.name, showsValidation: shouldShowNameValidation) {
            validationText("Habit name is required.")
        }
    }

    private var historySection: some View {
        AppFormCardSection(title: "History") {
            AppStartDateValueRow(date: draft.startDate)
        }
    }

    private var notificationsSection: some View {
        AppNotificationSettingsSection(
            scheduleSummary: draft.scheduleDays.compactSummaryOrPlaceholder,
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime.default())
        ) {
            EditHabitScheduleView(scheduleDays: $draft.scheduleDays)
        }
    }

    private var editableHistoryDays: Set<Date> {
        EditableHistoryWindow.dates(startDate: draft.startDate)
    }

    private var availableMonths: [Date] {
        HistoryMonthWindow.months(containing: editableHistoryDays)
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private var currentMissingPastDays: [Date] {
        let normalized = normalizedDraft()
        return EditableHistoryValidation.missingPastDays(
            editableDays: requiredPastScheduledDays,
            positiveDays: normalized.completedDays,
            skippedDays: normalized.skippedDays
        )
    }

    private var hasMissingPastDays: Bool {
        !currentMissingPastDays.isEmpty
    }

    private var currentHistoryReviewMessage: String? {
        let missingPastDays = currentMissingPastDays
        guard !missingPastDays.isEmpty else { return nil }
        return historyReviewMessage(for: missingPastDays)
    }

    private var shouldShowNameValidation: Bool {
        draft.name.isEmpty == false && draft.trimmedName.isEmpty
    }

    private func save() {
        guard isFormValid else {
            validationMessage = draft.trimmedName.isEmpty ? "Habit name is required." : AppCopy.chooseAtLeastOneDay
            return
        }

        isSaving = true
        validationMessage = nil
        historyValidationMessage = nil
        let savedDraft = normalizedDraft()
        let missingPastDays = currentMissingPastDays
        guard missingPastDays.isEmpty else {
            historyValidationMessage = historyReviewMessage(for: missingPastDays)
            displayedMonth = month(containing: missingPastDays[0])
            isSaving = false
            return
        }

        Task {
            do {
                try await appState.updateHabit(from: savedDraft)
                isSaving = false
                onSaveSuccess()
                dismiss()

                await appState.syncNotificationsAfterHabitUpdate(from: savedDraft)
            } catch {
                if let error = error as? EditableHistoryValidationError {
                    historyValidationMessage = error.localizedDescription
                    if case .missingHabitPastDays(let days) = error, let firstDay = days.first {
                        displayedMonth = month(containing: firstDay)
                    }
                } else {
                    validationMessage = appState.actionErrorMessage ?? error.localizedDescription
                }
                isSaving = false
            }
        }
    }

    private func deleteHabit() {
        isSaving = true
        validationMessage = nil
        historyValidationMessage = nil

        Task {
            await appState.deleteHabit(id: draft.id)
            if let errorMessage = appState.actionErrorMessage {
                validationMessage = errorMessage
                isSaving = false
                return
            }

            isSaving = false
            onDeleteSuccess()
            dismiss()
        }
    }

    private func normalizedDraft() -> EditHabitDraft {
        var normalized = draft
        normalized.skippedDays.subtract(normalized.completedDays)
        return normalized
    }

    private func historyReviewMessage(for missingPastDays: [Date]) -> String {
        if isOnlyActiveOverdueMissing(missingPastDays) {
            return AppCopy.overdueScheduledDayEditMessage(actionLabel: "Completed", days: missingPastDays)
        }
        return EditableHistoryValidationError.missingHabitPastDays(missingPastDays).localizedDescription
    }

    private func isOnlyActiveOverdueMissing(_ missingPastDays: [Date]) -> Bool {
        guard
            missingPastDays.count == 1,
            let activeOverdueDay
        else {
            return false
        }
        return Calendar.current.isDate(missingPastDays[0], inSameDayAs: activeOverdueDay)
    }

    private func month(containing date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    @ViewBuilder
    private func validationText(_ text: String) -> some View {
        AppInlineErrorText(text: text)
    }
}

private struct EditHabitScheduleView: View {
    @Binding var scheduleDays: WeekdaySet

    var body: some View {
        AppScheduleEditorScreen(
            backgroundStyle: .habits,
            scheduleDays: $scheduleDays
        )
    }
}

private struct HabitHistoryCalendarView: View {
    let month: Date
    let editableDays: Set<Date>
    @Binding var completedDays: Set<Date>
    @Binding var skippedDays: Set<Date>
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
            headerSpacing: 12,
            onMonthChange: onMonthChange
        ) { date, cellSize in
            HabitCalendarDayView(
                dayNumber: calendar.component(.day, from: date),
                style: dayStyle(for: date),
                cellSize: cellSize
            )
            .contentShape(Circle())
            .allowsHitTesting(editableDays.contains(date))
            .onTapGesture {
                toggle(date)
            }
            .disabled(!editableDays.contains(date))
        }
    }

    private func toggle(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        guard editableDays.contains(normalizedDate) else { return }

        let currentSelection: EditableHistorySelection
        switch dayStyle(for: normalizedDate) {
        case .available:
            currentSelection = .none
        case .completed:
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

        completedDays.remove(normalizedDate)
        skippedDays.remove(normalizedDate)

        switch nextSelection {
        case .none:
            break
        case .positive:
            completedDays.insert(normalizedDate)
        case .skipped:
            skippedDays.insert(normalizedDate)
        }
    }

    private func dayStyle(for date: Date) -> HabitCalendarDayStyle {
        guard editableDays.contains(date) else {
            return .disabled
        }
        if completedDays.contains(date) {
            return .completed
        } else if skippedDays.contains(date) {
            return .skipped
        } else {
            return .available
        }
    }
}

enum HabitCalendarDayStyle {
    case available
    case completed
    case skipped
    case disabled
}

struct HabitCalendarDayView: View {
    let dayNumber: Int
    let style: HabitCalendarDayStyle
    let cellSize: CGFloat

    var body: some View {
        ZStack {
            if style == .completed || style == .skipped {
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
        case .completed:
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
        case .completed:
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

private struct HabitHistoryLegend: View {
    var body: some View {
        AppLegend(items: [
            (label: "Completed", color: .blue),
            (label: "Skipped", color: .red),
        ])
    }
}
