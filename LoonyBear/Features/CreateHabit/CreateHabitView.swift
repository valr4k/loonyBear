import SwiftUI

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
                nameSection
                notificationsSection
                historySection
                if let validationMessage {
                    AppValidationBanner(message: validationMessage)
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

    private var nameSection: some View {
        AppHabitNameCard(text: $draft.name, showsValidation: shouldShowNameValidation) {
            AppInlineErrorText(text: "Habit name is required.")
        }
    }

    private var historySection: some View {
        AppFormCardSection(title: "History") {
            AppStartDatePickerRow(
                date: $draft.startDate,
                range: selectableStartDateRange
            )
        }
    }

    private var notificationsSection: some View {
        AppNotificationSettingsSection(
            scheduleSummary: draft.scheduleDays.compactSummaryOrPlaceholder,
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime(hour: 20, minute: 0))
        ) {
            CreateHabitScheduleView(
                scheduleDays: $draft.scheduleDays,
                useScheduleForHistory: $draft.useScheduleForHistory
            )
        }
    }

    private var selectableStartDateRange: ClosedRange<Date> {
        StartDateSelectionWindow.range(offset: DateComponents(day: -29))
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private var shouldShowNameValidation: Bool {
        draft.name.isEmpty == false && draft.trimmedName.isEmpty
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
                let habitID = try await appState.createHabit(from: savedDraft)
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

#Preview {
    CreateHabitView()
        .environmentObject(AppEnvironment.preview.appState)
}

private struct CreateHabitScheduleView: View {
    @Binding var scheduleDays: WeekdaySet
    @Binding var useScheduleForHistory: Bool

    var body: some View {
        AppScheduleEditorScreen(
            backgroundStyle: .habits,
            scheduleDays: $scheduleDays,
            useScheduleForHistory: $useScheduleForHistory,
            helperText: useScheduleForHistory
                ? AppCopy.habitHistoryFollowsSchedule
                : AppCopy.habitHistoryCountsEveryDay
        )
    }
}
