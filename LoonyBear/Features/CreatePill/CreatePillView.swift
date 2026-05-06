import SwiftUI
import UIKit

struct CreatePillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    @FocusState private var focusedField: Field?
    @State private var draft = PillDraft()
    @State private var validationMessage: String?
    @State private var isValidationWarningDismissed = false
    @State private var createLimitWarningMessage: String?
    @State private var isCreateLimitWarningDismissed = false
    @State private var isScheduleWarningDismissed = false
    @State private var isEndDateWarningDismissed = false
    @State private var scheduleNoticeMessage: String?
    @State private var scheduleNoticeDismissTask: Task<Void, Never>?
    @State private var pendingScheduleRule: ScheduleRule?
    @State private var isSaving = false
    @State private var isDismissingKeyboardForNonTextControl = false
    @State private var isShowingNotificationSettingsAlert = false

    private enum Field: Hashable {
        case description
    }

    var body: some View {
        ScrollViewReader { proxy in
            AppScreen(backgroundStyle: .pills, topPadding: 8) {
                VStack(alignment: .leading, spacing: 20) {
                    detailsSection
                    scheduleSection
                    descriptionSection
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                    AppDescriptionFieldSupport.dismissKeyboard()
                }
            }
            .overlay(alignment: .bottom) {
                floatingBottomBanners
            }
            .navigationTitle("Create Pill")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: shouldShowDescriptionInset ? 36 : 0)
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

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        savePill()
                    } label: {
                        AppToolbarIconLabel("Save", systemName: "checkmark")
                    }
                    .appToolbarActionTint(isDisabled: !isFormValid || isSaving)
                    .fontWeight(.semibold)
                    .disabled(!isFormValid || isSaving)
                }
            }
            .onChange(of: draft.reminderEnabled) { _, isEnabled in
                guard isEnabled else { return }

                Task {
                    let granted = await pillAppState.requestNotificationAuthorizationIfNeeded()
                    if !granted {
                        validationMessage = nil
                        createLimitWarningMessage = nil
                        isShowingNotificationSettingsAlert = true
                        draft.reminderEnabled = false
                    }
                }
            }
            .onAppear {
                applyPendingScheduleRuleIfNeeded()
            }
            .onChange(of: draft.scheduleRule) { _, _ in
                handleScheduleRuleChange()
                handleEndDateValidationInputsChanged()
                clearEndDateForNeverRepeat(showInfo: true)
            }
            .onChange(of: draft.startDate) { _, _ in
                handleEndDateValidationInputsChanged()
            }
            .onChange(of: draft.endDate) { _, _ in
                handleEndDateValidationInputsChanged()
            }
            .onChange(of: draft.name) { _, _ in
                handleNonScheduleValidationInputChanged()
            }
            .onChange(of: draft.dosage) { _, _ in
                handleNonScheduleValidationInputChanged()
            }
            .appNotificationSettingsAlert(isPresented: $isShowingNotificationSettingsAlert)
            .onChange(of: focusedField) { _, field in
                guard field == .description else { return }
                isDismissingKeyboardForNonTextControl = false
                AppDescriptionFieldSupport.scrollIntoView(
                    with: proxy,
                    focusedField: focusedField,
                    descriptionField: .description,
                    isDismissingKeyboardForNonTextControl: isDismissingKeyboardForNonTextControl,
                    anchor: Field.description
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                AppDescriptionFieldSupport.scrollIntoView(
                    with: proxy,
                    focusedField: focusedField,
                    descriptionField: .description,
                    isDismissingKeyboardForNonTextControl: isDismissingKeyboardForNonTextControl,
                    anchor: Field.description
                )
            }
            .animation(.easeInOut(duration: 0.18), value: validationMessage)
            .animation(.easeInOut(duration: 0.18), value: createLimitWarningMessage)
            .animation(.easeInOut(duration: 0.18), value: scheduleNoticeMessage)
            .animation(.easeInOut(duration: 0.18), value: isCreateLimitWarningDismissed)
            .animation(.easeInOut(duration: 0.18), value: isScheduleWarningDismissed)
            .animation(.easeInOut(duration: 0.18), value: isEndDateWarningDismissed)
            .onDisappear {
                scheduleNoticeDismissTask?.cancel()
            }
        }
    }

    private var detailsSection: some View {
        AppPillDetailsCard(name: $draft.name, dosage: $draft.dosage)
    }

    private var scheduleSection: some View {
        AppCreateScheduleSection(
            startDate: startDateBinding,
            startDateRange: selectableStartDateRange,
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime.default()),
            endDate: $draft.endDate,
            endDateRange: selectableEndDateRange,
            isEndDateEnabled: !draft.scheduleRule.isOneTime,
            repeatSummary: draft.scheduleRule.compactSummary,
            startDateTap: dismissKeyboardForNonTextControl,
            reminderTimeTap: dismissKeyboardForNonTextControl,
            repeatTap: dismissKeyboardForNonTextControl,
            endDateTap: dismissKeyboardForNonTextControl
        ) {
            AppCreateRepeatEditorScreen(
                backgroundStyle: .pills,
                scheduleRule: draft.scheduleRule,
                startDate: draft.startDate,
                allowsNeverRepeat: true,
                onTap: dismissKeyboardForNonTextControl,
                onSave: stageScheduleRule
            )
        }
    }

    private var descriptionSection: some View {
        AppFormCardSection(title: "Description") {
            TextField(AppCopy.pillDescriptionPlaceholder, text: $draft.details, axis: .vertical)
                .appAccentTint()
                .focused($focusedField, equals: .description)
                .lineLimit(3 ... 6)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
        }
        .id(Field.description)
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
        !draft.trimmedName.isEmpty && !draft.trimmedDosage.isEmpty && draft.scheduleRule.isValidSelection && isEndDateValid
    }

    private var isEndDateValid: Bool {
        EndDateValidationSupport.isValid(
            endDate: draft.endDate,
            startDate: draft.startDate,
            lowerBound: selectableEndDateRange.lowerBound,
            schedules: validationScheduleVersions,
            ignoresEndDate: draft.scheduleRule.isOneTime,
            calendar: Calendar.current
        )
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

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { draft.startDate },
            set: { newValue in
                draft.startDate = Calendar.current.startOfDay(for: newValue)
            }
        )
    }

    private var shouldShowDescriptionInset: Bool {
        AppDescriptionFieldSupport.shouldShowInset(
            focusedField: focusedField,
            descriptionField: .description,
            isDismissingKeyboardForNonTextControl: isDismissingKeyboardForNonTextControl
        )
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

                if let message = validationFloatingWarningMessage {
                    AppFloatingWarningBanner(message: message) {
                        isValidationWarningDismissed = true
                    }
                }

                if let message = createLimitWarningMessage, !isCreateLimitWarningDismissed {
                    AppFloatingWarningBanner(message: message) {
                        isCreateLimitWarningDismissed = true
                    }
                }

                if let message = scheduleNoticeMessage {
                    AppFloatingInfoBanner(message: message) {
                        dismissScheduleNotice()
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
            || validationFloatingWarningMessage != nil
            || (createLimitWarningMessage != nil && !isCreateLimitWarningDismissed)
            || scheduleNoticeMessage != nil
    }

    private var scheduleWarningMessage: String? {
        draft.scheduleRule.isValidSelection ? nil : AppCopy.chooseAtLeastOneDay
    }

    private var endDateFloatingWarningMessage: String? {
        guard !isEndDateWarningDismissed else { return nil }
        return endDateValidationMessage
    }

    private var validationFloatingWarningMessage: String? {
        guard !isValidationWarningDismissed else { return nil }
        if let validationMessage {
            return validationMessage
        }
        return visibleNonScheduleInvalidMessage
    }

    private var visibleNonScheduleInvalidMessage: String? {
        if draft.name.isEmpty == false, draft.trimmedName.isEmpty {
            return "Enter a pill name."
        }
        if draft.dosage.isEmpty == false, draft.trimmedDosage.isEmpty {
            return "Enter a dosage."
        }
        return nil
    }

    private func savePill() {
        guard isFormValid else {
            createLimitWarningMessage = nil
            if !draft.scheduleRule.isValidSelection {
                isScheduleWarningDismissed = false
            }
            if !isEndDateValid {
                isEndDateWarningDismissed = false
            }
            isValidationWarningDismissed = false
            validationMessage = nonScheduleInvalidMessage
            return
        }

        isSaving = true
        validationMessage = nil
        createLimitWarningMessage = nil
        let savedDraft = normalizedDraft()

        Task {
            do {
                let pillID = try await pillAppState.createPill(from: savedDraft)
                isSaving = false
                dismiss()

                guard savedDraft.reminderEnabled else { return }
                await pillAppState.prepareReminderNotifications(forPillID: pillID)
            } catch {
                let message = pillAppState.actionErrorMessage ?? UserFacingErrorMessage.text(for: error)
                if isCreateLimitError(error, message: message) {
                    showCreateLimitWarning(message)
                } else {
                    isValidationWarningDismissed = false
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

    private func handleNonScheduleValidationInputChanged() {
        isValidationWarningDismissed = false
        if nonScheduleInvalidMessage == nil,
           validationMessage == "Enter a pill name." || validationMessage == "Enter a dosage." {
            validationMessage = nil
        }
    }

    private func clearEndDateForNeverRepeat(showInfo: Bool) {
        guard draft.scheduleRule.isOneTime, draft.endDate != nil else { return }
        draft.endDate = nil

        if showInfo {
            presentScheduleNotice(AppCopy.endDateRemovedForNeverRepeat)
        }
    }

    private func isCreateLimitError(_ error: Error, message: String) -> Bool {
        if let pillRepositoryError = error as? PillRepositoryError,
           case .tooManyPills = pillRepositoryError {
            return true
        }
        return message == PillRepositoryError.tooManyPills.localizedDescription
    }

    private func showCreateLimitWarning(_ message: String) {
        validationMessage = nil
        createLimitWarningMessage = message
        isValidationWarningDismissed = false
        isCreateLimitWarningDismissed = false
    }

    private func normalizedDraft() -> PillDraft {
        var normalized = draft
        normalized.useScheduleForHistory = true
        if normalized.scheduleRule.isOneTime {
            normalized.endDate = nil
        }
        if let endDate = normalized.endDate {
            normalized.endDate = Calendar.current.startOfDay(for: endDate)
        }
        return normalized
    }

    private func presentScheduleNotice(_ message: String) {
        scheduleNoticeDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            scheduleNoticeMessage = message
        }

        scheduleNoticeDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scheduleNoticeMessage = nil
                }
            }
        }
    }

    private func dismissScheduleNotice() {
        scheduleNoticeDismissTask?.cancel()
        scheduleNoticeDismissTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            scheduleNoticeMessage = nil
        }
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

    private var nonScheduleInvalidMessage: String? {
        if draft.trimmedName.isEmpty {
            return "Enter a pill name."
        }
        if draft.trimmedDosage.isEmpty {
            return "Enter a dosage."
        }
        return nil
    }

    private func dismissKeyboardForNonTextControl() {
        AppDescriptionFieldSupport.dismissKeyboardForNonTextControl(
            focusedField: focusedField,
            descriptionField: Field.description,
            setFocusedField: { focusedField = $0 },
            setIsDismissingKeyboardForNonTextControl: { isDismissingKeyboardForNonTextControl = $0 }
        )
    }
}

#Preview {
    NavigationStack {
        CreatePillView()
    }
    .environmentObject(AppEnvironment.preview.pillAppState)
}
