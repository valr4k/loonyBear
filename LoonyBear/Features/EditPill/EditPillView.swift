import SwiftUI
import UIKit

struct EditPillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    private let onSaveSuccess: () -> Void
    @FocusState private var focusedField: Field?
    @State private var draft: EditPillDraft
    @State private var displayedMonth: Date
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var isDismissingKeyboardForNonTextControl = false
    @State private var isShowingDeleteConfirmation = false

    private enum Field: Hashable {
        case description
    }

    init(details: PillDetailsProjection, onSaveSuccess: @escaping () -> Void = {}) {
        self.onSaveSuccess = onSaveSuccess
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
                    Text("Delete")
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
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
            .navigationTitle(draft.name.isEmpty ? "Edit Pill" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: shouldShowDescriptionInset ? 36 : 0)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Save")
                    .disabled(!isFormValid || isSaving)
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
                        validationMessage = AppCopy.notificationsRequired
                        draft.reminderEnabled = false
                    }
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
        let savedDraft = normalizedDraft()

        Task {
            do {
                try await pillAppState.updatePill(from: savedDraft)
                isSaving = false
                onSaveSuccess()
                dismiss()

                await pillAppState.syncNotificationsAfterPillUpdate(from: savedDraft)
            } catch {
                validationMessage = pillAppState.actionErrorMessage ?? error.localizedDescription
                isSaving = false
            }
        }
    }

    private func deletePill() {
        isSaving = true
        validationMessage = nil

        Task {
            await pillAppState.deletePill(id: draft.id)
            if let errorMessage = pillAppState.actionErrorMessage {
                validationMessage = errorMessage
                isSaving = false
                return
            }

            isSaving = false
            dismiss()
        }
    }

    private func normalizedDraft() -> EditPillDraft {
        var normalized = draft
        normalized.skippedDays.subtract(normalized.takenDays)
        return normalized
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
        AppScheduleEditorScreen(
            backgroundStyle: .pills,
            scheduleDays: $scheduleDays,
            onTap: dismissKeyboardForNonTextControl
        )
    }
}

private struct PillHistoryLegend: View {
    var body: some View {
        AppLegend(items: [
            (label: "Taken", color: .blue),
            (label: "Skipped", color: .red),
        ])
    }
}
