import SwiftUI
import UIKit

struct CreateHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState

    @State private var draft = CreateHabitDraft()
    @State private var validationMessage: String?
    @State private var isSaving = false

    var body: some View {
        AppScreen(backgroundStyle: .habits, topPadding: 8) {
            VStack(alignment: .leading, spacing: 20) {
                typeSection
                detailsSection
                daysSection
                if let validationMessage {
                    validationBanner(validationMessage)
                }
            }
        }
        .navigationTitle("Create Habit")
        .navigationBarTitleDisplayMode(.inline)
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
                    saveHabit()
                } label: {
                    Image(systemName: "checkmark")
                }
                .fontWeight(.semibold)
                .accessibilityLabel("Save")
                .disabled(!isFormValid || isSaving)
            }
        }
        .onAppear {
            validationMessage = nil
            appState.clearCreateHabitError()
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
        .animation(.easeInOut(duration: 0.18), value: validationMessage)
    }

    private var typeSection: some View {
        AppCard {
            Picker("Habit Type", selection: $draft.type) {
                ForEach(HabitType.allCases) { type in
                    Text(type.sectionTitle).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
        }
    }

    private var detailsSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 0) {
                HabitNameInputField(text: $draft.name)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)

                if shouldShowNameValidation {
                    AppSectionDivider()

                    Text("Habit name is required.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }

                AppSectionDivider()

                DatePicker(
                    "Start Date",
                    selection: $draft.startDate,
                    in: selectableStartDateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)

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
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppCard {
                VStack(alignment: .leading, spacing: 0) {
                    InlineDaysSelector(selection: scheduleDaysBinding)

                    AppSectionDivider()

                    HStack(spacing: 16) {
                        Text("Use schedule for history?")
                            .foregroundStyle(.primary)

                        Spacer()

                        Toggle("", isOn: $draft.useScheduleForHistory)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)

                    if shouldShowScheduleValidation {
                        HStack {
                            AppInlineErrorText(text: AppCopy.chooseAtLeastOneDay)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                    }
                }
            }

            AppHelperText(text: historyHelperText)
        }
    }

    private func validationBanner(_ message: String) -> some View {
        AppValidationBanner(message: message)
    }

    private var reminderDateBinding: Binding<Date> {
        Binding {
            let components = DateComponents(hour: draft.reminderTime.hour, minute: draft.reminderTime.minute)
            return Calendar.current.date(from: components) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            draft.reminderTime = ReminderTime(
                hour: components.hour ?? 20,
                minute: components.minute ?? 0
            )
        }
    }

    private var selectableStartDateRange: ClosedRange<Date> {
        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        let earliest = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -29, to: today) ?? today
        return earliest ... today
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private var shouldShowNameValidation: Bool {
        draft.name.isEmpty == false && draft.trimmedName.isEmpty
    }

    private var shouldShowScheduleValidation: Bool {
        draft.scheduleDays.rawValue == 0
    }

    private var historyHelperText: String {
        draft.useScheduleForHistory
            ? AppCopy.habitHistoryFollowsSchedule
            : AppCopy.habitHistoryCountsEveryDay
    }

    private var scheduleDaysBinding: Binding<WeekdaySet> {
        Binding(
            get: { draft.scheduleDays },
            set: { newValue in
                draft.scheduleDays = newValue
            }
        )
    }

    private func saveHabit() {
        guard isFormValid else {
            validationMessage = draft.trimmedName.isEmpty
                ? "Habit name is required."
                : AppCopy.chooseAtLeastOneDay
            return
        }

        isSaving = true
        validationMessage = nil
        let savedDraft = draft

        Task {
            do {
                let habitID = try appState.createHabit(from: savedDraft)
                isSaving = false
                dismiss()

                guard savedDraft.reminderEnabled else { return }
                await appState.prepareReminderNotifications(forHabitID: habitID)
            } catch {
                validationMessage = appState.createHabitErrorMessage ?? error.localizedDescription
                isSaving = false
            }
        }
    }
}

struct CenteredInputField: View {
    @Binding var text: String
    let placeholder: String
    let capitalization: UITextAutocapitalizationType
    let autocorrectionType: UITextAutocorrectionType

    var body: some View {
        CenteredInputTextField(
            text: $text,
            placeholder: placeholder,
            capitalization: capitalization,
            autocorrectionType: autocorrectionType
        )
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 28)
    }
}

struct HabitNameInputField: View {
    @Binding var text: String

    var body: some View {
        CenteredInputField(
            text: $text,
            placeholder: "Enter habit name",
            capitalization: .sentences,
            autocorrectionType: .default
        )
    }
}

private struct CenteredInputTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let capitalization: UITextAutocapitalizationType
    let autocorrectionType: UITextAutocorrectionType

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = CenteredCaretTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.adjustsFontForContentSizeCategory = true
        textField.autocapitalizationType = capitalization
        textField.autocorrectionType = autocorrectionType
        textField.borderStyle = .none
        textField.clearButtonMode = .never
        textField.returnKeyType = .done
        textField.enablesReturnKeyAutomatically = false
        textField.font = .systemFont(ofSize: 20, weight: .semibold)
        textField.textColor = .label
        textField.tintColor = .systemBlue
        textField.textAlignment = .center
        textField.contentHorizontalAlignment = .center
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.tertiaryLabel,
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            ]
        )
        textField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func editingChanged(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

private final class CenteredCaretTextField: UITextField {
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard (text ?? "").isEmpty else { return rect }
        rect.origin.x = bounds.midX - (rect.width / 2)
        return rect
    }
}

private struct CreateHabitSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        content
    }
}

#Preview {
    CreateHabitView()
        .environmentObject(AppEnvironment.preview.appState)
}
