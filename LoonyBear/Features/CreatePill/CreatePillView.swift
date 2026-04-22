import SwiftUI
import UIKit

struct CreatePillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    @FocusState private var focusedField: Field?
    @State private var draft = PillDraft()
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var isDismissingKeyboardForNonTextControl = false

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
                }
            }
            .navigationTitle("Create Pill")
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
                        savePill()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Save")
                    .disabled(!isFormValid || isSaving)
                }
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

    private func savePill() {
        guard isFormValid else {
            validationMessage = invalidMessage
            return
        }

        isSaving = true
        validationMessage = nil
        var savedDraft = draft
        savedDraft.takenDays = generatedTakenDays(from: draft)

        Task {
            do {
                let pillID = try await pillAppState.createPill(from: savedDraft)
                isSaving = false
                dismiss()

                guard savedDraft.reminderEnabled else { return }
                await pillAppState.prepareReminderNotifications(forPillID: pillID)
            } catch {
                validationMessage = pillAppState.actionErrorMessage ?? error.localizedDescription
                isSaving = false
            }
        }
    }

    private func generatedTakenDays(from draft: PillDraft) -> Set<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: draft.startDate)
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }
        let end = calendar.startOfDay(for: yesterday)
        guard start <= end else { return [] }

        var dates: Set<Date> = []
        var cursor = start
        while cursor <= end {
            if draft.useScheduleForHistory {
                if draft.scheduleDays.contains(calendar.weekdaySet(for: cursor)) {
                    dates.insert(cursor)
                }
            } else {
                dates.insert(cursor)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return dates
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
        AppScheduleEditorScreen(
            backgroundStyle: .pills,
            scheduleDays: $scheduleDays,
            onTap: dismissKeyboardForNonTextControl,
            useScheduleForHistory: $useScheduleForHistory,
            helperText: useScheduleForHistory
                ? AppCopy.pillHistoryFollowsSchedule
                : AppCopy.pillHistoryCountsEveryDay
        )
    }
}
