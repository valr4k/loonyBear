import SwiftUI
import UIKit

struct CreatePillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    @FocusState private var focusedField: Field?
    @State private var draft = PillDraft()
    @State private var validationMessage: String?
    @State private var isSaving = false

    private enum Field: Hashable {
        case description
    }

    var body: some View {
        ScrollViewReader { proxy in
            AppScreen(backgroundStyle: .pills) {
                VStack(alignment: .leading, spacing: 20) {
                    detailsSection
                    daysSection
                    descriptionSection

                    if let validationMessage {
                        AppValidationBanner(message: validationMessage)
                    }
                }
            }
            .navigationTitle("Create Pill")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: focusedField == .description ? 36 : 0)
            }
            .toolbar {
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
                        validationMessage = "Enable notifications in Settings to use reminders."
                        draft.reminderEnabled = false
                    }
                }
            }
            .onChange(of: focusedField) { _, field in
                guard field == .description else { return }
                scrollDescriptionIntoView(with: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                guard focusedField == .description else { return }
                scrollDescriptionIntoView(with: proxy)
            }
        }
    }

    private var detailsSection: some View {
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
            }

            Text(historyHelperText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var descriptionSection: some View {
        AppCard {
            TextField("Description (optional)", text: $draft.details, axis: .vertical)
                .focused($focusedField, equals: .description)
                .lineLimit(3 ... 6)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
        }
        .id(Field.description)
    }

    private var selectableStartDateRange: ClosedRange<Date> {
        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        let earliest = Calendar.autoupdatingCurrent.date(byAdding: .year, value: -5, to: today) ?? today
        return earliest ... today
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

    private var historyHelperText: String {
        draft.useScheduleForHistory
            ? "Count only scheduled days from the start date."
            : "Count every day from the start date."
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
                let pillID = try pillAppState.createPill(from: savedDraft)
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

#Preview {
    NavigationStack {
        CreatePillView()
    }
    .environmentObject(AppEnvironment.preview.pillAppState)
}

private extension Calendar {
    func weekdaySet(for date: Date) -> WeekdaySet {
        switch component(.weekday, from: date) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }
}
