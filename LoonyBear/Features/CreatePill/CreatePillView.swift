import SwiftUI
import UIKit

struct CreatePillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    @FocusState private var focusedField: Field?
    @State private var draft = PillDraft()
    @State private var validationMessage: String?
    @State private var createLimitWarningMessage: String?
    @State private var isCreateLimitWarningDismissed = false
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
                    notificationsSection
                    historySection
                    descriptionSection

                    if let validationMessage {
                        AppValidationBanner(message: validationMessage)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                    AppDescriptionFieldSupport.dismissKeyboard()
                }
            }
            .overlay(alignment: .bottom) {
                createLimitWarningBanner
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
                    .appAccentTint()
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
            .animation(.easeInOut(duration: 0.18), value: isCreateLimitWarningDismissed)
        }
    }

    private var detailsSection: some View {
        AppPillDetailsCard(name: $draft.name, dosage: $draft.dosage)
    }

    private var historySection: some View {
        AppFormCardSection(title: "History") {
            AppStartDatePickerRow(
                date: $draft.startDate,
                range: selectableStartDateRange,
                onTap: dismissKeyboardForNonTextControl
            )
        }
    }

    private var notificationsSection: some View {
        AppNotificationSettingsSection(
            scheduleSummary: draft.scheduleDays.compactSummaryOrPlaceholder,
            scheduleTap: dismissKeyboardForNonTextControl,
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime.default()),
            reminderTimeTap: dismissKeyboardForNonTextControl
        ) {
            CreatePillScheduleView(
                scheduleDays: $draft.scheduleDays,
                useScheduleForHistory: $draft.useScheduleForHistory,
                dismissKeyboardForNonTextControl: dismissKeyboardForNonTextControl
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

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && !draft.trimmedDosage.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private var shouldShowDescriptionInset: Bool {
        AppDescriptionFieldSupport.shouldShowInset(
            focusedField: focusedField,
            descriptionField: .description,
            isDismissingKeyboardForNonTextControl: isDismissingKeyboardForNonTextControl
        )
    }

    @ViewBuilder
    private var createLimitWarningBanner: some View {
        if let message = createLimitWarningMessage, !isCreateLimitWarningDismissed {
            AppFloatingWarningBanner(message: message) {
                isCreateLimitWarningDismissed = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .zIndex(1)
        }
    }

    private func savePill() {
        guard isFormValid else {
            createLimitWarningMessage = nil
            validationMessage = invalidMessage
            return
        }

        isSaving = true
        validationMessage = nil
        createLimitWarningMessage = nil
        let savedDraft = draft

        Task {
            do {
                let pillID = try await pillAppState.createPill(from: savedDraft)
                isSaving = false
                dismiss()

                guard savedDraft.reminderEnabled else { return }
                await pillAppState.prepareReminderNotifications(forPillID: pillID)
            } catch {
                let message = pillAppState.actionErrorMessage ?? error.localizedDescription
                if isCreateLimitError(error, message: message) {
                    showCreateLimitWarning(message)
                } else {
                    validationMessage = message
                }
                isSaving = false
            }
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
        isCreateLimitWarningDismissed = false
    }

    private var invalidMessage: String {
        if draft.trimmedName.isEmpty {
            return "Pill name is required."
        }
        if draft.trimmedDosage.isEmpty {
            return "Dosage is required."
        }
        return AppCopy.chooseAtLeastOneDay
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

private struct CreatePillScheduleView: View {
    @Binding var scheduleDays: WeekdaySet
    @Binding var useScheduleForHistory: Bool
    let dismissKeyboardForNonTextControl: () -> Void

    var body: some View {
        AppScheduleEditorPopoverContent(
            scheduleDays: $scheduleDays,
            onTap: dismissKeyboardForNonTextControl,
            useScheduleForHistory: $useScheduleForHistory,
            helperText: useScheduleForHistory
                ? AppCopy.pillHistoryFollowsSchedule
                : AppCopy.pillHistoryCountsEveryDay
        )
    }
}
