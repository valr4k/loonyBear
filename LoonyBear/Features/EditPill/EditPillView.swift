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
            historyMode: details.historyMode,
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
                AppCard {
                    VStack(alignment: .leading, spacing: 0) {
                        CenteredInputField(
                            text: $draft.name,
                            placeholder: "Pill name",
                            capitalization: .sentences,
                            autocorrectionType: .default
                        )
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)

                        AppSectionDivider()

                        CenteredInputField(
                            text: $draft.dosage,
                            placeholder: "Dosage",
                            capitalization: .none,
                            autocorrectionType: .no
                        )
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)

                        AppSectionDivider()

                        AppValueRow(
                            title: "Start Date",
                            value: draft.startDate.formatted(date: .abbreviated, time: .omitted)
                        )

                        AppSectionDivider()

                        HStack(spacing: 16) {
                            Text("Reminder")
                                .foregroundStyle(.primary)

                            Spacer()

                            Toggle("", isOn: $draft.reminderEnabled)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                        if draft.reminderEnabled {
                            AppSectionDivider()

                            DatePicker(
                                "Time",
                                selection: reminderDateBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.compact)
                            .simultaneousGesture(TapGesture().onEnded {
                                dismissKeyboardForNonTextControl()
                            })
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 0) {
                        InlineDaysSelector(selection: scheduleDaysBinding)
                            .simultaneousGesture(TapGesture().onEnded {
                                dismissKeyboardForNonTextControl()
                            })

                        AppSectionDivider()

                        HStack(spacing: 16) {
                            Text("Use schedule for history?")
                                .foregroundStyle(.primary)

                            Spacer()

                            Toggle("", isOn: useScheduleForHistoryBinding)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                        if draft.scheduleDays.rawValue == 0 {
                            HStack {
                                AppInlineErrorText(text: AppCopy.chooseAtLeastOneDay)
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppCard {
                        PillHistoryCalendarView(
                            month: displayedMonth,
                            editableDays: Set(editableHistoryDays),
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

                AppCard {
                    TextField(AppCopy.pillDescriptionPlaceholder, text: $draft.details, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(3 ... 6)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                }
                .id(Field.description)

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
                guard focusedField == .description, !isDismissingKeyboardForNonTextControl else { return }
                scrollDescriptionIntoView(with: proxy)
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
                scrollDescriptionIntoView(with: proxy)
            }
            .animation(.easeInOut(duration: 0.18), value: validationMessage)
        }
    }

    private var editableHistoryDays: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        let earliest = max(
            Calendar.current.startOfDay(for: draft.startDate),
            Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today
        )

        return stride(from: 0, through: 29, by: 1)
            .compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
            .map { Calendar.current.startOfDay(for: $0) }
            .filter { $0 >= earliest && $0 <= today }
    }

    private var availableMonths: [Date] {
        let months = Set(
            editableHistoryDays.compactMap {
                Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: $0))
            }
        )
        return months.sorted()
    }

    private var reminderDateBinding: Binding<Date> {
        Binding {
            let components = DateComponents(hour: draft.reminderTime.hour, minute: draft.reminderTime.minute)
            return Calendar.current.date(from: components) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            let fallback = ReminderTime.default()
            draft.reminderTime = ReminderTime(
                hour: components.hour ?? fallback.hour,
                minute: components.minute ?? fallback.minute
            )
        }
    }

    private var scheduleDaysBinding: Binding<WeekdaySet> {
        Binding(
            get: { draft.scheduleDays },
            set: { draft.scheduleDays = $0 }
        )
    }

    private var useScheduleForHistoryBinding: Binding<Bool> {
        Binding(
            get: { draft.historyMode.usesScheduleForHistory },
            set: { draft.historyMode = $0 ? .scheduleBased : .everyDay }
        )
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && !draft.trimmedDosage.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private var shouldShowDescriptionInset: Bool {
        focusedField == .description && !isDismissingKeyboardForNonTextControl
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
                try pillAppState.updatePill(from: savedDraft)
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

        pillAppState.deletePill(id: draft.id)
        if let errorMessage = pillAppState.actionErrorMessage {
            validationMessage = errorMessage
            isSaving = false
            return
        }

        isSaving = false
        dismiss()
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

    private func scrollDescriptionIntoView(with proxy: ScrollViewProxy) {
        guard focusedField == .description, !isDismissingKeyboardForNonTextControl else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(Field.description, anchor: .bottom)
            }
        }
    }

    private func dismissKeyboardForNonTextControl() {
        guard focusedField == .description else { return }

        isDismissingKeyboardForNonTextControl = true
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isDismissingKeyboardForNonTextControl = false
        }
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
