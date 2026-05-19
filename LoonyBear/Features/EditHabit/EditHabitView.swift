import SwiftUI

struct EditHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState

    private let onSaveSuccess: () -> Void
    private let onDeleteSuccess: () -> Void
    private let onArchiveSuccess: () -> Void
    private let onRestoreRequested: (() -> Void)?
    private let showsCloseButton: Bool
    private let isReadOnly: Bool
    private let requiredPastScheduledDays: Set<Date>
    private let scheduleHistory: [HabitScheduleVersion]
    private let activeOverdueDay: Date?
    private let originalScheduleRule: ScheduleRule
    private let originalArchivedAt: Date?
    private let archivedDays: Set<Date>
    private let historySnapshot: CoreDataHistoryBucketSnapshot
    @State private var draft: EditHabitDraft
    @State private var discardBaselineDraft: EditHabitDraft
    @State private var pendingScheduleRule: ScheduleRule?
    @State private var validationMessage: String?
    @State private var isValidationWarningDismissed = false
    @State private var historyValidationMessage: String?
    @State private var displayedMonth: Date
    @State private var isSaving = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingArchiveConfirmation = false
    @State private var isShowingRestoreConfirmation = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingNotificationSettingsAlert = false
    @State private var isHistoryWarningDismissed = false
    @State private var isScheduleWarningDismissed = false
    @State private var isEndDateWarningDismissed = false
    @State private var isArchived: Bool
    @State private var isRestoreMode = false

    init(
        details: HabitDetailsProjection,
        showsCloseButton: Bool = true,
        isReadOnly: Bool = false,
        startsInRestoreMode: Bool = false,
        onSaveSuccess: @escaping () -> Void = {},
        onDeleteSuccess: @escaping () -> Void = {},
        onArchiveSuccess: @escaping () -> Void = {},
        onRestoreRequested: (() -> Void)? = nil
    ) {
        self.onSaveSuccess = onSaveSuccess
        self.onDeleteSuccess = onDeleteSuccess
        self.onArchiveSuccess = onArchiveSuccess
        self.onRestoreRequested = onRestoreRequested
        self.showsCloseButton = showsCloseButton
        self.isReadOnly = isReadOnly
        requiredPastScheduledDays = details.requiredPastScheduledDays
        scheduleHistory = details.scheduleHistory
        activeOverdueDay = details.activeOverdueDay
        originalScheduleRule = details.scheduleRule
        originalArchivedAt = details.archivedAt
        archivedDays = details.archivedDays
        historySnapshot = details.historySnapshot
        let today = Calendar.current.startOfDay(for: Date())
        var initialDraft = EditHabitDraft(
            id: details.id,
            type: details.type,
            startDate: details.startDate,
            activeFrom: details.activeFrom,
            endDate: details.endDate,
            name: details.name,
            scheduleRule: details.scheduleRule,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            completedDays: details.completedDays,
            skippedDays: details.skippedDays
        )
        if startsInRestoreMode {
            initialDraft.restoreActiveFrom = today
            initialDraft.scheduleEffectiveFrom = nil
            initialDraft.endDate = nil
        }
        _draft = State(initialValue: initialDraft)
        _discardBaselineDraft = State(initialValue: initialDraft)
        _displayedMonth = State(initialValue: startsInRestoreMode
            ? Self.month(containing: today)
            : Self.initialDisplayedMonth(startDate: details.startDate))
        _isArchived = State(initialValue: details.isArchived)
        _isRestoreMode = State(initialValue: startsInRestoreMode)
    }

    var body: some View {
        AppScreen(backgroundStyle: .habits, topPadding: 8) {
            nameSection
                .disabled(isEditingDisabled)
            streakSection
            scheduleSection
                .disabled(isEditingDisabled)

            VStack(alignment: .leading, spacing: 8) {
                AppFormSectionHeader(title: "Calendar")

                AppCard {
                    HabitHistoryCalendarView(
                        month: displayedMonth,
                        editableDays: editableHistoryDays,
                        scheduledDates: previewScheduledDates,
                        archivedDays: archivedDays,
                        historySnapshot: historySnapshot,
                        completedDays: $draft.completedDays,
                        skippedDays: $draft.skippedDays,
                        availableMonthRange: availableMonthRange,
                        isReadOnly: isEditingDisabled,
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
        .navigationTitle(isRestoreMode ? "Restore Habit" : "Habit Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        close()
                    } label: {
                        AppToolbarIconLabel("Close", systemName: "xmark")
                    }
                    .appAccentTint()
                    .confirmationDialog(
                        AppCopy.discardChangesTitle,
                        isPresented: $isShowingDiscardConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(AppCopy.discardChangesAction, role: .destructive) {
                            dismiss()
                        }
                    } message: {
                        Text(AppCopy.discardChangesMessage)
                    }
                }
            }

            if !isEditingDisabled {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        AppToolbarIconLabel("Save", systemName: "checkmark")
                    }
                    .appToolbarActionTint(isDisabled: isSaveDisabled)
                    .fontWeight(.semibold)
                    .disabled(isSaveDisabled)
                    .confirmationDialog(
                        "Restore Habit?",
                        isPresented: $isShowingRestoreConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Continue Progress") {
                            confirmRestoreHabit(historyMode: .keepHistory)
                        }

                        Button("Start From Scratch") {
                            confirmRestoreHabit(historyMode: .startFresh)
                        }
                    } message: {
                        Text("You can continue with your previous progress or start from scratch.")
                    }
                }
            }
        }
        .appSheetDismissGuard(isDisabled: hasUnsavedChanges, onAttempt: close)
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
            clampDisplayedMonthToAvailableRange()
        }
        .onChange(of: draft.restoreActiveFrom) { _, _ in
            handleEndDateValidationInputsChanged()
            clampDisplayedMonthToAvailableRange()
        }
        .onAppear {
            applyPendingScheduleRuleIfNeeded()
            resolveEffectiveFromSelection(showAdjustmentBanner: false)
            clampDisplayedMonthToAvailableRange()
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
            clampDisplayedMonthToAvailableRange()
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
        .transaction { transaction in
            if isShowingRestoreConfirmation || isShowingDiscardConfirmation {
                transaction.animation = nil
            }
        }
    }

    private var nameSection: some View {
        AppHabitNameCard(text: $draft.name, showsValidation: false) {
            EmptyView()
        }
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFormSectionHeader(title: "Streaks")

            AppCard {
                VStack(spacing: 0) {
                    AppPlainValueRow(
                        title: "Current streak",
                        value: DayCountFormatter.compactDurationString(for: currentStreak),
                        valueColor: AnyShapeStyle(.secondary)
                    )

                    AppSectionDivider()

                    AppPlainValueRow(
                        title: "Best streak",
                        value: DayCountFormatter.compactDurationString(for: longestStreak),
                        valueColor: AnyShapeStyle(.secondary)
                    )

                    AppSectionDivider()

                    AppPlainValueRow(
                        title: "Completed for",
                        value: DayCountFormatter.compactDurationString(for: totalCompletedDays),
                        valueColor: AnyShapeStyle(.secondary)
                    )
                }
            }
        }
    }

    private var scheduleSection: some View {
        AppEditScheduleSection(
            startDate: draft.startDate,
            activeFrom: restoreActiveFromBinding,
            activeFromRange: restoreActiveFromRange,
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime.default()),
            repeatSummary: draft.scheduleRule.compactSummary,
            endDate: $draft.endDate,
            endDateFallback: defaultEndDateFallback,
            activeFromTap: dismissKeyboardForNonTextControl,
            reminderTimeTap: dismissKeyboardForNonTextControl,
            repeatTap: dismissKeyboardForNonTextControl,
            endDateTap: dismissKeyboardForNonTextControl,
            isReadOnly: isEditingDisabled
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

    private var defaultEndDateFallback: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var isEditingDisabled: Bool {
        isReadOnly && !isRestoreMode
    }

    private var restoreActiveFromBinding: Binding<Date>? {
        guard isRestoreMode else { return nil }
        return Binding(
            get: {
                normalizedRestoreActiveFrom ?? Calendar.current.startOfDay(for: Date())
            },
            set: { newValue in
                draft.restoreActiveFrom = Calendar.current.startOfDay(for: newValue)
            }
        )
    }

    private var restoreActiveFromRange: ClosedRange<Date>? {
        guard isRestoreMode else { return nil }
        return restoreMinimumActiveFrom ... Date.distantFuture
    }

    private var normalizedRestoreActiveFrom: Date? {
        guard isRestoreMode else { return nil }
        return Calendar.current.startOfDay(for: draft.restoreActiveFrom ?? Date())
    }

    private var restoreMinimumActiveFrom: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let editableStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let archivedAt = originalArchivedAt.map { calendar.startOfDay(for: $0) } ?? today
        return max(archivedAt, calendar.startOfDay(for: editableStart))
    }

    private var isRestoreActiveFromValid: Bool {
        guard isRestoreMode, let activeFrom = normalizedRestoreActiveFrom else { return true }
        return activeFrom >= restoreMinimumActiveFrom
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if isRestoreMode {
                EmptyView()
            } else if isArchived {
                restoreButton
                deleteButton
            } else if !isEditingDisabled {
                archiveButton
                deleteButton
            }
        }
    }

    private var deleteButton: some View {
        Button {
            isShowingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppMaterialCapsuleActionButtonStyle())
        .tint(.red)
        .frame(maxWidth: .infinity)
        .disabled(isSaving)
        .alert("Permanently delete this Habit?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteHabit()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This Habit will be permanently deleted.")
        }
    }

    private var archiveButton: some View {
        Button {
            isShowingArchiveConfirmation = true
        } label: {
            Label("Archive", systemImage: "tray.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppMaterialCapsuleActionButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(isSaving)
        .alert(archiveConfirmationTitle, isPresented: $isShowingArchiveConfirmation) {
            Button("Archive") {
                archiveHabit()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(archiveConfirmationMessage)
        }
    }

    private var restoreButton: some View {
        Button {
            if let onRestoreRequested {
                onRestoreRequested()
            } else {
                beginRestore()
            }
        } label: {
            Label("Restore", systemImage: "tray.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppMaterialCapsuleActionButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(isSaving)
    }

    private var editableHistoryDays: Set<Date> {
        if isRestoreMode, let activeFrom = normalizedRestoreActiveFrom {
            return EditableHistoryWindow.dates(startDate: activeFrom)
        }
        return EditableHistoryWindow.dates(startDate: activeCycleStartDate)
    }

    private var availableMonthRange: ClosedRange<Date> {
        let calendarStart = normalizedRestoreActiveFrom ?? activeCycleStartDate
        let firstMonth = HistoryMonthWindow.monthStart(containing: calendarStart, calendar: Calendar.current)
        let defaultEndDate = HistoryMonthWindow.detailsCalendarEndDate(startDate: calendarStart)
        let calendarEnd = max(defaultEndDate, draft.endDate ?? defaultEndDate)
        let lastMonth = HistoryMonthWindow.monthStart(
            containing: calendarEnd,
            calendar: Calendar.current
        )
        return firstMonth ... max(firstMonth, lastMonth)
    }

    private var displayedMonthRange: ClosedRange<Date> {
        let monthStart = HistoryMonthWindow.monthStart(containing: displayedMonth, calendar: Calendar.current)
        let monthEnd = HistoryMonthWindow.endOfMonth(containing: monthStart, calendar: Calendar.current)
        return monthStart ... monthEnd
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty &&
            draft.scheduleRule.isValidSelection &&
            isScheduleEffectiveFromValid &&
            isRestoreActiveFromValid &&
            isEndDateValid
    }

    private var hasScheduleChanged: Bool {
        draft.scheduleRule != originalScheduleRule
    }

    private var hasUnsavedChanges: Bool {
        draft != discardBaselineDraft || stagedScheduleHasChanges
    }

    private var stagedScheduleHasChanges: Bool {
        guard let pendingScheduleRule else { return false }
        return pendingScheduleRule != draft.scheduleRule
    }

    private var shouldUseScheduleEffectiveFrom: Bool {
        !isRestoreMode && hasScheduleChanged
    }

    private var isScheduleEffectiveFromValid: Bool {
        !shouldUseScheduleEffectiveFrom || currentEffectiveFromResolution != nil
    }

    private var previewScheduledDates: Set<Date> {
        if isRestoreMode, let activeFrom = normalizedRestoreActiveFrom {
            return HistoryScheduleApplicability.scheduledDays(
                in: displayedMonthRange,
                startDate: activeFrom,
                limitingTo: previewScheduleEndDate,
                schedules: SchedulePreviewSupport.newCycleSchedules(
                    rule: draft.scheduleRule,
                    activeFrom: activeFrom,
                    calendar: Calendar.current
                ),
                calendar: Calendar.current
            )
        }

        guard shouldUseScheduleEffectiveFrom, let effectiveFrom = currentEffectiveFromResolution?.resolvedDate else {
            return HistoryScheduleApplicability.scheduledDays(
                in: displayedMonthRange,
                startDate: activeCycleStartDate,
                limitingTo: previewScheduleEndDate,
                schedules: validationScheduleVersions,
                calendar: Calendar.current
            )
        }

        return SchedulePreviewSupport.scheduledDays(
            in: displayedMonthRange,
            startDate: draft.startDate,
            limitingTo: previewScheduleEndDate,
            schedules: scheduleHistory,
            replacementRule: draft.scheduleRule,
            effectiveFrom: effectiveFrom,
            calendar: Calendar.current
        )
    }

    private var previewScheduleEndDate: Date? {
        draft.endDate
    }

    private var effectiveFromRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let lowerBound = max(today, activeCycleStartDate)
        let upperBound = max(
            lowerBound,
            HistoryMonthWindow.endOfSecondNextMonth(from: today, calendar: Calendar.current)
        )
        return lowerBound ... upperBound
    }

    private var effectiveFromBaseDate: Date {
        effectiveFromRange.lowerBound
    }

    private var endDateValidationLowerBound: Date {
        let today = Calendar.current.startOfDay(for: Date())
        if isRestoreMode, let activeFrom = normalizedRestoreActiveFrom {
            return max(today, activeFrom)
        }
        var lowerBound = max(today, activeCycleStartDate)
        if shouldUseScheduleEffectiveFrom, let effectiveFrom = currentEffectiveFromResolution?.resolvedDate {
            lowerBound = max(lowerBound, effectiveFrom)
        }
        return lowerBound
    }

    private var activeCycleStartDate: Date {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: draft.startDate)
        guard let activeFrom = draft.activeFrom else {
            return startDate
        }
        return max(startDate, calendar.startOfDay(for: activeFrom))
    }

    private var isEndDateValid: Bool {
        EndDateValidationSupport.isValid(
            endDate: draft.endDate,
            startDate: draft.startDate,
            lowerBound: endDateValidationLowerBound,
            schedules: validationScheduleVersions,
            calendar: Calendar.current
        )
    }

    private var endDateValidationMessage: String? {
        EndDateValidationSupport.failureReason(
            endDate: draft.endDate,
            startDate: draft.startDate,
            lowerBound: endDateValidationLowerBound,
            schedules: validationScheduleVersions,
            today: Date(),
            calendar: Calendar.current
        ).map(AppCopy.endDateValidationMessage)
    }

    private var validationScheduleVersions: [SchedulePreviewVersion] {
        if isRestoreMode, let activeFrom = normalizedRestoreActiveFrom {
            return SchedulePreviewSupport.previewSchedules(
                from: scheduleHistory,
                replacementRule: draft.scheduleRule,
                effectiveFrom: activeFrom,
                calendar: Calendar.current
            )
        }

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
        guard !isArchived, !isRestoreMode else { return [] }
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

    private var currentStreak: Int {
        StreakEngine.currentStreak(
            earliestCompletionDate: earliestCompletionDate,
            containsCompletion: { effectiveHistoryState(on: $0) == .positive },
            containsSkippedCompletion: { effectiveHistoryState(on: $0) == .skipped },
            schedules: streakScheduleHistory,
            startDate: draft.startDate,
            today: Date(),
            seed: historySnapshot.positiveStreakSeed(calendar: Calendar.current),
            calendar: Calendar.current
        )
    }

    private var longestStreak: Int {
        StreakEngine.longestStreak(
            earliestCompletionDate: earliestCompletionDate,
            latestCompletionDate: latestCompletionDate,
            containsCompletion: { effectiveHistoryState(on: $0) == .positive },
            schedules: streakScheduleHistory,
            startDate: draft.startDate,
            seed: historySnapshot.positiveStreakSeed(calendar: Calendar.current),
            calendar: Calendar.current
        )
    }

    private var totalCompletedDays: Int {
        let editableDays = editableHistoryDays
        let originalEditableCompletedCount = editableDays.filter {
            historySnapshot.state(on: $0, calendar: Calendar.current) == .positive
        }.count
        let draftEditableCompletedCount = editableDays.filter {
            draft.completedDays.contains(Calendar.current.startOfDay(for: $0))
        }.count
        return max(0, historySnapshot.positiveCount - originalEditableCompletedCount + draftEditableCompletedCount)
    }

    private var earliestCompletionDate: Date? {
        let draftEarliest = draft.completedDays.min()
        guard let snapshotEarliest = historySnapshot.earliestPositiveDate else { return draftEarliest }
        guard let draftEarliest else { return snapshotEarliest }
        return min(snapshotEarliest, draftEarliest)
    }

    private var latestCompletionDate: Date? {
        let draftLatest = draft.completedDays.max()
        guard let snapshotLatest = historySnapshot.latestPositiveDate else { return draftLatest }
        guard let draftLatest else { return snapshotLatest }
        return max(snapshotLatest, draftLatest)
    }

    private func effectiveHistoryState(on day: Date) -> CoreDataHistoryBucketState? {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        if editableHistoryDays.contains(normalizedDay) {
            if draft.completedDays.contains(normalizedDay) { return .positive }
            if draft.skippedDays.contains(normalizedDay) { return .skipped }
            return nil
        }
        return historySnapshot.state(on: normalizedDay, calendar: Calendar.current)
    }

    private var streakScheduleHistory: [HabitScheduleVersion] {
        if isRestoreMode, let activeFrom = normalizedRestoreActiveFrom {
            let calendar = Calendar.current
            let normalizedActiveFrom = calendar.startOfDay(for: activeFrom)
            let priorSchedules = scheduleHistory.filter {
                calendar.startOfDay(for: $0.effectiveFrom) < normalizedActiveFrom
            }

            return priorSchedules + [
                HabitScheduleVersion(
                    id: UUID(),
                    habitID: draft.id,
                    rule: draft.scheduleRule,
                    effectiveFrom: normalizedActiveFrom,
                    createdAt: .distantFuture,
                    version: Int.max
                ),
            ]
        }

        guard shouldUseScheduleEffectiveFrom, let effectiveFrom = currentEffectiveFromResolution?.resolvedDate else {
            return scheduleHistory
        }

        let calendar = Calendar.current
        let normalizedEffectiveFrom = calendar.startOfDay(for: effectiveFrom)
        let priorSchedules = scheduleHistory.filter {
            calendar.startOfDay(for: $0.effectiveFrom) < normalizedEffectiveFrom
        }

        return priorSchedules + [
            HabitScheduleVersion(
                id: UUID(),
                habitID: draft.id,
                rule: draft.scheduleRule,
                effectiveFrom: normalizedEffectiveFrom,
                createdAt: .distantFuture,
                version: Int.max
            ),
        ]
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
            if !isEditingDisabled, let message = scheduleWarningMessage, !isScheduleWarningDismissed {
                AppFloatingWarningBanner(message: message) {
                    isScheduleWarningDismissed = true
                }
            }

            if !isEditingDisabled, let message = floatingHistoryWarningMessage, !isHistoryWarningDismissed {
                AppFloatingWarningBanner(message: message) {
                    isHistoryWarningDismissed = true
                }
            }

            if !isEditingDisabled, let message = endDateFloatingWarningMessage {
                AppFloatingWarningBanner(message: message) {
                    isEndDateWarningDismissed = true
                }
            }

            if !isEditingDisabled, let message = validationFloatingWarningMessage {
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
        "Archive this Habit?"
    }

    private var archiveConfirmationMessage: String {
        "This Habit will be moved to Archive."
    }

    private var isSaveDisabled: Bool {
        if isRestoreMode {
            return isSaving
        }

        return !isFormValid || hasMissingPastDays || isSaving
    }

    private func beginRestore() {
        let today = Calendar.current.startOfDay(for: Date())
        pendingScheduleRule = nil
        draft.restoreActiveFrom = today
        draft.scheduleEffectiveFrom = nil
        draft.endDate = nil
        isRestoreMode = true
        validationMessage = nil
        historyValidationMessage = nil
        isValidationWarningDismissed = false
        isHistoryWarningDismissed = false
        isScheduleWarningDismissed = false
        isEndDateWarningDismissed = false
        displayedMonth = month(containing: today)
        discardBaselineDraft = draft
    }

    private func close() {
        guard hasUnsavedChanges else {
            dismiss()
            return
        }

        isShowingDiscardConfirmation = true
    }

    private func save() {
        guard !isRestoreMode else {
            prepareRestoreHabitConfirmation()
            return
        }

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

    private func clampDisplayedMonthToAvailableRange() {
        let normalizedDisplayedMonth = month(containing: displayedMonth)
        let range = availableMonthRange
        if normalizedDisplayedMonth < range.lowerBound {
            displayedMonth = range.lowerBound
        } else if normalizedDisplayedMonth > range.upperBound {
            displayedMonth = range.upperBound
        }
    }

    private func stageScheduleRule(_ scheduleRule: ScheduleRule) {
        pendingScheduleRule = scheduleRule
    }

    private func applyPendingScheduleRuleIfNeeded() {
        guard !isEditingDisabled else { return }
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

    private func archiveHabit() {
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

    private func prepareRestoreHabitConfirmation() {
        guard !isShowingRestoreConfirmation else { return }
        isShowingRestoreConfirmation = true
    }

    private func confirmRestoreHabit(historyMode: RestoreHistoryMode) {
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

        restoreHabit(savedDraft: normalizedDraft(), historyMode: historyMode)
    }

    private func restoreHabit(savedDraft: EditHabitDraft, historyMode: RestoreHistoryMode) {
        isSaving = true
        validationMessage = nil
        historyValidationMessage = nil

        Task {
            do {
                try await appState.restoreHabit(from: savedDraft, historyMode: historyMode)
                isSaving = false
                onSaveSuccess()
                dismiss()
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

    private func normalizedDraft() -> EditHabitDraft {
        var normalized = draft
        normalized.skippedDays.subtract(normalized.completedDays)
        if isRestoreMode {
            normalized.restoreActiveFrom = normalizedRestoreActiveFrom
            normalized.scheduleEffectiveFrom = nil
        } else {
            normalized.restoreActiveFrom = nil
            normalized.scheduleEffectiveFrom = shouldUseScheduleEffectiveFrom ? currentEffectiveFromResolution?.resolvedDate : nil
        }
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
        guard !isEditingDisabled else { return }
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

    private static func month(containing date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func initialDisplayedMonth(startDate: Date) -> Date {
        HistoryMonthWindow.displayMonth(startDate: startDate, today: Date(), calendar: Calendar.current)
    }

    private func dismissKeyboardForNonTextControl() {
        AppDescriptionFieldSupport.dismissKeyboard()
    }

    private func draftCompletions(from days: Set<Date>, source: CompletionSource) -> [HabitCompletion] {
        days.map {
            HabitCompletion(
                id: UUID(),
                habitID: draft.id,
                localDate: Calendar.current.startOfDay(for: $0),
                source: source,
                createdAt: $0
            )
        }
    }

}

private struct HabitHistoryCalendarView: View {
    let month: Date
    let editableDays: Set<Date>
    let scheduledDates: Set<Date>
    let archivedDays: Set<Date>
    let historySnapshot: CoreDataHistoryBucketSnapshot
    @Binding var completedDays: Set<Date>
    @Binding var skippedDays: Set<Date>
    let availableMonthRange: ClosedRange<Date>
    var isReadOnly = false
    let onMonthChange: (Date) -> Void

    private var calendar: Calendar {
        MonthCalendarSupport.defaultCalendar()
    }

    var body: some View {
        MonthCalendarView(
            month: month,
            availableMonthRange: availableMonthRange,
            calendar: calendar,
            headerSpacing: 12,
            onMonthChange: onMonthChange
        ) { date, cellSize in
            HabitCalendarDayView(
                dayNumber: calendar.component(.day, from: date),
                style: dayStyle(for: date),
                isEditable: !isReadOnly && editableDays.contains(date) && !isArchived(date),
                isScheduled: isScheduled(date),
                cellSize: cellSize
            )
            .contentShape(Circle())
            .allowsHitTesting(!isReadOnly && editableDays.contains(date) && !isArchived(date))
            .onTapGesture {
                toggle(date)
            }
            .disabled(isReadOnly || !editableDays.contains(date) || isArchived(date))
        }
    }

    private func toggle(_ date: Date) {
        guard !isReadOnly else { return }
        let normalizedDate = calendar.startOfDay(for: date)
        guard editableDays.contains(normalizedDate) else { return }
        guard !archivedDays.contains(normalizedDate) else { return }

        let currentSelection: EditableHistorySelection
        switch dayStyle(for: normalizedDate) {
        case .available:
            currentSelection = .none
        case .completed:
            currentSelection = .positive
        case .skipped:
            currentSelection = .skipped
        case .archived, .disabled:
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
        let normalizedDate = calendar.startOfDay(for: date)

        if completedDays.contains(normalizedDate) {
            return .completed
        } else if skippedDays.contains(normalizedDate) {
            return .skipped
        } else if archivedDays.contains(normalizedDate) {
            return .archived
        } else if editableDays.contains(normalizedDate) && !isReadOnly {
            return .available
        } else if let state = historySnapshot.state(on: normalizedDate, calendar: calendar) {
            switch state {
            case .positive:
                return .completed
            case .skipped:
                return .skipped
            case .archived:
                return .archived
            }
        } else if isReadOnly {
            return .disabled
        } else {
            return .disabled
        }
    }

    private func isScheduled(_ date: Date) -> Bool {
        scheduledDates.contains(calendar.startOfDay(for: date))
    }

    private func isArchived(_ date: Date) -> Bool {
        let normalizedDate = calendar.startOfDay(for: date)
        return archivedDays.contains(normalizedDate) ||
            historySnapshot.state(on: normalizedDate, calendar: calendar) == .archived
    }
}

enum HabitCalendarDayStyle {
    case available
    case completed
    case skipped
    case archived
    case disabled
}

struct HabitCalendarDayView: View {
    let dayNumber: Int
    let style: HabitCalendarDayStyle
    let isEditable: Bool
    let isScheduled: Bool
    let cellSize: CGFloat
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    var body: some View {
        ZStack {
            if style == .completed || style == .skipped || style == .archived {
                Circle()
                    .fill(backgroundColor)
                    .overlay {
                        Circle()
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    }
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
        case .archived:
            return Color(uiColor: .tertiaryLabel)
        case .available:
            return .primary
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .completed:
            return appTint.accentColor.opacity(markedBackgroundOpacity)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(markedBackgroundOpacity)
        case .archived:
            return Color(uiColor: .systemGray).opacity(0.14)
        case .available, .disabled:
            return .clear
        }
    }

    private var borderColor: Color {
        guard isEditable else { return .clear }

        switch style {
        case .completed:
            return appTint.accentColor.opacity(0.45)
        case .skipped:
            return Color(uiColor: .systemRed).opacity(0.45)
        case .archived, .available, .disabled:
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        isEditable ? 1 : 0
    }

    private var markedBackgroundOpacity: Double {
        isEditable ? 0.22 : 0.18
    }

    private var markerSize: CGFloat {
        min(cellSize, 40)
    }

    private var scheduleIndicatorSize: CGFloat {
        4
    }

    private var scheduleIndicatorOffset: CGFloat {
        markerSize / 2 - scheduleIndicatorSize - 2
    }

    private var scheduleIndicatorColor: Color {
        Color(uiColor: .tertiaryLabel)
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
    }
}
