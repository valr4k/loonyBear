import SwiftUI

struct EditHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: HabitAppState

    private let onSaveSuccess: () -> Void
    @State private var draft: EditHabitDraft
    @State private var validationMessage: String?
    @State private var displayedMonth: Date
    @State private var isSaving = false

    init(details: HabitDetailsProjection, onSaveSuccess: @escaping () -> Void = {}) {
        self.onSaveSuccess = onSaveSuccess
        _draft = State(initialValue: EditHabitDraft(
            id: details.id,
            type: details.type,
            startDate: details.startDate,
            name: details.name,
            scheduleDays: details.scheduleDays,
            reminderEnabled: details.reminderEnabled,
            reminderTime: details.reminderTime ?? ReminderTime.default(),
            completedDays: details.completedDays
        ))
        _displayedMonth = State(initialValue: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date())
    }

    var body: some View {
        AppScreen(backgroundStyle: .habits, topPadding: 8) {
            AppCard {
                VStack(alignment: .leading, spacing: 0) {
                    HabitNameInputField(text: $draft.name)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                    if shouldShowNameValidation {
                        AppSectionDivider()

                        validationText("Habit name is required.")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                    }

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

                        DatePicker("Time", selection: reminderDateBinding, displayedComponents: .hourAndMinute)
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
                        validationText("Select at least one day.")
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                AppCard {
                    CompletedDaysCalendarView(
                        month: displayedMonth,
                        editableDays: Set(editableCompletionDays),
                        selectedDays: $draft.completedDays,
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

            if !historicalCompletedDays.isEmpty {
                AppCard {
                    ForEach(historicalCompletedDays, id: \.self) { day in
                        HStack {
                            Text(day.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                        if day != historicalCompletedDays.last {
                            AppSectionDivider()
                        }
                    }
                }

                Text("Older completed days remain visible here, but cannot be edited.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if let validationMessage {
                AppValidationBanner(message: validationMessage)
            }
        }
        .navigationTitle(draft.type.sectionTitle)
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
                    save()
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
                let granted = await appState.requestNotificationAuthorizationIfNeeded()
                if !granted {
                    validationMessage = "Enable notifications in Settings to use reminders."
                    draft.reminderEnabled = false
                }
            }
        }
    }

    private var editableCompletionDays: [Date] {
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

    private var historicalCompletedDays: [Date] {
        let editableSet = Set(editableCompletionDays)
        return draft.completedDays
            .filter { !editableSet.contains($0) }
            .sorted(by: >)
    }

    private var availableMonths: [Date] {
        let months = Set(
            editableCompletionDays.compactMap {
                Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: $0))
            }
        )
        return months.sorted()
    }

    private var isFormValid: Bool {
        !draft.trimmedName.isEmpty && draft.scheduleDays.rawValue != 0
    }

    private var shouldShowNameValidation: Bool {
        draft.name.isEmpty == false && draft.trimmedName.isEmpty
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
            set: { newValue in
                draft.scheduleDays = newValue
            }
        )
    }

    private func save() {
        guard isFormValid else {
            validationMessage = draft.trimmedName.isEmpty ? "Habit name is required." : "Select at least one day."
            return
        }

        isSaving = true
        validationMessage = nil
        let savedDraft = draft

        Task {
            do {
                try appState.updateHabit(from: savedDraft)
                isSaving = false
                onSaveSuccess()
                dismiss()

                await appState.syncNotificationsAfterHabitUpdate(from: savedDraft)
            } catch {
                validationMessage = appState.actionErrorMessage ?? error.localizedDescription
                isSaving = false
            }
        }
    }

    @ViewBuilder
    private func validationText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

private struct CompletedDaysCalendarView: View {
    let month: Date
    let editableDays: Set<Date>
    @Binding var selectedDays: Set<Date>
    let availableMonths: [Date]
    let onMonthChange: (Date) -> Void
    @State private var availableWidth: CGFloat = 0
    @State private var transitionDirection: HabitCalendarTransitionDirection = .forward
    @State private var renderedMonth: Date
    @State private var outgoingMonth: Date?
    @State private var incomingOffset: CGFloat = 0
    @State private var outgoingOffset: CGFloat = 0
    
    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    init(
        month: Date,
        editableDays: Set<Date>,
        selectedDays: Binding<Set<Date>>,
        availableMonths: [Date],
        onMonthChange: @escaping (Date) -> Void
    ) {
        self.month = month
        self.editableDays = editableDays
        self._selectedDays = selectedDays
        self.availableMonths = availableMonths
        self.onMonthChange = onMonthChange
        _renderedMonth = State(initialValue: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        changeMonth(step: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBackward)
                    .foregroundStyle(canGoBackward ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))

                    Button {
                        changeMonth(step: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoForward)
                    .foregroundStyle(canGoForward ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }

            ZStack {
                if let outgoingMonth {
                    monthGridContent(for: outgoingMonth)
                        .frame(width: availableWidth == 0 ? nil : availableWidth, alignment: .top)
                        .offset(x: outgoingOffset)
                }

                monthGridContent(for: renderedMonth)
                    .frame(width: availableWidth == 0 ? nil : availableWidth, alignment: .top)
                    .offset(x: incomingOffset)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
        }
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HabitEditCalendarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(HabitEditCalendarWidthPreferenceKey.self) { width in
            availableWidth = width
        }
        .onChange(of: month) {
            animateMonthChange(to: month)
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -50 {
                        changeMonth(step: 1)
                    } else if value.translation.width > 50 {
                        changeMonth(step: -1)
                    }
                }
        )
    }

    private func monthGridContent(for displayMonth: Date) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(dayRows(for: displayMonth).indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(dayRows(for: displayMonth)[rowIndex]) { day in
                        Group {
                            if let date = day.date {
                                HabitCalendarDayView(
                                    dayNumber: calendar.component(.day, from: date),
                                    style: dayStyle(for: date),
                                    cellSize: cellSize
                                )
                                .contentShape(Circle())
                                .allowsHitTesting(editableDays.contains(date))
                                .onTapGesture {
                                    toggle(date)
                                }
                                .disabled(!editableDays.contains(date))
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Calendar.autoupdatingCurrent.locale ?? Locale.autoupdatingCurrent
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        return (Array(symbols[1...]) + [symbols[0]]).map { $0.uppercased() }
    }

    private func days(for displayMonth: Date) -> [CalendarDayCell] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayMonth),
            let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthInterval.start),
            let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else {
            return []
        }

        var result: [CalendarDayCell] = []
        var cursor = calendar.startOfDay(for: firstWeekInterval.start)
        let end = calendar.startOfDay(for: lastWeekInterval.end)

        while cursor < end {
            let isInDisplayedMonth = calendar.isDate(cursor, equalTo: displayMonth, toGranularity: .month)
            result.append(CalendarDayCell(id: cursor, date: isInDisplayedMonth ? cursor : nil))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: next)
        }

        return result
    }

    private func dayRows(for displayMonth: Date) -> [[CalendarDayCell]] {
        days(for: displayMonth).chunked(into: 7)
    }

    private var cellSize: CGFloat {
        let raw = floor((availableWidth - 8 * 6) / 7)
        return min(max(raw, 35), 40)
    }

    private var canGoBackward: Bool {
        guard let first = availableMonths.first else { return false }
        return month > first
    }

    private var canGoForward: Bool {
        guard let last = availableMonths.last else { return false }
        return month < last
    }

    private func toggle(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        guard editableDays.contains(normalizedDate) else { return }

        if selectedDays.contains(normalizedDate) {
            selectedDays.remove(normalizedDate)
        } else {
            selectedDays.insert(normalizedDate)
        }
    }

    private func changeMonth(step: Int) {
        guard let currentIndex = availableMonths.firstIndex(of: month) else { return }
        let nextIndex = currentIndex + step
        guard availableMonths.indices.contains(nextIndex) else { return }
        transitionDirection = step > 0 ? .forward : .backward
        onMonthChange(availableMonths[nextIndex])
    }

    private func animateMonthChange(to newMonth: Date) {
        guard newMonth != renderedMonth else { return }
        guard availableWidth > 0 else {
            renderedMonth = newMonth
            outgoingMonth = nil
            return
        }

        let width = availableWidth
        let incomingStart = transitionDirection == .forward ? width : -width
        let outgoingEnd = -incomingStart

        outgoingMonth = renderedMonth
        renderedMonth = newMonth
        incomingOffset = incomingStart
        outgoingOffset = 0

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.24)) {
                incomingOffset = 0
                outgoingOffset = outgoingEnd
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard renderedMonth == newMonth else { return }
            outgoingMonth = nil
            incomingOffset = 0
            outgoingOffset = 0
        }
    }

    private func dayStyle(for date: Date) -> HabitCalendarDayStyle {
        if selectedDays.contains(date) {
            return .selected
        } else if editableDays.contains(date) {
            return .available
        } else {
            return .disabled
        }
    }
}

private enum HabitCalendarTransitionDirection {
    case forward
    case backward
}

private struct CalendarDayCell: Identifiable {
    let id: Date
    let date: Date?
}

enum HabitCalendarDayStyle {
    case available
    case selected
    case disabled
}

struct HabitCalendarDayView: View {
    let dayNumber: Int
    let style: HabitCalendarDayStyle
    let cellSize: CGFloat

    private var selectionSize: CGFloat {
        min(cellSize, 42)
    }

    var body: some View {
        ZStack {
            if style == .selected {
                Circle()
                    .fill(Color(uiColor: .systemBlue).opacity(0.2))
                    .frame(width: selectionSize, height: selectionSize)
            }

            Text("\(dayNumber)")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
        }
        .frame(width: cellSize, height: cellSize)
        .frame(maxWidth: .infinity, minHeight: selectionSize)
    }

    private var foreground: Color {
        switch style {
        case .selected:
            return .blue
        case .available:
            return .primary
        case .disabled:
            return Color(uiColor: .tertiaryLabel)
        }
    }
}

private struct HabitEditCalendarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }

        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start ..< Swift.min(start + size, count)])
        }
    }
}
