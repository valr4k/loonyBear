import SwiftUI

struct EditHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState

    private let onSaveSuccess: () -> Void
    private let onDeleteSuccess: () -> Void
    private let onArchiveSuccess: () -> Void
    private let showsCloseButton: Bool
    private let requiredPastScheduledDays: Set<Date>
    private let scheduledDates: Set<Date>
    private let scheduleHistory: [HabitScheduleVersion]
    private let activeOverdueDay: Date?
    private let originalScheduleRule: ScheduleRule
    @State private var draft: EditHabitDraft
    @State private var pendingScheduleRule: ScheduleRule?
    @State private var validationMessage: String?
    @State private var isValidationWarningDismissed = false
    @State private var historyValidationMessage: String?
    @State private var displayedMonth: Date
    @State private var isSaving = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingArchiveConfirmation = false
    @State private var isShowingNotificationSettingsAlert = false
    @State private var isHistoryWarningDismissed = false
    @State private var isScheduleWarningDismissed = false
    @State private var isEndDateWarningDismissed = false
    @State private var isArchived: Bool

    init(
        details: HabitDetailsProjection,
        showsCloseButton: Bool = true,
        onSaveSuccess: @escaping () -> Void = {},
        onDeleteSuccess: @escaping () -> Void = {},
        onArchiveSuccess: @escaping () -> Void = {}
    ) {
        self.onSaveSuccess = onSaveSuccess
        self.onDeleteSuccess = onDeleteSuccess
        self.onArchiveSuccess = onArchiveSuccess
        self.showsCloseButton = showsCloseButton
        requiredPastScheduledDays = details.requiredPastScheduledDays
        scheduledDates = details.scheduledDates
        scheduleHistory = details.scheduleHistory
        activeOverdueDay = details.activeOverdueDay
        originalScheduleRule = details.scheduleRule
        _draft = State(initialValue: EditHabitDraft(
            id: details.id,
            type: details.type,
            startDate: details.startDate,
            endDate: details.endDate,
            name: details.name,
            scheduleRule: details.scheduleRule,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            completedDays: details.completedDays,
            skippedDays: details.skippedDays
        ))
        _displayedMonth = State(initialValue: Self.initialDisplayedMonth(startDate: details.startDate))
        _isArchived = State(initialValue: details.isArchived)
    }

    var body: some View {
        AppScreen(backgroundStyle: .habits, topPadding: 8) {
            nameSection
            scheduleSection

            VStack(alignment: .leading, spacing: 8) {
                AppFormSectionHeader(title: "Calendar")

                AppCard {
                    HabitHistoryCalendarView(
                        month: displayedMonth,
                        editableDays: editableHistoryDays,
                        scheduledDates: previewScheduledDates,
                        completedDays: $draft.completedDays,
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

            }

            actionButtons
        }
        .overlay(alignment: .bottom) {
            floatingBottomBanners
        }
        .contentShape(Rectangle())
        .onTapGesture {
            AppDescriptionFieldSupport.dismissKeyboard()
        }
        .navigationTitle("Edit Habit")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .alert("Delete Habit?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteHabit()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This habit will be permanently deleted.")
        }
        .alert(archiveConfirmationTitle, isPresented: $isShowingArchiveConfirmation) {
            Button("Archive") {
                setHabitArchived()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(archiveConfirmationMessage)
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
                .appToolbarActionTint(isDisabled: !isFormValid || hasMissingPastDays || isSaving)
                .fontWeight(.semibold)
                .disabled(!isFormValid || hasMissingPastDays || isSaving)
            }
        }
        .onChange(of: draft.reminderEnabled) { _, isEnabled in
            guard isEnabled else { return }

            Task {
                let granted = await appState.requestNotificationAuthorizationIfNeeded()
                if !granted {
                    validationMessage = nil
                    isShowingNotificationSettingsAlert = true
                    draft.reminderEnabled = false
                }
            }
        }
        .onChange(of: draft.scheduleRule) { _, _ in
            handleScheduleRuleChange()
            handleEndDateValidationInputsChanged()
            resolveEffectiveFromSelection(showAdjustmentBanner: false)
        }
        .onAppear {
            applyPendingScheduleRuleIfNeeded()
            resolveEffectiveFromSelection(showAdjustmentBanner: false)
        }
        .appNotificationSettingsAlert(isPresented: $isShowingNotificationSettingsAlert)
        .onChange(of: draft.completedDays) { _, _ in
            historyValidationMessage = nil
            handleEndDateValidationInputsChanged()
            resolveEffectiveFromSelection(showAdjustmentBanner: false)
        }
        .onChange(of: draft.skippedDays) { _, _ in
            historyValidationMessage = nil
            handleEndDateValidationInputsChanged()
            resolveEffectiveFromSelection(showAdjustmentBanner: false)
        }
        .onChange(of: draft.endDate) { _, _ in
            handleEndDateValidationInputsChanged()
        }
        .onChange(of: draft.name) { _, _ in
            isValidationWarningDismissed = false
            if draft.trimmedName.isEmpty == false, validationMessage == "Enter a habit name." {
                validationMessage = nil
            }
        }
        .onChange(of: hasMissingPastDays) { _, hasMissingPastDays in
            if !hasMissingPastDays {
                isHistoryWarningDismissed = false
            }
        }
        .animation(.easeInOut(duration: 0.18), value: validationMessage)
        .animation(.easeInOut(duration: 0.18), value: historyValidationMessage)
        .animation(.easeInOut(duration: 0.18), value: floatingHistoryWarningMessage)
        .animation(.easeInOut(duration: 0.18), value: isHistoryWarningDismissed)
        .animation(.easeInOut(duration: 0.18), value: isScheduleWarningDismissed)
        .animation(.easeInOut(duration: 0.18), value: isEndDateWarningDismissed)
    }

    private var nameSection: some View {
        AppHabitNameCard(text: $draft.name, showsValidation: false) {
            EmptyView()
        }
    }

    private var scheduleSection: some View {
        AppEditScheduleSection(
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime.default()),
            repeatSummary: draft.scheduleRule.compactSummary,
            endDate: $draft.endDate,
            endDateRange: selectableEndDateRange,
            endDateFallback: draft.startDate,
            reminderTimeTap: dismissKeyboardForNonTextControl,
            repeatTap: dismissKeyboardForNonTextControl,
            endDateTap: dismissKeyboardForNonTextControl
        ) {
            AppCreateRepeatEditorScreen(
                backgroundStyle: .habits,
                scheduleRule: draft.scheduleRule,
                startDate: draft.startDate,
                onTap: dismissKeyboardForNonTextControl
            ) { scheduleRule in
                stageScheduleRule(scheduleRule)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if !isArchived {
                archiveButton
            }
            deleteButton
        }
    }

    private var deleteButton: some View {
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
    }

    private var archiveButton: some View {
        Button {
            isShowingArchiveConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "archivebox")
                    .imageScale(.medium)
                    .foregroundStyle(isSaving ? .secondary : .primary)

                Text("Archive")
                    .foregroundStyle(isSaving ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppNeutralCapsuleActionButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(isSaving)
    }

    private var editableHistoryDays: Set<Date> {
        EditableHistoryWindow.dates(startDate: draft.startDate)
    }

    private var availableMonths: [Date] {
        let months = HistoryMonthWindow.months(containing: editableHistoryDays)
        if !months.isEmpty {
            return months
        }
        return [HistoryMonthWindow.displayMonth(startDate: draft.startDate)]
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty &&
            draft.scheduleRule.isValidSelection &&
            isScheduleEffectiveFromValid &&
            isEndDateValid
    }

    private var hasScheduleChanged: Bool {
        draft.scheduleRule != originalScheduleRule
    }

    private var shouldUseScheduleEffectiveFrom: Bool {
        hasScheduleChanged
    }

    private var isScheduleEffectiveFromValid: Bool {
        !shouldUseScheduleEffectiveFrom || currentEffectiveFromResolution != nil
    }

    private var previewScheduledDates: Set<Date> {
        guard shouldUseScheduleEffectiveFrom, let effectiveFrom = currentEffectiveFromResolution?.resolvedDate else {
            return scheduledDates
        }

        return SchedulePreviewSupport.scheduledDays(
            startDate: draft.startDate,
            through: HistoryMonthWindow.detailsCalendarEndDate(
                startDate: draft.startDate,
                today: Date(),
                calendar: Calendar.current
            ),
            schedules: scheduleHistory,
            replacementRule: draft.scheduleRule,
            effectiveFrom: effectiveFrom,
            calendar: Calendar.current
        )
    }

    private var effectiveFromRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let lowerBound = max(today, Calendar.current.startOfDay(for: draft.startDate))
        let upperBound = max(
            lowerBound,
            HistoryMonthWindow.endOfSecondNextMonth(from: today, calendar: Calendar.current)
        )
        return lowerBound ... upperBound
    }

    private var effectiveFromBaseDate: Date {
        effectiveFromRange.lowerBound
    }

    private var selectableEndDateRange: PartialRangeFrom<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        var lowerBound = max(today, Calendar.current.startOfDay(for: draft.startDate))
        if shouldUseScheduleEffectiveFrom, let effectiveFrom = currentEffectiveFromResolution?.resolvedDate {
            lowerBound = max(lowerBound, effectiveFrom)
        }
        return lowerBound...
    }

    private var isEndDateValid: Bool {
        EndDateValidationSupport.isValid(
            endDate: draft.endDate,
            startDate: draft.startDate,
            lowerBound: selectableEndDateRange.lowerBound,
            schedules: validationScheduleVersions,
            calendar: Calendar.current
        )
    }

    private var endDateValidationMessage: String? {
        isEndDateValid ? nil : AppCopy.noScheduledDayBeforeEndDate
    }

    private var validationScheduleVersions: [SchedulePreviewVersion] {
        if shouldUseScheduleEffectiveFrom, let effectiveFrom = currentEffectiveFromResolution?.resolvedDate {
            return SchedulePreviewSupport.previewSchedules(
                from: scheduleHistory,
                replacementRule: draft.scheduleRule,
                effectiveFrom: effectiveFrom,
                calendar: Calendar.current
            )
        }

        return scheduleHistory.map {
            SchedulePreviewVersion(
                rule: $0.rule,
                effectiveFrom: Calendar.current.startOfDay(for: $0.effectiveFrom),
                createdAt: $0.createdAt,
                version: $0.version
            )
        }
    }

    private var currentMissingPastDays: [Date] {
        guard !isArchived else { return [] }
        let normalized = normalizedDraft()
        return EditableHistoryValidation.missingPastDays(
            editableDays: requiredPastScheduledDays,
            positiveDays: normalized.completedDays,
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
    private var floatingBottomBanners: some View {
        VStack(spacing: 10) {
            if let message = scheduleWarningMessage, !isScheduleWarningDismissed {
                AppFloatingWarningBanner(message: message) {
                    isScheduleWarningDismissed = true
                }
            }

            if let message = floatingHistoryWarningMessage, !isHistoryWarningDismissed {
                AppFloatingWarningBanner(message: message) {
                    isHistoryWarningDismissed = true
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
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .zIndex(1)
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
        return shouldShowNameValidation ? "Enter a habit name." : nil
    }

    private var shouldShowNameValidation: Bool {
        draft.name.isEmpty == false && draft.trimmedName.isEmpty
    }

    private var archiveConfirmationTitle: String {
        "Archive Habit?"
    }

    private var archiveConfirmationMessage: String {
        "This habit will move to Archive."
    }

    private func save() {
        applyPendingScheduleRuleIfNeeded()

        guard isFormValid else {
            if !draft.scheduleRule.isValidSelection {
                isScheduleWarningDismissed = false
            }
            if !isEndDateValid {
                isEndDateWarningDismissed = false
            }
            isValidationWarningDismissed = false
            validationMessage = draft.trimmedName.isEmpty ? "Enter a habit name." : nil
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
                try await appState.updateHabit(from: savedDraft)
                isSaving = false
                onSaveSuccess()
                dismiss()

                if !isArchived {
                    await appState.syncNotificationsAfterHabitUpdate(from: savedDraft)
                }
            } catch {
                if let error = error as? EditableHistoryValidationError {
                    historyValidationMessage = error.localizedDescription
                    if case .missingHabitPastDays(let days) = error, let firstDay = days.first {
                        displayedMonth = month(containing: firstDay)
                    }
                } else {
                    isValidationWarningDismissed = false
                    validationMessage = appState.actionErrorMessage ?? UserFacingErrorMessage.text(for: error)
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

    private func stageScheduleRule(_ scheduleRule: ScheduleRule) {
        pendingScheduleRule = scheduleRule
    }

    private func applyPendingScheduleRuleIfNeeded() {
        guard let scheduleRule = pendingScheduleRule else { return }
        pendingScheduleRule = nil
        guard draft.scheduleRule != scheduleRule else { return }
        draft.scheduleRule = scheduleRule
    }

    private func deleteHabit() {
        isSaving = true
        validationMessage = nil
        isValidationWarningDismissed = false
        historyValidationMessage = nil

        Task {
            await appState.deleteHabit(id: draft.id)
            if let errorMessage = appState.actionErrorMessage {
                validationMessage = errorMessage
                isSaving = false
                return
            }

            isSaving = false
            onDeleteSuccess()
            dismiss()
        }
    }

    private func setHabitArchived() {
        isSaving = true
        validationMessage = nil
        isValidationWarningDismissed = false
        historyValidationMessage = nil

        Task {
            await appState.setHabitArchived(id: draft.id, isArchived: true)
            if let errorMessage = appState.actionErrorMessage {
                validationMessage = errorMessage
                isSaving = false
                return
            }

            isArchived = true
            isSaving = false
            onArchiveSuccess()
            dismiss()
        }
    }

    private func normalizedDraft() -> EditHabitDraft {
        var normalized = draft
        normalized.skippedDays.subtract(normalized.completedDays)
        normalized.scheduleEffectiveFrom = shouldUseScheduleEffectiveFrom ? currentEffectiveFromResolution?.resolvedDate : nil
        if let endDate = normalized.endDate {
            normalized.endDate = Calendar.current.startOfDay(for: endDate)
        }
        return normalized
    }

    private var currentEffectiveFromResolution: ScheduleEffectiveFromResolution? {
        effectiveFromResolution(
            selectedDate: effectiveFromBaseDate
        )
    }

    private func effectiveFromResolution(selectedDate: Date) -> ScheduleEffectiveFromResolution? {
        ScheduleEffectiveFromResolver.resolve(
            scheduleRule: draft.scheduleRule,
            selectedDate: selectedDate,
            explicitDays: draft.completedDays.union(draft.skippedDays),
            minimumDate: effectiveFromRange.lowerBound,
            maximumDate: effectiveFromRange.upperBound,
            calendar: Calendar.current
        )
    }

    private func resolveEffectiveFromSelection(showAdjustmentBanner _: Bool) {
        guard shouldUseScheduleEffectiveFrom else {
            draft.scheduleEffectiveFrom = nil
            return
        }

        guard let resolution = currentEffectiveFromResolution else {
            draft.scheduleEffectiveFrom = nil
            return
        }

        draft.scheduleEffectiveFrom = resolution.resolvedDate
    }

    private func historyReviewMessage(for missingPastDays: [Date]) -> String {
        if isOnlyActiveOverdueMissing(missingPastDays) {
            return AppCopy.overdueScheduledDayEditMessage(actionLabel: "Completed")
        }
        return EditableHistoryValidationError.missingHabitPastDays(missingPastDays).localizedDescription
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

    private static func initialDisplayedMonth(startDate: Date) -> Date {
        HistoryMonthWindow.displayMonth(startDate: startDate, today: Date(), calendar: Calendar.current)
    }

    private func dismissKeyboardForNonTextControl() {
        AppDescriptionFieldSupport.dismissKeyboard()
    }

}

private struct HabitHistoryCalendarView: View {
    let month: Date
    let editableDays: Set<Date>
    let scheduledDates: Set<Date>
    @Binding var completedDays: Set<Date>
    @Binding var skippedDays: Set<Date>
    let availableMonths: [Date]
    let onMonthChange: (Date) -> Void

    private var calendar: Calendar {
        MonthCalendarSupport.defaultCalendar()
    }

    var body: some View {
        MonthCalendarView(
            month: month,
            availableMonths: availableMonths,
            calendar: calendar,
            headerSpacing: 12,
            onMonthChange: onMonthChange
        ) { date, cellSize in
            HabitCalendarDayView(
                dayNumber: calendar.component(.day, from: date),
                style: dayStyle(for: date),
                isScheduled: isScheduled(date),
                cellSize: cellSize
            )
            .contentShape(Circle())
            .allowsHitTesting(editableDays.contains(date))
            .onTapGesture {
                toggle(date)
            }
            .disabled(!editableDays.contains(date))
        }
    }

    private func toggle(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        guard editableDays.contains(normalizedDate) else { return }

        let currentSelection: EditableHistorySelection
        switch dayStyle(for: normalizedDate) {
        case .available:
            currentSelection = .none
        case .completed:
            currentSelection = .positive
        case .skipped:
            currentSelection = .skipped
        case .disabled:
            return
        }

        let nextSelection = EditableHistoryStateMachine.nextSelection(
            current: currentSelection,
            for: normalizedDate,
            today: Date(),
            calendar: calendar
        )

        completedDays.remove(normalizedDate)
        skippedDays.remove(normalizedDate)

        switch nextSelection {
        case .none:
            break
        case .positive:
            completedDays.insert(normalizedDate)
        case .skipped:
            skippedDays.insert(normalizedDate)
        }
    }

    private func dayStyle(for date: Date) -> HabitCalendarDayStyle {
        guard editableDays.contains(date) else {
            return .disabled
        }
        if completedDays.contains(date) {
            return .completed
        } else if skippedDays.contains(date) {
            return .skipped
        } else {
            return .available
        }
    }

    private func isScheduled(_ date: Date) -> Bool {
        scheduledDates.contains(calendar.startOfDay(for: date))
    }
}

enum HabitCalendarDayStyle {
    case available
    case completed
    case skipped
    case disabled
}

struct HabitCalendarDayView: View {
    let dayNumber: Int
    let style: HabitCalendarDayStyle
    let isScheduled: Bool
    let cellSize: CGFloat
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    var body: some View {
        ZStack {
            if style == .completed || style == .skipped {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: markerSize, height: markerSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
                .frame(width: markerSize, height: markerSize)

            if isScheduled {
                Circle()
                    .fill(scheduleIndicatorColor)
                    .frame(width: scheduleIndicatorSize, height: scheduleIndicatorSize)
                    .offset(y: scheduleIndicatorOffset)
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var foreground: Color {
        switch style {
        case .completed:
            return appTint.accentColor
        case .skipped:
            return .red
        case .available:
            return .primary
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .completed:
            return appTint.accentColor.opacity(0.18)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(0.18)
        case .available, .disabled:
            return .clear
        }
    }

    private var markerSize: CGFloat {
        min(cellSize, 40)
    }

    private var scheduleIndicatorSize: CGFloat {
        4
    }

    private var scheduleIndicatorOffset: CGFloat {
        markerSize / 2 - scheduleIndicatorSize
    }

    private var scheduleIndicatorColor: Color {
        Color(uiColor: .tertiaryLabel)
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
    }
}
