import SwiftUI
import UIKit

struct EditPillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState

    private let onSaveSuccess: () -> Void
    private let onDeleteSuccess: () -> Void
    private let onArchiveSuccess: () -> Void
    private let showsCloseButton: Bool
    private let requiredPastScheduledDays: Set<Date>
    private let scheduledDates: Set<Date>
    private let scheduleHistory: [PillScheduleVersion]
    private let activeOverdueDay: Date?
    private let originalScheduleRule: ScheduleRule
    @FocusState private var focusedField: Field?
    @State private var draft: EditPillDraft
    @State private var pendingScheduleRule: ScheduleRule?
    @State private var displayedMonth: Date
    @State private var validationMessage: String?
    @State private var historyValidationMessage: String?
    @State private var scheduleInfoMessage: String?
    @State private var scheduleInfoDismissTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var isDismissingKeyboardForNonTextControl = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingArchiveConfirmation = false
    @State private var isShowingNotificationSettingsAlert = false
    @State private var isHistoryWarningDismissed = false
    @State private var isScheduleWarningDismissed = false
    @State private var isArchived: Bool

    private enum Field: Hashable {
        case description
    }

    init(
        details: PillDetailsProjection,
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
        _draft = State(initialValue: EditPillDraft(
            id: details.id,
            name: details.name,
            dosage: details.dosage,
            details: details.details ?? "",
            startDate: details.startDate,
            endDate: details.endDate,
            scheduleRule: details.scheduleRule,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            takenDays: details.takenDays,
            skippedDays: details.skippedDays
        ))
        _displayedMonth = State(initialValue: Self.initialDisplayedMonth(startDate: details.startDate))
        _isArchived = State(initialValue: details.isArchived)
    }

    var body: some View {
        ScrollViewReader { proxy in
            AppScreen(backgroundStyle: .pills, topPadding: 8) {
                detailsSection
                scheduleSection

                VStack(alignment: .leading, spacing: 8) {
                    AppFormSectionHeader(title: "Calendar")

                    AppCard {
                        PillHistoryCalendarView(
                            month: displayedMonth,
                            editableDays: editableHistoryDays,
                            scheduledDates: previewScheduledDates,
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

                }

                descriptionSection

                actionButtons

                if let validationMessage {
                    AppValidationBanner(message: validationMessage)
                }

                if let endDateValidationMessage {
                    AppValidationBanner(message: endDateValidationMessage)
                }
            }
            .overlay(alignment: .bottom) {
                floatingBottomBanners
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
                AppDescriptionFieldSupport.dismissKeyboard()
            }
            .navigationTitle("Edit Pill")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .alert("Delete Pill?", isPresented: $isShowingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deletePill()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This pill will be permanently deleted.")
            }
            .alert(archiveConfirmationTitle, isPresented: $isShowingArchiveConfirmation) {
                Button(archiveActionTitle) {
                    setPillArchived(!isArchived)
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(archiveConfirmationMessage)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: shouldShowDescriptionInset ? 36 : 0)
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
                resolveEffectiveFromSelection(showAdjustmentBanner: false)
                clearEndDateForNeverRepeat(showInfo: true)
            }
            .onAppear {
                applyPendingScheduleRuleIfNeeded()
                resolveEffectiveFromSelection(showAdjustmentBanner: false)
                clearEndDateForNeverRepeat(showInfo: false)
            }
            .appNotificationSettingsAlert(isPresented: $isShowingNotificationSettingsAlert)
            .onChange(of: draft.takenDays) { _, _ in
                historyValidationMessage = nil
                resolveEffectiveFromSelection(showAdjustmentBanner: false)
            }
            .onChange(of: draft.skippedDays) { _, _ in
                historyValidationMessage = nil
                resolveEffectiveFromSelection(showAdjustmentBanner: false)
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
            .animation(.easeInOut(duration: 0.18), value: scheduleInfoMessage)
            .animation(.easeInOut(duration: 0.18), value: isHistoryWarningDismissed)
            .animation(.easeInOut(duration: 0.18), value: isScheduleWarningDismissed)
            .onDisappear {
                scheduleInfoDismissTask?.cancel()
            }
        }
    }

    private var detailsSection: some View {
        AppPillDetailsCard(name: $draft.name, dosage: $draft.dosage)
    }

    private var scheduleSection: some View {
        AppEditScheduleSection(
            reminderEnabled: $draft.reminderEnabled,
            reminderDate: $draft.reminderTime.dateBinding(fallback: ReminderTime.default()),
            repeatSummary: draft.scheduleRule.compactSummary,
            endDate: $draft.endDate,
            endDateRange: selectableEndDateRange,
            endDateFallback: draft.startDate,
            isEndDateEnabled: !draft.scheduleRule.isOneTime,
            reminderTimeTap: dismissKeyboardForNonTextControl,
            repeatTap: dismissKeyboardForNonTextControl,
            endDateTap: dismissKeyboardForNonTextControl
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

    private var descriptionSection: some View {
        AppFormCardSection(title: "Description") {
            TextField(AppCopy.pillDescriptionPlaceholder, text: $draft.details, axis: .vertical)
                .appAccentTint()
                .focused($focusedField, equals: .description)
                .lineLimit(3 ... 6)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
        }
        .id(Field.description)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            archiveRestoreButton
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

    private var archiveRestoreButton: some View {
        Button {
            isShowingArchiveConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: archiveActionSystemImage)
                    .imageScale(.medium)
                    .foregroundStyle(isArchiveRestoreButtonEnabled ? .primary : .secondary)

                Text(archiveActionTitle)
                    .foregroundStyle(isArchiveRestoreButtonEnabled ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppNeutralCapsuleActionButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(!isArchiveRestoreButtonEnabled)
    }

    private var isArchiveRestoreButtonEnabled: Bool {
        !isSaving && (!isArchived || isFormValid)
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
            !draft.trimmedDosage.isEmpty &&
            draft.scheduleRule.isValidSelection &&
            isScheduleEffectiveFromValid &&
            isEndDateValid
    }

    private var hasScheduleChanged: Bool {
        draft.scheduleRule != originalScheduleRule
    }

    private var shouldUseScheduleEffectiveFrom: Bool {
        hasScheduleChanged || isArchived
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
        guard !draft.scheduleRule.isOneTime, let endDate = draft.endDate else {
            return true
        }
        let normalizedEndDate = Calendar.current.startOfDay(for: endDate)
        guard normalizedEndDate >= selectableEndDateRange.lowerBound else {
            return false
        }
        return hasScheduledDay(from: selectableEndDateRange.lowerBound, through: normalizedEndDate)
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

    private func hasScheduledDay(from lowerBound: Date, through endDate: Date) -> Bool {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: lowerBound)
        let normalizedEndDate = calendar.startOfDay(for: endDate)
        let cappedEndDate = min(
            normalizedEndDate,
            calendar.date(byAdding: .day, value: 31, to: cursor).map { calendar.startOfDay(for: $0) } ?? normalizedEndDate
        )

        while cursor <= cappedEndDate {
            if HistoryScheduleApplicability.isScheduled(
                on: cursor,
                startDate: draft.startDate,
                endDate: normalizedEndDate,
                from: validationScheduleVersions,
                calendar: calendar
            ) {
                return true
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return false
    }

    private var currentMissingPastDays: [Date] {
        guard !isArchived else { return [] }
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

            if let message = scheduleInfoMessage {
                AppFloatingInfoBanner(message: message) {
                    dismissScheduleInfo()
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

    private var shouldShowDescriptionInset: Bool {
        AppDescriptionFieldSupport.shouldShowInset(
            focusedField: focusedField,
            descriptionField: .description,
            isDismissingKeyboardForNonTextControl: isDismissingKeyboardForNonTextControl
        )
    }

    private var archiveActionTitle: String {
        isArchived ? "Restore" : "Archive"
    }

    private var archiveActionSystemImage: String {
        isArchived ? "arrow.uturn.backward" : "archivebox"
    }

    private var archiveConfirmationTitle: String {
        isArchived ? "Restore Pill?" : "Archive Pill?"
    }

    private var archiveConfirmationMessage: String {
        isArchived
            ? "Save changes and move this pill back to its active section."
            : "This pill will move to Archived."
    }

    private func save() {
        applyPendingScheduleRuleIfNeeded()

        guard isFormValid else {
            if !draft.scheduleRule.isValidSelection {
                isScheduleWarningDismissed = false
            }
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

    private func stageScheduleRule(_ scheduleRule: ScheduleRule) {
        pendingScheduleRule = scheduleRule
    }

    private func applyPendingScheduleRuleIfNeeded() {
        guard let scheduleRule = pendingScheduleRule else { return }
        pendingScheduleRule = nil
        guard draft.scheduleRule != scheduleRule else { return }
        draft.scheduleRule = scheduleRule
    }

    private func clearEndDateForNeverRepeat(showInfo: Bool) {
        guard draft.scheduleRule.isOneTime, draft.endDate != nil else { return }
        draft.endDate = nil

        if showInfo {
            presentScheduleInfo(AppCopy.endDateRemovedForNeverRepeat)
        }
    }

    private func deletePill() {
        isSaving = true
        validationMessage = nil
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

    private func setPillArchived(_ archived: Bool) {
        if !archived, isArchived {
            restorePill()
            return
        }

        isSaving = true
        validationMessage = nil
        historyValidationMessage = nil

        Task {
            await pillAppState.setPillArchived(id: draft.id, isArchived: archived)
            if let errorMessage = pillAppState.actionErrorMessage {
                validationMessage = errorMessage
                isSaving = false
                return
            }

            isArchived = archived
            isSaving = false
            onArchiveSuccess()
            dismiss()
        }
    }

    private func restorePill() {
        applyPendingScheduleRuleIfNeeded()

        guard isFormValid else {
            if !draft.scheduleRule.isValidSelection {
                isScheduleWarningDismissed = false
            }
            validationMessage = nonScheduleInvalidMessage
            return
        }

        isSaving = true
        validationMessage = nil
        historyValidationMessage = nil
        let restoredDraft = normalizedDraft()

        Task {
            do {
                try await pillAppState.updatePill(from: restoredDraft)
                await pillAppState.setPillArchived(id: draft.id, isArchived: false)
                if let errorMessage = pillAppState.actionErrorMessage {
                    validationMessage = errorMessage
                    isSaving = false
                    return
                }

                isArchived = false
                isSaving = false
                onArchiveSuccess()
                dismiss()
            } catch {
                if let error = error as? EditableHistoryValidationError {
                    historyValidationMessage = error.localizedDescription
                    if case .missingPillPastDays(let days) = error, let firstDay = days.first {
                        displayedMonth = month(containing: firstDay)
                    }
                } else {
                    validationMessage = pillAppState.actionErrorMessage ?? UserFacingErrorMessage.text(for: error)
                }
                isSaving = false
            }
        }
    }

    private func normalizedDraft() -> EditPillDraft {
        var normalized = draft
        normalized.skippedDays.subtract(normalized.takenDays)
        normalized.scheduleEffectiveFrom = shouldUseScheduleEffectiveFrom ? currentEffectiveFromResolution?.resolvedDate : nil
        if normalized.scheduleRule.isOneTime {
            normalized.endDate = nil
        }
        if let endDate = normalized.endDate {
            normalized.endDate = max(Calendar.current.startOfDay(for: endDate), selectableEndDateRange.lowerBound)
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

    private func presentScheduleInfo(_ message: String) {
        scheduleInfoDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            scheduleInfoMessage = message
        }

        scheduleInfoDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scheduleInfoMessage = nil
                }
            }
        }
    }

    private func dismissScheduleInfo() {
        scheduleInfoDismissTask?.cancel()
        scheduleInfoDismissTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            scheduleInfoMessage = nil
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
        if let endDateValidationMessage {
            return endDateValidationMessage
        }
        return nil
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
