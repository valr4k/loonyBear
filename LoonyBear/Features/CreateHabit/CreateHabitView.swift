import SwiftUI

struct CreateHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState

    @State private var draft = CreateHabitDraft()
    @State private var validationMessage: String?
    @State private var createLimitWarningMessage: String?
    @State private var isCreateLimitWarningDismissed = false
    @State private var isScheduleWarningDismissed = false
    @State private var isEndDateWarningDismissed = false
    @State private var pendingScheduleRule: ScheduleRule?
    @State private var isSaving = false
    @State private var hasInitialized = false
    @State private var isShowingNotificationSettingsAlert = false

    var body: some View {
        AppScreen(backgroundStyle: .habits, topPadding: 8) {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                scheduleSection
                if let validationMessage {
                    AppValidationBanner(message: validationMessage)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                AppDescriptionFieldSupport.dismissKeyboard()
            }
        }
        .overlay(alignment: .bottom) {
            floatingBottomBanners
        }
        .navigationTitle("Create Habit")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    AppToolbarIconLabel("Close", systemName: "xmark")
                }
                .appAccentTint()
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveHabit()
                } label: {
                    AppToolbarIconLabel("Save", systemName: "checkmark")
                }
                .appToolbarActionTint(isDisabled: !isFormValid || isSaving)
                .fontWeight(.semibold)
                .disabled(!isFormValid || isSaving)
            }
        }
        .onAppear {
            initializeIfNeeded()
            applyPendingScheduleRuleIfNeeded()
        }
        .onChange(of: draft.scheduleRule) { _, _ in
            handleScheduleRuleChange()
            handleEndDateValidationInputsChanged()
        }
        .onChange(of: draft.startDate) { _, _ in
            handleEndDateValidationInputsChanged()
        }
        .onChange(of: draft.endDate) { _, _ in
            handleEndDateValidationInputsChanged()
        }
        .onChange(of: draft.reminderEnabled) { _, isEnabled in
            guard isEnabled else { return }

            Task {
                let granted = await appState.requestNotificationAuthorizationIfNeeded()
                if !granted {
                    validationMessage = nil
                    createLimitWarningMessage = nil
                    isShowingNotificationSettingsAlert = true
                    draft.reminderEnabled = false
                }
            }
        }
        .appNotificationSettingsAlert(isPresented: $isShowingNotificationSettingsAlert)
        .animation(.easeInOut(duration: 0.18), value: validationMessage)
        .animation(.easeInOut(duration: 0.18), value: createLimitWarningMessage)
        .animation(.easeInOut(duration: 0.18), value: isCreateLimitWarningDismissed)
        .animation(.easeInOut(duration: 0.18), value: isScheduleWarningDismissed)
        .animation(.easeInOut(duration: 0.18), value: isEndDateWarningDismissed)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            typeSection
            nameSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typeSection: some View {
        Picker("Habit Type", selection: $draft.type) {
            ForEach(HabitType.allCases) { type in
                Text(type.sectionTitle).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var nameSection: some View {
        AppHabitNameCard(text: $draft.name, showsValidation: shouldShowNameValidation) {
            AppInlineErrorText(text: "Enter a habit name.")
        }
    }

    private var scheduleSection: some View {
        AppCreateScheduleSection(
            startDate: startDateBinding,
            startDateRange: selectableStartDateRange,
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime(hour: 20, minute: 0)),
            endDate: $draft.endDate,
            endDateRange: selectableEndDateRange,
            repeatSummary: draft.scheduleRule.compactSummary,
            startDateTap: dismissKeyboardForNonTextControl,
            reminderTimeTap: dismissKeyboardForNonTextControl,
            repeatTap: dismissKeyboardForNonTextControl,
            endDateTap: dismissKeyboardForNonTextControl
        ) {
            AppCreateRepeatEditorScreen(
                backgroundStyle: .habits,
                scheduleRule: draft.scheduleRule,
                startDate: draft.startDate,
                onTap: dismissKeyboardForNonTextControl,
                onSave: stageScheduleRule
            )
        }
    }

    private var selectableStartDateRange: ClosedRange<Date> {
        StartDateSelectionWindow.range(offset: DateComponents(year: -5))
    }

    private var selectableEndDateRange: PartialRangeFrom<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let lowerBound = max(today, Calendar.current.startOfDay(for: draft.startDate))
        return lowerBound...
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && draft.scheduleRule.isValidSelection && isEndDateValid
    }

    private var isEndDateValid: Bool {
        guard let endDate = draft.endDate else {
            return true
        }
        let normalizedEndDate = Calendar.current.startOfDay(for: endDate)
        guard normalizedEndDate >= selectableEndDateRange.lowerBound else {
            return false
        }
        return hasScheduledDay(from: selectableEndDateRange.lowerBound, through: normalizedEndDate)
    }

    private var endDateValidationMessage: String? {
        isEndDateValid ? nil : AppCopy.noScheduledDayBeforeEndDate
    }

    private var validationScheduleVersions: [SchedulePreviewVersion] {
        [
            SchedulePreviewVersion(
                rule: draft.scheduleRule,
                effectiveFrom: Calendar.current.startOfDay(for: draft.startDate),
                createdAt: .distantPast,
                version: 1
            ),
        ]
    }

    private func hasScheduledDay(from lowerBound: Date, through endDate: Date) -> Bool {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: lowerBound)
        let normalizedEndDate = calendar.startOfDay(for: endDate)
        let cappedEndDate = min(
            normalizedEndDate,
            calendar.date(byAdding: .day, value: 31, to: cursor).map { calendar.startOfDay(for: $0) } ?? normalizedEndDate
        )

        while cursor <= cappedEndDate {
            if HistoryScheduleApplicability.isScheduled(
                on: cursor,
                startDate: draft.startDate,
                endDate: normalizedEndDate,
                from: validationScheduleVersions,
                calendar: calendar
            ) {
                return true
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return false
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { draft.startDate },
            set: { newValue in
                draft.startDate = Calendar.current.startOfDay(for: newValue)
            }
        )
    }

    private var shouldShowNameValidation: Bool {
        draft.name.isEmpty == false && draft.trimmedName.isEmpty
    }

    @ViewBuilder
    private var floatingBottomBanners: some View {
        if shouldShowFloatingBottomBanners {
            VStack(spacing: 10) {
                if let message = scheduleWarningMessage, !isScheduleWarningDismissed {
                    AppFloatingWarningBanner(message: message) {
                        isScheduleWarningDismissed = true
                    }
                }

                if let message = endDateFloatingWarningMessage {
                    AppFloatingWarningBanner(message: message) {
                        isEndDateWarningDismissed = true
                    }
                }

                if let message = createLimitWarningMessage, !isCreateLimitWarningDismissed {
                    AppFloatingWarningBanner(message: message) {
                        isCreateLimitWarningDismissed = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .zIndex(1)
        }
    }

    private var shouldShowFloatingBottomBanners: Bool {
        (scheduleWarningMessage != nil && !isScheduleWarningDismissed)
            || endDateFloatingWarningMessage != nil
            || (createLimitWarningMessage != nil && !isCreateLimitWarningDismissed)
    }

    private var scheduleWarningMessage: String? {
        draft.scheduleRule.isValidSelection ? nil : AppCopy.chooseAtLeastOneDay
    }

    private var endDateFloatingWarningMessage: String? {
        guard !isEndDateWarningDismissed else { return nil }
        return endDateValidationMessage
    }

    private func saveHabit() {
        guard isFormValid else {
            createLimitWarningMessage = nil
            if !draft.scheduleRule.isValidSelection {
                isScheduleWarningDismissed = false
            }
            validationMessage = draft.trimmedName.isEmpty ? "Enter a habit name." : nil
            return
        }

        isSaving = true
        validationMessage = nil
        createLimitWarningMessage = nil
        let savedDraft = normalizedDraft()

        Task {
            do {
                let habitID = try await appState.createHabit(from: savedDraft)
                isSaving = false
                dismiss()

                guard savedDraft.reminderEnabled else { return }
                await appState.prepareReminderNotifications(forHabitID: habitID)
            } catch {
                let message = appState.createHabitErrorMessage ?? UserFacingErrorMessage.text(for: error)
                if isCreateLimitError(error, message: message) {
                    showCreateLimitWarning(message)
                } else {
                    validationMessage = message
                }
                isSaving = false
            }
        }
    }

    private func handleScheduleRuleChange() {
        isScheduleWarningDismissed = false
        if draft.scheduleRule.isValidSelection, validationMessage == AppCopy.chooseAtLeastOneDay {
            validationMessage = nil
        }
    }

    private func handleEndDateValidationInputsChanged() {
        isEndDateWarningDismissed = false
    }

    private func isCreateLimitError(_ error: Error, message: String) -> Bool {
        if let createHabitError = error as? CreateHabitError, createHabitError == .tooManyHabits {
            return true
        }
        return message == CreateHabitError.tooManyHabits.localizedDescription
    }

    private func showCreateLimitWarning(_ message: String) {
        validationMessage = nil
        createLimitWarningMessage = message
        isCreateLimitWarningDismissed = false
    }

    private func normalizedDraft() -> CreateHabitDraft {
        var normalized = draft
        normalized.useScheduleForHistory = true
        if let endDate = normalized.endDate {
            let today = Calendar.current.startOfDay(for: Date())
            let lowerBound = max(today, Calendar.current.startOfDay(for: normalized.startDate))
            normalized.endDate = max(Calendar.current.startOfDay(for: endDate), lowerBound)
        }
        return normalized
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        validationMessage = nil
        createLimitWarningMessage = nil
        isCreateLimitWarningDismissed = false
        isScheduleWarningDismissed = false
        appState.clearCreateHabitError()
        hasInitialized = true
    }

    private func stageScheduleRule(_ scheduleRule: ScheduleRule) {
        pendingScheduleRule = scheduleRule
    }

    private func applyPendingScheduleRuleIfNeeded() {
        guard let scheduleRule = pendingScheduleRule else { return }
        pendingScheduleRule = nil
        guard draft.scheduleRule != scheduleRule else { return }
        draft.scheduleRule = scheduleRule
    }

    private func dismissKeyboardForNonTextControl() {
        AppDescriptionFieldSupport.dismissKeyboard()
    }
}

#Preview {
    CreateHabitView()
        .environmentObject(AppEnvironment.preview.appState)
}
