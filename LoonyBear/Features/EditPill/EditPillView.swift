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
            takenDays: details.takenDays
        ))
        _displayedMonth = State(initialValue: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date())
    }

    var body: some View {
        ScrollViewReader { proxy in
            AppScreen(backgroundStyle: .pills) {
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
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                        }
                    }
                }

                AppCard {
                    InlineDaysSelector(selection: scheduleDaysBinding)
                    if draft.scheduleDays.rawValue == 0 {
                        HStack {
                            Text("Select at least one day.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppCard {
                        PillHistoryCalendarView(
                            month: displayedMonth,
                            editableDays: Set(editableTakenDays),
                            selectedDays: $draft.takenDays,
                            availableMonths: availableMonths,
                            onMonthChange: { displayedMonth = $0 }
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    }

                    Text("You can edit the last 30 days, including today, but not before the start date.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                AppCard {
                    TextField("Description (optional)", text: $draft.details, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(3 ... 6)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                }
                .id(Field.description)

                if let validationMessage {
                    AppValidationBanner(message: validationMessage)
                }
            }
            .navigationTitle(draft.name.isEmpty ? "Edit Pill" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: focusedField == .description ? 36 : 0)
            }
            .toolbar {
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
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                guard focusedField == .description else { return }
                scrollDescriptionIntoView(with: proxy)
            }
            .onChange(of: draft.reminderEnabled) { _, isEnabled in
                guard isEnabled else { return }

                Task {
                    let granted = await pillAppState.requestNotificationAuthorizationIfNeeded()
                    if !granted {
                        validationMessage = "Enable notifications in Settings to use reminders."
                        draft.reminderEnabled = false
                    }
                }
            }
            .onChange(of: focusedField) { _, field in
                guard field == .description else { return }
                scrollDescriptionIntoView(with: proxy)
            }
        }
    }

    private var editableTakenDays: [Date] {
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
            editableTakenDays.compactMap {
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

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && !draft.trimmedDosage.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private func save() {
        guard isFormValid else {
            validationMessage = invalidMessage
            return
        }

        isSaving = true
        validationMessage = nil
        let savedDraft = draft

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

    private var invalidMessage: String {
        if draft.trimmedName.isEmpty {
            return "Pill name is required."
        }
        if draft.trimmedDosage.isEmpty {
            return "Dosage is required."
        }
        return "Select at least one day."
    }

    private func scrollDescriptionIntoView(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(Field.description, anchor: .bottom)
            }
        }
    }
}
