import SwiftUI
import UIKit

enum AppLayout {
    static let screenSpacing: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 18
    static let schedulePopoverRowVerticalPadding: CGFloat = 12
    static let inlinePadding: CGFloat = 4
    static let cardCornerRadius: CGFloat = 22
    static let insetCardCornerRadius: CGFloat = 18
    static let listIconWidth: CGFloat = 22
    static let listIconSize: CGFloat = 18
    static let actionIconSize: CGFloat = 20
    static let tintSwatchSize: CGFloat = 26
}

enum AppTint: String, CaseIterable, Identifiable {
    static let storageKey = "app_tint"

    case blue
    case indigo
    case cyan
    case teal
    case green
    case brown
    case amber
    case red
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue:
            return "Blue"
        case .indigo:
            return "Indigo"
        case .cyan:
            return "Cyan"
        case .teal:
            return "Teal"
        case .green:
            return "Green"
        case .brown:
            return "Brown"
        case .amber:
            return "Amber"
        case .red:
            return "Red"
        case .white:
            return "White"
        }
    }

    var accentColor: Color {
        Color(uiColor: accentUIColor)
    }

    var accentUIColor: UIColor {
        switch self {
        case .white:
            return .label
        case .blue, .indigo, .cyan, .teal, .green, .brown, .amber, .red:
            return uiColor
        }
    }

    var uiColor: UIColor {
        switch self {
        case .white:
            return .white
        case .blue:
            return .systemBlue
        case .indigo:
            return .systemIndigo
        case .cyan:
            return .systemCyan
        case .teal:
            return .systemTeal
        case .green:
            return .systemGreen
        case .brown:
            return .systemBrown
        case .amber:
            return .systemOrange
        case .red:
            return .systemRed
        }
    }

    var swatchColor: Color {
        Color(uiColor: uiColor)
    }

    var swatchCheckmarkColor: Color {
        switch self {
        case .white:
            return .black
        case .blue, .indigo, .cyan, .teal, .green, .brown, .amber, .red:
            return .white
        }
    }

    func calendarPositiveForeground(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .white:
            return colorScheme == .dark ? .black : .white
        case .blue, .indigo, .cyan, .teal, .green, .brown, .amber, .red:
            return .white
        }
    }

    func backgroundWashOpacity(for colorScheme: ColorScheme) -> Double {
        switch colorScheme {
        case .dark:
            return 0.1
        case .light:
            return 0.075
        @unknown default:
            return 0.075
        }
    }

    static func stored(rawValue: String) -> AppTint {
        switch rawValue {
        case "default":
            return .blue
        case "gray", "yellow":
            return .brown
        default:
            return AppTint(rawValue: rawValue) ?? .blue
        }
    }

    static func isValidStoredRawValue(_ rawValue: String) -> Bool {
        AppTint(rawValue: rawValue) != nil || rawValue == "default" || rawValue == "gray" || rawValue == "yellow"
    }
}

private struct AppTintModifier: ViewModifier {
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    func body(content: Content) -> some View {
        content.tint(AppTint.stored(rawValue: appTintRawValue).accentColor)
    }
}

private struct AppAccentForegroundModifier: ViewModifier {
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    func body(content: Content) -> some View {
        content.foregroundStyle(AppTint.stored(rawValue: appTintRawValue).accentColor)
    }
}

private struct AppBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        AppToolbarIconLabel("Back", systemName: "chevron.left")
                    }
                    .appAccentTint()
                }
            }
    }
}

struct AppToolbarIconLabel: View {
    let title: String
    let systemName: String

    init(_ title: String, systemName: String) {
        self.title = title
        self.systemName = systemName
    }

    var body: some View {
        Label(title, systemImage: systemName)
            .labelStyle(.iconOnly)
    }
}

extension View {
    func appAccentTint() -> some View {
        modifier(AppTintModifier())
    }

    func appAccentForeground() -> some View {
        modifier(AppAccentForegroundModifier())
    }

    func appTintedBackButton() -> some View {
        modifier(AppBackButtonModifier())
    }

    func appNotificationSettingsAlert(isPresented: Binding<Bool>) -> some View {
        modifier(AppNotificationSettingsAlertModifier(isPresented: isPresented))
    }
}

private struct AppNotificationSettingsAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .alert("Notifications are off", isPresented: $isPresented) {
                Button("Open Settings") {
                    openAppSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(AppCopy.notificationsRequired)
            }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

enum AppCopy {
    static let chooseAtLeastOneDay = "Choose at least one day."
    static let notificationsRequired = "Turn on notifications in Settings to use reminders."
    static let backupFolderHint = "Backups stay in the selected Files folder even if the app is deleted. After reinstalling, choose the same folder again before restoring."
    static let pillHistoryFollowsSchedule = "History follows schedule from start date."
    static let pillHistoryCountsEveryDay = "History counts every day from the start date."
    static let habitHistoryFollowsSchedule = "History follows schedule from start date."
    static let habitHistoryCountsEveryDay = "History counts every day from the start date."
    static let pillDescriptionPlaceholder = "Notes (optional)"
    static let habitHistoryHint = "Today: None, Completed, or Skipped.\nPast days: Completed or Skipped only.\nYou can edit the last 30 days.\nDays before the start date can’t be edited"
    static let pillHistoryHint = "Today: None, Taken, or Skipped.\nPast days: Taken or Skipped only.\nYou can edit the last 30 days.\nDays before the start date can’t be edited"

    static func overdueScheduledDayEditMessage(actionLabel: String) -> String {
        "Choose \(actionLabel) or Skipped for the overdue scheduled day before saving."
    }

    static func overdueScheduledDayDetailsMessage(actionLabel: String) -> String {
        "Open Edit and choose \(actionLabel) or Skipped for the overdue scheduled day."
    }

    static func missingScheduledDaysDetailsMessage(actionLabel: String) -> String {
        "Open Edit and choose \(actionLabel) or Skipped for every past scheduled day."
    }
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
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

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
        Color(uiColor: appTint.uiColor)
    }

    private var tintOpacity: Double {
        0
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
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
    var usesTintedChevron = false

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            AppReadOnlyValueCapsule(
                text: value,
                valueColor: valueColor,
                showsChevron: showsChevron,
                usesTintedChevron: usesTintedChevron
            )
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

private struct AppReadOnlyValueCapsule: View {
    let text: String
    var valueColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    var showsChevron = false
    var usesTintedChevron = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .modifier(AppChevronForegroundStyle(usesTint: usesTintedChevron))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(Color(uiColor: .tertiarySystemFill))
        }
    }
}

private struct AppChevronForegroundStyle: ViewModifier {
    let usesTint: Bool

    func body(content: Content) -> some View {
        if usesTint {
            content.appAccentForeground()
        } else {
            content.foregroundStyle(.tertiary)
        }
    }
}

private struct AppPickerValueCapsule: View {
    let text: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .multilineTextAlignment(.trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
        }
        .appAccentForeground()
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(Color(uiColor: .tertiarySystemFill))
        }
    }
}

@MainActor
private enum AppDatePickerPopoverPrewarmer {
    private static var didWarmUp = false
    private static var isWarmingUp = false
    private static var retainedWarmUpView: UIView?

    static func warmUpDeferred() async {
        guard !didWarmUp, !isWarmingUp else { return }
        isWarmingUp = true
        try? await Task.sleep(nanoseconds: 180_000_000)

        guard !Task.isCancelled else {
            isWarmingUp = false
            return
        }

        warmUpNow()
        isWarmingUp = false
    }

    private static func warmUpNow() {
        guard !didWarmUp else { return }
        didWarmUp = true

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 340, height: 260))
        container.alpha = 0
        container.isUserInteractionEnabled = false

        let datePicker = UIDatePicker(frame: CGRect(x: 0, y: 0, width: 320, height: 260))
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .inline

        let timePicker = UIDatePicker(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        timePicker.datePickerMode = .time
        timePicker.preferredDatePickerStyle = .wheels

        container.addSubview(datePicker)
        container.addSubview(timePicker)
        container.setNeedsLayout()
        container.layoutIfNeeded()

        retainedWarmUpView = container
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            retainedWarmUpView = nil
        }
    }
}

struct AppSchedulePickerRow<PopoverContent: View>: View {
    let value: String
    let onTap: (() -> Void)?
    @ViewBuilder let popoverContent: PopoverContent
    @State private var isShowingPopover = false

    init(
        value: String,
        onTap: (() -> Void)? = nil,
        @ViewBuilder popoverContent: () -> PopoverContent
    ) {
        self.value = value
        self.onTap = onTap
        self.popoverContent = popoverContent()
    }

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture {
                AppDescriptionFieldSupport.dismissKeyboard()
                onTap?()
                isShowingPopover = true
            }
        .popover(
            isPresented: $isShowingPopover,
            attachmentAnchor: .point(.trailing),
            arrowEdge: .trailing
        ) {
            popoverContent
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.clear)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            Text("Schedule")
                .foregroundStyle(.primary)

            Spacer()

            AppPickerValueCapsule(text: value, showsChevron: true)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
    }
}

struct AppReminderTimeRows: View {
    @Binding var isEnabled: Bool
    @Binding var reminderDate: Date
    let onTimeTap: (() -> Void)?
    @State private var isShowingTimePicker = false

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
                    .simultaneousGesture(TapGesture().onEnded {
                        dismissKeyboardForNonTextControl()
                    })
            }
            .padding(.horizontal, AppLayout.rowHorizontalPadding)
            .padding(.vertical, AppLayout.rowVerticalPadding)

            if isEnabled {
                AppSectionDivider()
                timePickerRow
            }
        }
        .task {
            await AppDatePickerPopoverPrewarmer.warmUpDeferred()
        }
    }

    @ViewBuilder
    private var timePickerRow: some View {
        HStack(spacing: 16) {
            Text("Time")
                .foregroundStyle(.primary)

            Spacer()

            AppPickerValueCapsule(text: formattedTime)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboardForNonTextControl()
            isShowingTimePicker = true
        }
        .popover(
            isPresented: $isShowingTimePicker,
            attachmentAnchor: .point(.trailing),
            arrowEdge: .trailing
        ) {
            DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .appAccentTint()
                .frame(width: 220, height: 180)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var formattedTime: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func dismissKeyboardForNonTextControl() {
        AppDescriptionFieldSupport.dismissKeyboard()
        onTimeTap?()
    }
}

struct AppStartDatePickerRow: View {
    @Binding var date: Date
    let range: ClosedRange<Date>
    let onTap: (() -> Void)?
    @State private var isShowingDatePicker = false

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
        HStack(spacing: 16) {
            Text("Start Date")
                .foregroundStyle(.primary)

            Spacer()

            AppPickerValueCapsule(text: formattedDate)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            AppDescriptionFieldSupport.dismissKeyboard()
            onTap?()
            isShowingDatePicker = true
        }
        .popover(
            isPresented: $isShowingDatePicker,
            attachmentAnchor: .point(.trailing),
            arrowEdge: .trailing
        ) {
            DatePicker(
                "",
                selection: $date,
                in: range,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .appAccentTint()
            .frame(width: 320)
            .padding(8)
            .presentationCompactAdaptation(.popover)
        }
        .task {
            await AppDatePickerPopoverPrewarmer.warmUpDeferred()
        }
    }

    private var formattedDate: String {
        date.formatted(date: .abbreviated, time: .omitted)
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

struct AppNotificationSettingsSection<PopoverContent: View>: View {
    let scheduleSummary: String
    let scheduleTap: (() -> Void)?
    @Binding var reminderEnabled: Bool
    @Binding var reminderDate: Date
    let reminderTimeTap: (() -> Void)?
    @ViewBuilder let schedulePopoverContent: PopoverContent

    init(
        scheduleSummary: String,
        scheduleTap: (() -> Void)? = nil,
        reminderEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        reminderTimeTap: (() -> Void)? = nil,
        @ViewBuilder schedulePopoverContent: () -> PopoverContent
    ) {
        self.scheduleSummary = scheduleSummary
        self.scheduleTap = scheduleTap
        _reminderEnabled = reminderEnabled
        _reminderDate = reminderDate
        self.reminderTimeTap = reminderTimeTap
        self.schedulePopoverContent = schedulePopoverContent()
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
                        schedulePopoverContent
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
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

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
        dismissKeyboard()
        guard focusedField == descriptionField else { return }

        setIsDismissingKeyboardForNonTextControl(true)
        setFocusedField(nil)

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
            VStack(alignment: .leading, spacing: 8) {
                AppScheduleEditorSectionContent(
                    scheduleDays: $scheduleDays,
                    onTap: onTap,
                    useScheduleForHistory: useScheduleForHistory,
                    helperText: helperText
                )
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .appTintedBackButton()
    }
}

struct AppScheduleEditorPopoverContent: View {
    @Binding var scheduleDays: WeekdaySet
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    init(
        scheduleDays: Binding<WeekdaySet>,
        onTap: (() -> Void)? = nil,
        useScheduleForHistory: Binding<Bool>? = nil,
        helperText: String? = nil
    ) {
        _scheduleDays = scheduleDays
        self.onTap = onTap
        self.useScheduleForHistory = useScheduleForHistory
        self.helperText = helperText
    }

    var body: some View {
        AppScheduleEditorPopoverBody(
            scheduleDays: $scheduleDays,
            onTap: onTap,
            useScheduleForHistory: useScheduleForHistory,
            helperText: helperText
        )
    }
}

private struct AppScheduleEditorSectionContent: View {
    @Binding var scheduleDays: WeekdaySet
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppCard {
                AppScheduleEditorListContent(
                    scheduleDays: $scheduleDays,
                    onTap: onTap,
                    useScheduleForHistory: useScheduleForHistory
                )
            }

            if let helperText {
                AppHelperText(text: helperText)
            }
        }
    }
}

private struct AppScheduleEditorPopoverBody: View {
    @Binding var scheduleDays: WeekdaySet
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppScheduleEditorListContent(
                scheduleDays: $scheduleDays,
                onTap: onTap,
                useScheduleForHistory: useScheduleForHistory
            )

            if let helperText {
                AppHelperText(text: helperText)
                    .padding(.horizontal, 12)
                    .padding(.top, -18)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 340)
    }
}

private struct AppScheduleEditorListContent: View {
    @Binding var scheduleDays: WeekdaySet
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InlineDaysSelector(selection: $scheduleDays)
                .appTapAction(onTap)

            if let useScheduleForHistory {
                HStack(spacing: 16) {
                    Text("Use schedule for history?")
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

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
}

private struct CenteredInputTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let capitalization: UITextAutocapitalizationType
    let autocorrectionType: UITextAutocorrectionType
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

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
        textField.tintColor = AppTint.stored(rawValue: appTintRawValue).accentUIColor
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
        uiView.tintColor = AppTint.stored(rawValue: appTintRawValue).accentUIColor
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

struct AppCompactValidationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.12), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct AppHistoryReviewRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        )
    }
}

struct AppFloatingWarningBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemRed))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Label("Dismiss", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .systemRed).opacity(0.18))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .systemRed).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

enum OverdueDayLabel {
    static func text(for overdueDay: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let normalizedOverdueDay = calendar.startOfDay(for: overdueDay)
        let today = calendar.startOfDay(for: now)
        if normalizedOverdueDay == today {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           normalizedOverdueDay == calendar.startOfDay(for: yesterday) {
            return "Yesterday"
        }
        let components = calendar.dateComponents([.day, .month, .year], from: normalizedOverdueDay)
        guard
            let day = components.day,
            let month = components.month,
            let year = components.year
        else {
            return normalizedOverdueDay.formatted(date: .abbreviated, time: .omitted)
        }
        return String(format: "%02d.%02d.%04d", day, month, year)
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
            AppReadOnlyScheduleCard(scheduleDays: scheduleDays)
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .appTintedBackButton()
    }
}

struct AppReadOnlySchedulePopoverContent: View {
    let scheduleDays: WeekdaySet

    var body: some View {
        AppReadOnlyScheduleList(scheduleDays: scheduleDays)
            .frame(width: 280)
            .presentationCompactAdaptation(.popover)
    }
}

private struct AppReadOnlyScheduleCard: View {
    let scheduleDays: WeekdaySet

    var body: some View {
        AppCard {
            AppReadOnlyScheduleList(scheduleDays: scheduleDays)
        }
    }
}

private struct AppReadOnlyScheduleList: View {
    let scheduleDays: WeekdaySet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(WeekdayDisplay.fullNames, id: \.label) { day in
                AppReadOnlyScheduleRow(
                    title: day.label,
                    isSelected: scheduleDays.contains(day.value)
                )
            }
        }
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
        .padding(.vertical, AppLayout.schedulePopoverRowVerticalPadding)
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
                    .appAccentForeground()

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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(WeekdayDisplay.fullNames, id: \.label) { day in
                HStack {
                    Text(day.label)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(day.value) {
                        Image(systemName: "checkmark")
                            .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                            .appAccentForeground()
                    }
                }
                .padding(.horizontal, AppLayout.rowHorizontalPadding)
                .padding(.vertical, AppLayout.schedulePopoverRowVerticalPadding)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(day.value)
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

private enum WeekdayDisplay {
    static let fullNames: [(label: String, value: WeekdaySet)] = [
        ("Monday", .monday),
        ("Tuesday", .tuesday),
        ("Wednesday", .wednesday),
        ("Thursday", .thursday),
        ("Friday", .friday),
        ("Saturday", .saturday),
        ("Sunday", .sunday),
    ]
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

struct AppLegendEntry {
    let label: String
    let color: Color
    let fillOpacity: Double
    let strokeOpacity: Double

    init(
        label: String,
        color: Color,
        fillOpacity: Double = 0.2,
        strokeOpacity: Double = 0.35
    ) {
        self.label = label
        self.color = color
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
    }
}

struct AppLegend: View {
    let items: [AppLegendEntry]

    init(items: [(label: String, color: Color)]) {
        self.items = items.map {
            AppLegendEntry(label: $0.label, color: $0.color)
        }
    }

    init(items: [AppLegendEntry]) {
        self.items = items
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(items, id: \.label) { item in
                AppLegendItem(item: item)
            }
        }
        .padding(.horizontal, AppLayout.inlinePadding)
    }
}

private struct AppLegendItem: View {
    let item: AppLegendEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.color.opacity(item.fillOpacity))
                .overlay {
                    Circle()
                        .stroke(item.color.opacity(item.strokeOpacity), lineWidth: 1)
                }
                .frame(width: 18, height: 18)

            Text(item.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct AppListIcon: View {
    let symbol: String
    var tint: Color?
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    init(symbol: String, tint: Color? = nil) {
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: AppLayout.listIconSize, weight: .regular))
            .foregroundStyle(tint ?? AppTint.stored(rawValue: appTintRawValue).accentColor)
            .frame(width: AppLayout.listIconWidth)
    }
}

struct AppActionIcon: View {
    let symbol: String
    var tint: Color?
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    init(symbol: String, tint: Color? = nil) {
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: AppLayout.actionIconSize, weight: .semibold))
            .foregroundStyle(tint ?? AppTint.stored(rawValue: appTintRawValue).accentColor)
            .frame(width: AppLayout.listIconWidth, height: AppLayout.listIconWidth)
    }
}
