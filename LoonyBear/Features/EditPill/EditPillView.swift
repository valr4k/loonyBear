import SwiftUI
import UIKit

struct EditPillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    private let onSaveSuccess: () -> Void
    private let onDeleteSuccess: () -> Void
    private let onArchiveSuccess: () -> Void
    private let onRestoreRequested: (() -> Void)?
    private let showsCloseButton: Bool
    private let isReadOnly: Bool
    private let requiredPastScheduledDays: Set<Date>
    private let scheduleHistory: [PillScheduleVersion]
    private let activeOverdueDay: Date?
    private let originalScheduleRule: ScheduleRule
    private let originalArchivedAt: Date?
    private let archivedDays: Set<Date>
    private let historySnapshot: CoreDataHistoryBucketSnapshot
    @FocusState private var focusedField: Field?
    @State private var draft: EditPillDraft
    @State private var discardBaselineDraft: EditPillDraft
    @State private var pendingScheduleRule: ScheduleRule?
    @State private var displayedMonth: Date
    @State private var validationMessage: String?
    @State private var isValidationWarningDismissed = false
    @State private var historyValidationMessage: String?
    @State private var scheduleNoticeMessage: String?
    @State private var scheduleNoticeDismissTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var isDismissingKeyboardForNonTextControl = false
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

    private enum Field: Hashable {
        case description
    }

    init(
        details: PillDetailsProjection,
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
        var initialDraft = EditPillDraft(
            id: details.id,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            activeFrom: details.activeFrom,
            endDate: details.endDate,
            scheduleRule: details.scheduleRule,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
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
        ScrollViewReader { proxy in
            AppScreen(backgroundStyle: .pills, topPadding: 8) {
                detailsSection
                    .disabled(isEditingDisabled)
                streakSection
                scheduleSection
                    .disabled(isEditingDisabled)

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Calendar")

                    AppCard {
                        PillHistoryCalendarView(
                            month: displayedMonth,
                            editableDays: editableHistoryDays,
                            scheduledDates: previewScheduledDates,
                            archivedDays: archivedDays,
                            historySnapshot: historySnapshot,
                            takenDays: $draft.takenDays,
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

                descriptionSection
                    .disabled(isEditingDisabled)

                actionButtons
            }
            .overlay(alignment: .bottom) {
                floatingBottomBanners
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
                AppDescriptionFieldSupport.dismissKeyboard()
            }
            .navigationTitle(isRestoreMode ? "Restore Pill" : "Pill Details")
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
                            "Restore Pill?",
                            isPresented: $isShowingRestoreConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Continue Progress") {
                                confirmRestorePill(historyMode: .keepHistory)
                            }

                            Button("Start From Scratch") {
                                confirmRestorePill(historyMode: .startFresh)
                            }
                        } message: {
                            Text("You can continue with your previous progress or start from scratch.")
                        }
                    }
                }
            }
            .appSheetDismissGuard(isDisabled: hasUnsavedChanges, onAttempt: close)
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
            .onChange(of: draft.scheduleRule) { _, _ in
                handleScheduleRuleChange()
                handleEndDateValidationInputsChanged()
                resolveEffectiveFromSelection(showAdjustmentBanner: false)
                clearEndDateForNeverRepeat(showInfo: true)
                clampDisplayedMonthToAvailableRange()
            }
            .onChange(of: draft.restoreActiveFrom) { _, _ in
                handleEndDateValidationInputsChanged()
                clampDisplayedMonthToAvailableRange()
            }
            .onAppear {
                applyPendingScheduleRuleIfNeeded()
                resolveEffectiveFromSelection(showAdjustmentBanner: false)
                clearEndDateForNeverRepeat(showInfo: false)
                clampDisplayedMonthToAvailableRange()
            }
            .appNotificationSettingsAlert(isPresented: $isShowingNotificationSettingsAlert)
            .onChange(of: draft.takenDays) { _, _ in
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
                handleNonScheduleValidationInputChanged()
            }
            .onChange(of: draft.dosage) { _, _ in
                handleNonScheduleValidationInputChanged()
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
            .animation(.easeInOut(duration: 0.18), value: scheduleNoticeMessage)
            .animation(.easeInOut(duration: 0.18), value: isHistoryWarningDismissed)
            .animation(.easeInOut(duration: 0.18), value: isScheduleWarningDismissed)
            .animation(.easeInOut(duration: 0.18), value: isEndDateWarningDismissed)
            .transaction { transaction in
                if isShowingRestoreConfirmation || isShowingDiscardConfirmation {
                    transaction.animation = nil
                }
            }
            .onDisappear {
                scheduleNoticeDismissTask?.cancel()
            }
        }
    }

    private var detailsSection: some View {
        AppPillDetailsCard(name: $draft.name, dosage: $draft.dosage)
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFormSectionHeader(title: "Streak")

            AppCard {
                AppPlainValueRow(
                    title: "Taken for",
                    value: DayCountFormatter.compactDurationString(for: totalTakenDays),
                    valueColor: AnyShapeStyle(.secondary)
                )
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
            isEndDateEnabled: !draft.scheduleRule.isOneTime,
            activeFromTap: dismissKeyboardForNonTextControl,
            reminderTimeTap: dismissKeyboardForNonTextControl,
            repeatTap: dismissKeyboardForNonTextControl,
            endDateTap: dismissKeyboardForNonTextControl,
            isReadOnly: isEditingDisabled
        ) {
            AppCreateRepeatEditorScreen(
                backgroundStyle: .pills,
                scheduleRule: draft.scheduleRule,
                startDate: draft.startDate,
                allowsNeverRepeat: true,
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

    private var descriptionSection: some View {
        AppFormCardSection(title: "Description") {
            if isEditingDisabled {
                Text(draft.details.isEmpty ? AppCopy.pillDescriptionPlaceholder : draft.details)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            } else {
                TextField(AppCopy.pillDescriptionPlaceholder, text: $draft.details, axis: .vertical)
                    .appAccentTint()
                    .focused($focusedField, equals: .description)
                    .lineLimit(3 ... 6)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
        }
        .id(Field.description)
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
        .alert("Permanently delete this Pill?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deletePill()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This Pill will be permanently deleted.")
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
                archivePill()
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

    private var totalTakenDays: Int {
        let editableDays = editableHistoryDays
        let originalEditableTakenCount = editableDays.filter {
            historySnapshot.state(on: $0, calendar: Calendar.current) == .positive
        }.count
        let draftEditableTakenCount = editableDays.filter {
            draft.takenDays.contains(Calendar.current.startOfDay(for: $0))
        }.count
        return max(0, historySnapshot.positiveCount - originalEditableTakenCount + draftEditableTakenCount)
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
            !draft.trimmedDosage.isEmpty &&
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
        draft.scheduleRule.isOneTime ? nil : draft.endDate
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
            ignoresEndDate: draft.scheduleRule.isOneTime,
            calendar: Calendar.current
        )
    }

    private var endDateValidationMessage: String? {
        EndDateValidationSupport.failureReason(
            endDate: draft.endDate,
            startDate: draft.startDate,
            lowerBound: endDateValidationLowerBound,
            schedules: validationScheduleVersions,
            ignoresEndDate: draft.scheduleRule.isOneTime,
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

            if let message = scheduleNoticeMessage {
                AppFloatingInfoBanner(message: message) {
                    dismissScheduleNotice()
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
        return visibleNonScheduleInvalidMessage
    }

    private var visibleNonScheduleInvalidMessage: String? {
        if draft.name.isEmpty == false, draft.trimmedName.isEmpty {
            return "Enter a pill name."
        }
        if draft.dosage.isEmpty == false, draft.trimmedDosage.isEmpty {
            return "Enter a dosage."
        }
        return nil
    }

    private var shouldShowDescriptionInset: Bool {
        AppDescriptionFieldSupport.shouldShowInset(
            focusedField: focusedField,
            descriptionField: .description,
            isDismissingKeyboardForNonTextControl: isDismissingKeyboardForNonTextControl
        )
    }

    private var archiveConfirmationTitle: String {
        "Archive this Pill?"
    }

    private var archiveConfirmationMessage: String {
        "This Pill will be moved to Archive."
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
        scheduleNoticeMessage = nil
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
            prepareRestorePillConfirmation()
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
            validationMessage = nonScheduleInvalidMessage
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

                if !isArchived {
                    await pillAppState.syncNotificationsAfterPillUpdate(from: savedDraft)
                }
            } catch {
                if let error = error as? EditableHistoryValidationError {
                    historyValidationMessage = error.localizedDescription
                    if case .missingPillPastDays(let days) = error, let firstDay = days.first {
                        displayedMonth = month(containing: firstDay)
                    }
                } else {
                    isValidationWarningDismissed = false
                    validationMessage = pillAppState.actionErrorMessage ?? UserFacingErrorMessage.text(for: error)
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

    private func clearEndDateForNeverRepeat(showInfo: Bool) {
        guard !isEditingDisabled else { return }
        guard draft.scheduleRule.isOneTime, draft.endDate != nil else { return }
        draft.endDate = nil

        if showInfo {
            presentScheduleNotice(AppCopy.endDateRemovedForNeverRepeat)
        }
    }

    private func deletePill() {
        isSaving = true
        validationMessage = nil
        isValidationWarningDismissed = false
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

    private func archivePill() {
        isSaving = true
        validationMessage = nil
        isValidationWarningDismissed = false
        historyValidationMessage = nil

        Task {
            await pillAppState.setPillArchived(id: draft.id, isArchived: true)
            if let errorMessage = pillAppState.actionErrorMessage {
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

    private func prepareRestorePillConfirmation() {
        guard !isShowingRestoreConfirmation else { return }
        isShowingRestoreConfirmation = true
    }

    private func confirmRestorePill(historyMode: RestoreHistoryMode) {
        guard isFormValid else {
            if !draft.scheduleRule.isValidSelection {
                isScheduleWarningDismissed = false
            }
            if !isEndDateValid {
                isEndDateWarningDismissed = false
            }
            isValidationWarningDismissed = false
            validationMessage = nonScheduleInvalidMessage
            return
        }

        restorePill(savedDraft: normalizedDraft(), historyMode: historyMode)
    }

    private func restorePill(savedDraft: EditPillDraft, historyMode: RestoreHistoryMode) {
        isSaving = true
        validationMessage = nil
        historyValidationMessage = nil

        Task {
            do {
                try await pillAppState.restorePill(from: savedDraft, historyMode: historyMode)
                isSaving = false
                onSaveSuccess()
                dismiss()
            } catch {
                if let error = error as? EditableHistoryValidationError {
                    historyValidationMessage = error.localizedDescription
                    if case .missingPillPastDays(let days) = error, let firstDay = days.first {
                        displayedMonth = month(containing: firstDay)
                    }
                } else {
                    isValidationWarningDismissed = false
                    validationMessage = pillAppState.actionErrorMessage ?? UserFacingErrorMessage.text(for: error)
                }
                isSaving = false
            }
        }
    }

    private func normalizedDraft() -> EditPillDraft {
        var normalized = draft
        normalized.skippedDays.subtract(normalized.takenDays)
        if isRestoreMode {
            normalized.restoreActiveFrom = normalizedRestoreActiveFrom
            normalized.scheduleEffectiveFrom = nil
        } else {
            normalized.restoreActiveFrom = nil
            normalized.scheduleEffectiveFrom = shouldUseScheduleEffectiveFrom ? currentEffectiveFromResolution?.resolvedDate : nil
        }
        if normalized.scheduleRule.isOneTime {
            normalized.endDate = nil
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
            explicitDays: draft.takenDays.union(draft.skippedDays),
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

    private func presentScheduleNotice(_ message: String) {
        scheduleNoticeDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            scheduleNoticeMessage = message
        }

        scheduleNoticeDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scheduleNoticeMessage = nil
                }
            }
        }
    }

    private func dismissScheduleNotice() {
        scheduleNoticeDismissTask?.cancel()
        scheduleNoticeDismissTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            scheduleNoticeMessage = nil
        }
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

    private static func month(containing date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func initialDisplayedMonth(startDate: Date) -> Date {
        HistoryMonthWindow.displayMonth(startDate: startDate, today: Date(), calendar: Calendar.current)
    }

    private var nonScheduleInvalidMessage: String? {
        if draft.trimmedName.isEmpty {
            return "Enter a pill name."
        }
        if draft.trimmedDosage.isEmpty {
            return "Enter a dosage."
        }
        return nil
    }

    private func handleNonScheduleValidationInputChanged() {
        isValidationWarningDismissed = false
        if nonScheduleInvalidMessage == nil,
           validationMessage == "Enter a pill name." || validationMessage == "Enter a dosage." {
            validationMessage = nil
        }
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
