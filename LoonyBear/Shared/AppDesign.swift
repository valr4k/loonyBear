import SwiftUI
import UIKit

enum AppLayout {
    static let screenSpacing: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 18
    static let inlinePadding: CGFloat = 4
    static let cardCornerRadius: CGFloat = 22
    static let insetCardCornerRadius: CGFloat = 18
    static let listIconWidth: CGFloat = 22
    static let listIconSize: CGFloat = 18
    static let actionIconSize: CGFloat = 20
}

enum AppCopy {
    static let chooseAtLeastOneDay = "Choose at least one day."
    static let notificationsRequired = "Turn on notifications in Settings to use reminders."
    static let backupFolderHint = "Backups stay in the selected Files folder even if the app is deleted. After reinstalling, choose the same folder again before restoring."
    static let pillHistoryFollowsSchedule = "History follows your selected schedule from the start date."
    static let pillHistoryCountsEveryDay = "History counts every day from the start date."
    static let habitHistoryFollowsSchedule = "History follows your selected schedule from the start date."
    static let habitHistoryCountsEveryDay = "History counts every day from the start date."
    static let pillDescriptionPlaceholder = "Notes (optional)"
    static let habitHistoryHint = "Today: None, Completed, or Skipped.\nPast days: Completed or Skipped only.\nYou can edit the last 30 days.\nDays before the start date can’t be edited"
    static let pillHistoryHint = "Today: None, Taken, or Skipped.\nPast days: Taken or Skipped only.\nYou can edit the last 30 days.\nDays before the start date can’t be edited"
}

enum AppBackgroundStyle {
    case `default`
    case habits
    case pills
    case settings
}

struct AppScreen<Content: View>: View {
    var backgroundStyle: AppBackgroundStyle = .default
    var topPadding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppLayout.screenSpacing) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 40)
        }
        .background(AppBackground(style: backgroundStyle))
    }
}

struct AppBackground: View {
    let style: AppBackgroundStyle
    @Environment(\.colorScheme) private var colorScheme

    init(style: AppBackgroundStyle = .default) {
        self.style = style
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            tintColor
                .opacity(tintOpacity)
        }
        .ignoresSafeArea()
    }

    private var tintColor: Color {
        .clear
    }

    private var tintOpacity: Double {
        0
    }
}

extension View {
    @ViewBuilder
    func appTapAction(_ action: (() -> Void)?) -> some View {
        if let action {
            simultaneousGesture(TapGesture().onEnded {
                action()
            })
        } else {
            self
        }
    }
}

struct AppSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        content
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct AppInsetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.insetCardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

struct AppValueRow: View {
    let title: String
    let value: String
    var valueColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    var showsChevron = false

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 7) {
                Text(value)
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

struct AppSchedulePickerRow<Destination: View>: View {
    let value: String
    let onTap: (() -> Void)?
    @ViewBuilder let destination: Destination

    init(
        value: String,
        onTap: (() -> Void)? = nil,
        @ViewBuilder destination: () -> Destination
    ) {
        self.value = value
        self.onTap = onTap
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .appTapAction(onTap)
    }

    private var rowContent: some View {
        AppValueRow(
            title: "Schedule",
            value: value,
            valueColor: AnyShapeStyle(.secondary),
            showsChevron: true
        )
    }
}

struct AppReminderTimeRows: View {
    @Binding var isEnabled: Bool
    @Binding var reminderDate: Date
    let onTimeTap: (() -> Void)?

    init(
        isEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        onTimeTap: (() -> Void)? = nil
    ) {
        _isEnabled = isEnabled
        _reminderDate = reminderDate
        self.onTimeTap = onTimeTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("Reminder")
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }
            .padding(.horizontal, AppLayout.rowHorizontalPadding)
            .padding(.vertical, AppLayout.rowVerticalPadding)

            if isEnabled {
                AppSectionDivider()
                timePickerRow
            }
        }
    }

    @ViewBuilder
    private var timePickerRow: some View {
        DatePicker("Time", selection: $reminderDate, displayedComponents: .hourAndMinute)
            .datePickerStyle(.compact)
            .appTapAction(onTimeTap)
            .padding(.horizontal, AppLayout.rowHorizontalPadding)
            .padding(.vertical, AppLayout.rowVerticalPadding)
    }
}

struct AppStartDatePickerRow: View {
    @Binding var date: Date
    let range: ClosedRange<Date>
    let onTap: (() -> Void)?

    init(
        date: Binding<Date>,
        range: ClosedRange<Date>,
        onTap: (() -> Void)? = nil
    ) {
        _date = date
        self.range = range
        self.onTap = onTap
    }

    var body: some View {
        DatePicker(
            "Start Date",
            selection: $date,
            in: range,
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .appTapAction(onTap)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
    }
}

struct AppStartDateValueRow: View {
    let date: Date

    var body: some View {
        AppValueRow(
            title: "Start Date",
            value: date.formatted(date: .abbreviated, time: .omitted)
        )
    }
}

struct AppNotificationSettingsSection<Destination: View>: View {
    let scheduleSummary: String
    let scheduleTap: (() -> Void)?
    @Binding var reminderEnabled: Bool
    @Binding var reminderDate: Date
    let reminderTimeTap: (() -> Void)?
    @ViewBuilder let scheduleDestination: Destination

    init(
        scheduleSummary: String,
        scheduleTap: (() -> Void)? = nil,
        reminderEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        reminderTimeTap: (() -> Void)? = nil,
        @ViewBuilder scheduleDestination: () -> Destination
    ) {
        self.scheduleSummary = scheduleSummary
        self.scheduleTap = scheduleTap
        _reminderEnabled = reminderEnabled
        _reminderDate = reminderDate
        self.reminderTimeTap = reminderTimeTap
        self.scheduleDestination = scheduleDestination()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFormSectionHeader(title: "Notifications")

            AppCard {
                VStack(alignment: .leading, spacing: 0) {
                    AppSchedulePickerRow(
                        value: scheduleSummary,
                        onTap: scheduleTap
                    ) {
                        scheduleDestination
                    }

                    AppSectionDivider()

                    AppReminderTimeRows(
                        isEnabled: $reminderEnabled,
                        reminderDate: $reminderDate,
                        onTimeTap: reminderTimeTap
                    )
                }
            }
        }
    }
}

extension Binding where Value == ReminderTime {
    func dateBinding(fallback: ReminderTime) -> Binding<Date> {
        Binding<Date>(
            get: {
                let components = DateComponents(hour: wrappedValue.hour, minute: wrappedValue.minute)
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                wrappedValue = ReminderTime(
                    hour: components.hour ?? fallback.hour,
                    minute: components.minute ?? fallback.minute
                )
            }
        )
    }
}

enum AppDescriptionFieldSupport {
    static func shouldShowInset<Field: Equatable>(
        focusedField: Field?,
        descriptionField: Field,
        isDismissingKeyboardForNonTextControl: Bool
    ) -> Bool {
        focusedField == descriptionField && !isDismissingKeyboardForNonTextControl
    }

    static func scrollIntoView<Field: Hashable>(
        with proxy: ScrollViewProxy,
        focusedField: Field?,
        descriptionField: Field,
        isDismissingKeyboardForNonTextControl: Bool,
        anchor: Field
    ) {
        guard
            focusedField == descriptionField,
            !isDismissingKeyboardForNonTextControl
        else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(anchor, anchor: .bottom)
            }
        }
    }

    static func dismissKeyboardForNonTextControl<Field: Hashable>(
        focusedField: Field?,
        descriptionField: Field,
        setFocusedField: @escaping (Field?) -> Void,
        setIsDismissingKeyboardForNonTextControl: @escaping (Bool) -> Void
    ) {
        guard focusedField == descriptionField else { return }

        setIsDismissingKeyboardForNonTextControl(true)
        setFocusedField(nil)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            setIsDismissingKeyboardForNonTextControl(false)
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

struct AppHabitNameCard<ValidationContent: View>: View {
    @Binding var text: String
    let showsValidation: Bool
    @ViewBuilder let validationContent: ValidationContent

    init(
        text: Binding<String>,
        showsValidation: Bool,
        @ViewBuilder validationContent: () -> ValidationContent
    ) {
        _text = text
        self.showsValidation = showsValidation
        self.validationContent = validationContent()
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 0) {
                HabitNameInputField(text: $text)
                    .padding(.horizontal, AppLayout.rowHorizontalPadding)
                    .padding(.vertical, AppLayout.rowVerticalPadding)

                if showsValidation {
                    AppSectionDivider()

                    validationContent
                        .padding(.horizontal, AppLayout.rowHorizontalPadding)
                        .padding(.vertical, 14)
                }
            }
        }
    }
}

struct AppPillDetailsCard: View {
    @Binding var name: String
    @Binding var dosage: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 0) {
                CenteredInputField(
                    text: $name,
                    placeholder: "Pill name",
                    capitalization: .sentences,
                    autocorrectionType: .default
                )
                .padding(.horizontal, AppLayout.rowHorizontalPadding)
                .padding(.vertical, AppLayout.rowVerticalPadding)

                AppSectionDivider()

                CenteredInputField(
                    text: $dosage,
                    placeholder: "Dosage",
                    capitalization: .none,
                    autocorrectionType: .no
                )
                .padding(.horizontal, AppLayout.rowHorizontalPadding)
                .padding(.vertical, AppLayout.rowVerticalPadding)
            }
        }
    }
}

struct AppScheduleEditorScreen: View {
    let backgroundStyle: AppBackgroundStyle
    @Binding var scheduleDays: WeekdaySet
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    init(
        backgroundStyle: AppBackgroundStyle,
        scheduleDays: Binding<WeekdaySet>,
        onTap: (() -> Void)? = nil,
        useScheduleForHistory: Binding<Bool>? = nil,
        helperText: String? = nil
    ) {
        self.backgroundStyle = backgroundStyle
        _scheduleDays = scheduleDays
        self.onTap = onTap
        self.useScheduleForHistory = useScheduleForHistory
        self.helperText = helperText
    }

    var body: some View {
        AppScreen(backgroundStyle: backgroundStyle, topPadding: 8) {
            VStack(alignment: .leading, spacing: 20) {
                AppCard {
                    VStack(alignment: .leading, spacing: 0) {
                        InlineDaysSelector(selection: $scheduleDays)
                            .appTapAction(onTap)

                        if let useScheduleForHistory {
                            AppSectionDivider()

                            HStack(spacing: 16) {
                                Text("Use schedule for history?")
                                    .foregroundStyle(.primary)

                                Spacer()

                                Toggle("", isOn: useScheduleForHistory)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, AppLayout.rowHorizontalPadding)
                            .padding(.vertical, AppLayout.rowVerticalPadding)
                            .appTapAction(onTap)
                        }

                        if scheduleDays.rawValue == 0 {
                            HStack {
                                AppInlineErrorText(text: AppCopy.chooseAtLeastOneDay)
                                Spacer()
                            }
                            .padding(.horizontal, AppLayout.rowHorizontalPadding)
                            .padding(.bottom, 16)
                        }
                    }
                }

                if let helperText {
                    AppHelperText(text: helperText)
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
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

struct AppValidationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.12), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct AppSectionDivider: View {
    var inset: CGFloat = AppLayout.rowHorizontalPadding

    var body: some View {
        Divider()
            .padding(.leading, inset)
    }
}

struct AppFormSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

struct AppFormCardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFormSectionHeader(title: title)

            AppCard {
                content
            }
        }
    }
}

struct AppReadOnlyScheduleView: View {
    let scheduleDays: WeekdaySet
    let backgroundStyle: AppBackgroundStyle

    var body: some View {
        AppScreen(backgroundStyle: backgroundStyle, topPadding: 8) {
            AppCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(WeekdaySet.orderedDays.enumerated()), id: \.offset) { index, day in
                        AppReadOnlyScheduleRow(
                            title: day.0,
                            isSelected: scheduleDays.contains(day.1)
                        )

                        if index < WeekdaySet.orderedDays.count - 1 {
                            AppSectionDivider()
                        }
                    }
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppReadOnlyScheduleRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
    }
}

struct AppEmptyStateCard: View {
    let title: String
    let message: String
    let symbol: String
    let buttonTitle: String?
    let action: (() -> Void)?

    init(title: String, message: String, symbol: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        AppCard {
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.blue)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let buttonTitle, let action {
                    Button(buttonTitle, action: action)
                        .buttonStyle(.glassProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }
}

struct InlineDaysSelector: View {
    @Binding var selection: WeekdaySet

    private let fullDayNames: [(String, WeekdaySet)] = [
        ("Monday", .monday),
        ("Tuesday", .tuesday),
        ("Wednesday", .wednesday),
        ("Thursday", .thursday),
        ("Friday", .friday),
        ("Saturday", .saturday),
        ("Sunday", .sunday),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(fullDayNames, id: \.0) { day in
                HStack {
                    Text(day.0)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(day.1) {
                        Image(systemName: "checkmark")
                            .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, AppLayout.rowHorizontalPadding)
                .padding(.vertical, AppLayout.rowVerticalPadding)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(day.1)
                }

                if day.0 != fullDayNames.last?.0 {
                    AppSectionDivider()
                }

            }
        }
    }

    private func toggle(_ weekday: WeekdaySet) {
        var updatedSelection = selection
        if updatedSelection.contains(weekday) {
            updatedSelection.remove(weekday)
        } else {
            updatedSelection.insert(weekday)
        }
        selection = updatedSelection
    }
}

struct AppInlineErrorText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.red)
            .lineSpacing(1)
    }
}

struct AppHelperText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .padding(.horizontal, AppLayout.inlinePadding)
    }
}

struct AppLegend: View {
    let items: [(label: String, color: Color)]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(items, id: \.label) { item in
                AppLegendItem(label: item.label, color: item.color)
            }
        }
        .padding(.horizontal, AppLayout.inlinePadding)
    }
}

private struct AppLegendItem: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.2))
                .overlay {
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 1)
                }
                .frame(width: 18, height: 18)

            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct AppListIcon: View {
    let symbol: String
    var tint: Color = .blue

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: AppLayout.listIconSize, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: AppLayout.listIconWidth)
    }
}

struct AppActionIcon: View {
    let symbol: String
    var tint: Color = .blue

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: AppLayout.actionIconSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: AppLayout.listIconWidth, height: AppLayout.listIconWidth)
    }
}
