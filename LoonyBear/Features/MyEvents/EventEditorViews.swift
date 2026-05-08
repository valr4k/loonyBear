import Combine
import SwiftUI
import UIKit

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventAppState: EventAppState

    @State private var draft = EventDraft()
    @State private var isValidationWarningDismissed = false
    @State private var isSaving = false
    @StateObject private var presentationGuard = EventTimingPresentationGuard()

    var body: some View {
        AppScreen(topPadding: 8) {
            VStack(alignment: .leading, spacing: 20) {
                EventNameSection(name: $draft.name)
                EventTimingSection(
                    mode: $draft.mode,
                    date: $draft.date,
                    presentationGuard: presentationGuard
                )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                AppDescriptionFieldSupport.dismissKeyboard()
            }
        }
        .overlay(alignment: .bottom) {
            floatingBottomBanners
        }
        .navigationTitle("Add new Event")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    AppToolbarIconLabel("Close", systemName: "xmark")
                }
                .appAccentTint()
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveEvent()
                } label: {
                    AppToolbarIconLabel("Save", systemName: "checkmark")
                }
                .appToolbarActionTint(isDisabled: !isFormValid || isSaving)
                .fontWeight(.semibold)
                .disabled(!isFormValid || isSaving)
            }
        }
        .onChange(of: draft.mode) { oldMode, newMode in
            applyModeSwitch(from: oldMode, to: newMode)
            handleValidationInputChanged()
        }
        .onChange(of: draft.date) { _, _ in
            handleValidationInputChanged()
        }
        .onChange(of: draft.name) { _, _ in
            handleValidationInputChanged()
        }
        .animation(.easeInOut(duration: 0.18), value: validationMessage)
        .animation(.easeInOut(duration: 0.18), value: isValidationWarningDismissed)
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && validationMessage == nil
    }

    private var validationMessage: String? {
        EventValidation.validationMessage(mode: draft.mode, date: draft.date)
    }

    @ViewBuilder
    private var floatingBottomBanners: some View {
        if let message = validationMessage, !isValidationWarningDismissed {
            AppFloatingWarningBanner(message: message) {
                isValidationWarningDismissed = true
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func applyModeSwitch(from oldMode: EventMode, to newMode: EventMode) {
        guard oldMode != newMode else { return }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let selectedDate = calendar.startOfDay(for: draft.date)

        switch newMode {
        case .countdown where selectedDate < today:
            draft.date = EventDateDefaults.countdownDate(today: today, calendar: calendar)
        case .countUp where selectedDate > today:
            draft.date = EventDateDefaults.countUpDate(today: today, calendar: calendar)
        default:
            draft.date = selectedDate
        }
    }

    private func handleValidationInputChanged() {
        if validationMessage == nil {
            isValidationWarningDismissed = false
            return
        }

        isValidationWarningDismissed = false
    }

    private func saveEvent() {
        guard isFormValid else {
            isValidationWarningDismissed = false
            return
        }

        isSaving = true
        Task {
            do {
                _ = try await eventAppState.createEvent(from: draft)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}

struct EditEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventAppState: EventAppState

    @State private var draft: EditEventDraft
    @State private var isValidationWarningDismissed = false
    @State private var isSaving = false
    @State private var isShowingDeleteConfirmation = false
    @StateObject private var presentationGuard = EventTimingPresentationGuard()

    init(details: EventDetailsProjection) {
        _draft = State(initialValue: EditEventDraft(details: details))
    }

    var body: some View {
        AppScreen(topPadding: 8) {
            VStack(alignment: .leading, spacing: 20) {
                EventNameSection(name: $draft.name)
                EventTimingSection(
                    mode: $draft.mode,
                    date: $draft.date,
                    presentationGuard: presentationGuard
                )
                deleteButton
            }
            .contentShape(Rectangle())
            .onTapGesture {
                AppDescriptionFieldSupport.dismissKeyboard()
            }
        }
        .overlay(alignment: .bottom) {
            floatingBottomBanners
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    AppToolbarIconLabel("Close", systemName: "xmark")
                }
                .appAccentTint()
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveEvent()
                } label: {
                    AppToolbarIconLabel("Save", systemName: "checkmark")
                }
                .appToolbarActionTint(isDisabled: !isFormValid || isSaving)
                .fontWeight(.semibold)
                .disabled(!isFormValid || isSaving)
            }
        }
        .alert("Delete this Event?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteEvent()
            }
        } message: {
            Text("This Event will be permanently deleted.")
        }
        .onChange(of: draft.mode) { oldMode, newMode in
            applyModeSwitch(from: oldMode, to: newMode)
            handleValidationInputChanged()
        }
        .onChange(of: draft.date) { _, _ in
            handleValidationInputChanged()
        }
        .onChange(of: draft.name) { _, _ in
            handleValidationInputChanged()
        }
        .animation(.easeInOut(duration: 0.18), value: validationMessage)
        .animation(.easeInOut(duration: 0.18), value: isValidationWarningDismissed)
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && validationMessage == nil
    }

    private var validationMessage: String? {
        EventValidation.validationMessage(mode: draft.mode, date: draft.date)
    }

    private var deleteButton: some View {
        Button {
            isShowingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppMaterialCapsuleActionButtonStyle())
        .foregroundStyle(.red)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var floatingBottomBanners: some View {
        if let message = validationMessage, !isValidationWarningDismissed {
            AppFloatingWarningBanner(message: message) {
                isValidationWarningDismissed = true
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func applyModeSwitch(from oldMode: EventMode, to newMode: EventMode) {
        guard oldMode != newMode else { return }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let selectedDate = calendar.startOfDay(for: draft.date)

        switch newMode {
        case .countdown where selectedDate < today:
            draft.date = EventDateDefaults.countdownDate(today: today, calendar: calendar)
        case .countUp where selectedDate > today:
            draft.date = EventDateDefaults.countUpDate(today: today, calendar: calendar)
        default:
            draft.date = selectedDate
        }
    }

    private func handleValidationInputChanged() {
        if validationMessage == nil {
            isValidationWarningDismissed = false
            return
        }

        isValidationWarningDismissed = false
    }

    private func saveEvent() {
        guard isFormValid else {
            isValidationWarningDismissed = false
            return
        }

        isSaving = true
        Task {
            do {
                try await eventAppState.updateEvent(from: draft)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }

    private func deleteEvent() {
        Task {
            await eventAppState.deleteEvent(id: draft.id)
            await MainActor.run {
                dismiss()
            }
        }
    }
}

private struct EventNameSection: View {
    @Binding var name: String

    var body: some View {
        AppCard {
            TextField("Name", text: $name)
                .appAccentTint()
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
        }
    }
}

private struct EventTimingSection: View {
    @Binding var mode: EventMode
    @Binding var date: Date
    @ObservedObject var presentationGuard: EventTimingPresentationGuard

    var body: some View {
        AppFormCardSection(title: "Timing") {
            EventModePickerRow(
                mode: $mode,
                presentationGuard: presentationGuard
            )

            AppSectionDivider()

            AppDatePickerRow(
                title: "Date",
                date: $date,
                onTap: {
                    presentationGuard.blockModeForDatePickerTouch()
                },
                isPickerPresentationBlocked: presentationGuard.isDatePickerPresentationBlocked
            )
        }
    }
}

private struct EventModePickerRow: View {
    @Binding var mode: EventMode
    @ObservedObject var presentationGuard: EventTimingPresentationGuard
    @State private var isShowingOptions = false

    var body: some View {
        HStack(spacing: 16) {
            Text("Mode")
                .foregroundStyle(.primary)

            Spacer()

            Button {
                toggleOptions()
            } label: {
                HStack(spacing: 6) {
                    Text(mode.title)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .frame(minWidth: 128, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
            .allowsHitTesting(!presentationGuard.isModePresentationBlocked)
            .appTouchDownAction {
                guard !presentationGuard.isModePresentationBlocked, !isShowingOptions else { return }
                presentationGuard.blockDatePickerForModeTouch()
            }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            AppDescriptionFieldSupport.dismissKeyboard()
        })
        .popover(
            isPresented: optionsPresentationBinding,
            attachmentAnchor: .point(.trailing),
            arrowEdge: .trailing
        ) {
            optionsPopover
        }
    }

    private var optionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(EventMode.allCases, id: \.self) { option in
                Button {
                    mode = option
                    setOptionsPresented(false)
                } label: {
                    HStack(spacing: 14) {
                        Text(option.title)
                            .foregroundStyle(.primary)

                        Spacer()

                        if option == mode {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 220)
        .padding(.vertical, 8)
        .presentationCompactAdaptation(.popover)
    }

    private var optionsPresentationBinding: Binding<Bool> {
        Binding(
            get: { isShowingOptions },
            set: { isPresented in
                setOptionsPresented(isPresented)
            }
        )
    }

    private func toggleOptions() {
        guard !presentationGuard.isModePresentationBlocked else { return }
        AppDescriptionFieldSupport.dismissKeyboard()

        if isShowingOptions {
            setOptionsPresented(false)
        } else {
            presentationGuard.blockDatePickerForModeTouch()
            setOptionsPresented(true)
        }
    }

    private func setOptionsPresented(_ isPresented: Bool) {
        guard isShowingOptions != isPresented else { return }
        isShowingOptions = isPresented
        presentationGuard.setModeOptionsPresented(isPresented)
    }
}

@MainActor
final class EventTimingPresentationGuard: ObservableObject {
    @Published private(set) var isDatePickerPresentationBlocked = false
    @Published private(set) var isModePresentationBlocked = false

    private static let touchBlockDurationNanoseconds: UInt64 = 200_000_000
    private var dateTouchReleaseTask: Task<Void, Never>?
    private var modeTouchReleaseTask: Task<Void, Never>?

    deinit {
        dateTouchReleaseTask?.cancel()
        modeTouchReleaseTask?.cancel()
    }

    func setModeOptionsPresented(_ isPresented: Bool) {
        modeTouchReleaseTask?.cancel()
        modeTouchReleaseTask = nil
        isDatePickerPresentationBlocked = isPresented
    }

    func blockModeForDatePickerTouch() {
        dateTouchReleaseTask?.cancel()
        isModePresentationBlocked = true
        dateTouchReleaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.touchBlockDurationNanoseconds)
            guard !Task.isCancelled else { return }
            isModePresentationBlocked = false
        }
    }

    func blockDatePickerForModeTouch() {
        modeTouchReleaseTask?.cancel()
        isDatePickerPresentationBlocked = true
        modeTouchReleaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.touchBlockDurationNanoseconds)
            guard !Task.isCancelled else { return }
            isDatePickerPresentationBlocked = false
        }
    }
}
