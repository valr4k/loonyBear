import SwiftUI
import UIKit

struct EditPillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    private let onSaveSuccess: () -> Void
    private let onDeleteSuccess: () -> Void
    private let showsCloseButton: Bool
    private let requiredPastScheduledDays: Set<Date>
    private let activeOverdueDay: Date?
    @FocusState private var focusedField: Field?
    @State private var draft: EditPillDraft
    @State private var displayedMonth: Date
    @State private var validationMessage: String?
    @State private var historyValidationMessage: String?
    @State private var isSaving = false
    @State private var isDismissingKeyboardForNonTextControl = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingNotificationSettingsAlert = false
    @State private var isHistoryWarningDismissed = false

    private enum Field: Hashable {
        case description
    }

    init(
        details: PillDetailsProjection,
        showsCloseButton: Bool = true,
        onSaveSuccess: @escaping () -> Void = {},
        onDeleteSuccess: @escaping () -> Void = {}
    ) {
        self.onSaveSuccess = onSaveSuccess
        self.onDeleteSuccess = onDeleteSuccess
        self.showsCloseButton = showsCloseButton
        requiredPastScheduledDays = details.requiredPastScheduledDays
        activeOverdueDay = details.activeOverdueDay
        _draft = State(initialValue: EditPillDraft(
            id: details.id,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        ))
        _displayedMonth = State(initialValue: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date())
    }

    var body: some View {
        ScrollViewReader { proxy in
            AppScreen(backgroundStyle: .pills, topPadding: 8) {
                detailsSection
                notificationsSection
                historySection

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Calendar")

                    AppCard {
                        PillHistoryCalendarView(
                            month: displayedMonth,
                            editableDays: editableHistoryDays,
                            takenDays: $draft.takenDays,
                            skippedDays: $draft.skippedDays,
                            availableMonths: availableMonths,
                            onMonthChange: { displayedMonth = $0 }
                        )
                        .simultaneousGesture(TapGesture().onEnded {
                            dismissKeyboardForNonTextControl()
                        })
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    }

                    PillHistoryLegend()
                    AppHelperText(text: AppCopy.pillHistoryHint)
                }

                descriptionSection

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
                .disabled(isSaving)
                .confirmationDialog("Delete Pill?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
                    Button("Yes", role: .destructive) {
                        deletePill()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This pill will be permanently deleted.")
                }

                if let validationMessage {
                    AppValidationBanner(message: validationMessage)
                }
            }
            .overlay(alignment: .bottom) {
                floatingHistoryWarningBanner
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
                AppDescriptionFieldSupport.dismissKeyboard()
            }
            .navigationTitle(draft.name.isEmpty ? "Edit Pill" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: shouldShowDescriptionInset ? 36 : 0)
            }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            AppToolbarIconLabel("Close", systemName: "xmark")
                        }
                        .appAccentTint()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        AppToolbarIconLabel("Save", systemName: "checkmark")
                    }
                    .appAccentTint()
                    .fontWeight(.semibold)
                    .disabled(!isFormValid || hasMissingPastDays || isSaving)
                }
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
            .onChange(of: draft.reminderEnabled) { _, isEnabled in
                guard isEnabled else { return }

                Task {
                    let granted = await pillAppState.requestNotificationAuthorizationIfNeeded()
                    if !granted {
                        validationMessage = nil
                        isShowingNotificationSettingsAlert = true
                        draft.reminderEnabled = false
                    }
                }
            }
            .appNotificationSettingsAlert(isPresented: $isShowingNotificationSettingsAlert)
            .onChange(of: draft.takenDays) { _, _ in
                historyValidationMessage = nil
            }
            .onChange(of: draft.skippedDays) { _, _ in
                historyValidationMessage = nil
            }
            .onChange(of: hasMissingPastDays) { _, hasMissingPastDays in
                if !hasMissingPastDays {
                    isHistoryWarningDismissed = false
                }
            }
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
            .animation(.easeInOut(duration: 0.18), value: validationMessage)
            .animation(.easeInOut(duration: 0.18), value: historyValidationMessage)
            .animation(.easeInOut(duration: 0.18), value: floatingHistoryWarningMessage)
            .animation(.easeInOut(duration: 0.18), value: isHistoryWarningDismissed)
        }
    }

    private var detailsSection: some View {
        AppPillDetailsCard(name: $draft.name, dosage: $draft.dosage)
    }

    private var historySection: some View {
        AppFormCardSection(title: "History") {
            AppStartDateValueRow(date: draft.startDate)
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
            EditPillScheduleView(
                scheduleDays: $draft.scheduleDays,
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

    private var editableHistoryDays: Set<Date> {
        EditableHistoryWindow.dates(startDate: draft.startDate)
    }

    private var availableMonths: [Date] {
        HistoryMonthWindow.months(containing: editableHistoryDays)
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && !draft.trimmedDosage.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private var currentMissingPastDays: [Date] {
        let normalized = normalizedDraft()
        return EditableHistoryValidation.missingPastDays(
            editableDays: requiredPastScheduledDays,
            positiveDays: normalized.takenDays,
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

    private var floatingHistoryWarningMessage: String? {
        currentHistoryReviewMessage ?? historyValidationMessage
    }

    @ViewBuilder
    private var floatingHistoryWarningBanner: some View {
        if let message = floatingHistoryWarningMessage, !isHistoryWarningDismissed {
            AppFloatingWarningBanner(message: message) {
                isHistoryWarningDismissed = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .zIndex(1)
        }
    }

    private var shouldShowDescriptionInset: Bool {
        AppDescriptionFieldSupport.shouldShowInset(
            focusedField: focusedField,
            descriptionField: .description,
            isDismissingKeyboardForNonTextControl: isDismissingKeyboardForNonTextControl
        )
    }

    private func save() {
        guard isFormValid else {
            validationMessage = invalidMessage
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
                try await pillAppState.updatePill(from: savedDraft)
                isSaving = false
                onSaveSuccess()
                dismiss()

                await pillAppState.syncNotificationsAfterPillUpdate(from: savedDraft)
            } catch {
                if let error = error as? EditableHistoryValidationError {
                    historyValidationMessage = error.localizedDescription
                    if case .missingPillPastDays(let days) = error, let firstDay = days.first {
                        displayedMonth = month(containing: firstDay)
                    }
                } else {
                    validationMessage = pillAppState.actionErrorMessage ?? error.localizedDescription
                }
                isSaving = false
            }
        }
    }

    private func deletePill() {
        isSaving = true
        validationMessage = nil
        historyValidationMessage = nil

        Task {
            await pillAppState.deletePill(id: draft.id)
            if let errorMessage = pillAppState.actionErrorMessage {
                validationMessage = errorMessage
                isSaving = false
                return
            }

            isSaving = false
            onDeleteSuccess()
            dismiss()
        }
    }

    private func normalizedDraft() -> EditPillDraft {
        var normalized = draft
        normalized.skippedDays.subtract(normalized.takenDays)
        return normalized
    }

    private func historyReviewMessage(for missingPastDays: [Date]) -> String {
        if isOnlyActiveOverdueMissing(missingPastDays) {
            return AppCopy.overdueScheduledDayEditMessage(actionLabel: "Taken")
        }
        return EditableHistoryValidationError.missingPillPastDays(missingPastDays).localizedDescription
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

private struct EditPillScheduleView: View {
    @Binding var scheduleDays: WeekdaySet
    let dismissKeyboardForNonTextControl: () -> Void

    var body: some View {
        AppScheduleEditorPopoverContent(
            scheduleDays: $scheduleDays,
            onTap: dismissKeyboardForNonTextControl
        )
    }
}

private struct PillHistoryLegend: View {
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    var body: some View {
        AppLegend(items: [
            AppLegendEntry(label: "Taken", color: appTint.accentColor, fillOpacity: 1, strokeOpacity: 0),
            AppLegendEntry(label: "Skipped", color: .red),
        ])
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
    }
}
