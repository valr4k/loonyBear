import SwiftUI
import UIKit

enum AppLayout {
    static let screenSpacing: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 18
    static let schedulePopoverRowVerticalPadding: CGFloat = 12
    static let scheduleStepperRowVerticalPadding: CGFloat = 6
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
    case green
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue:
            return "Blue"
        case .indigo:
            return "Indigo"
        case .green:
            return "Green"
        case .amber:
            return "Amber"
        }
    }

    var accentColor: Color {
        Color(uiColor: accentUIColor)
    }

    var accentUIColor: UIColor {
        uiColor
    }

    var uiColor: UIColor {
        switch self {
        case .blue:
            return .systemBlue
        case .indigo:
            return .systemIndigo
        case .green:
            return .systemGreen
        case .amber:
            return .systemOrange
        }
    }

    var swatchColor: Color {
        Color(uiColor: uiColor)
    }

    var swatchCheckmarkColor: Color {
        .white
    }

    func calendarPositiveForeground(for _: ColorScheme) -> Color {
        .white
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
        case "default", "gray", "yellow", "cyan", "teal", "brown", "red", "white":
            return .blue
        default:
            return AppTint(rawValue: rawValue) ?? .blue
        }
    }

    static func isValidStoredRawValue(_ rawValue: String) -> Bool {
        AppTint(rawValue: rawValue) != nil
            || rawValue == "default"
            || rawValue == "gray"
            || rawValue == "yellow"
            || rawValue == "cyan"
            || rawValue == "teal"
            || rawValue == "brown"
            || rawValue == "red"
            || rawValue == "white"
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

private struct AppToolbarActionTintModifier: ViewModifier {
    let isDisabled: Bool
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    func body(content: Content) -> some View {
        content.tint(AppTint.stored(rawValue: appTintRawValue).accentColor)
    }
}

private struct AppBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .background(AppInteractivePopGestureEnabler())
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

private struct AppInteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableSwipeBack()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSwipeBack()
        }

        func enableSwipeBack() {
            guard let navigationController else { return }
            navigationController.interactivePopGestureRecognizer?.delegate = nil
            navigationController.interactivePopGestureRecognizer?.isEnabled = navigationController.viewControllers.count > 1
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

    func appToolbarActionTint(isDisabled: Bool) -> some View {
        modifier(AppToolbarActionTintModifier(isDisabled: isDisabled))
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
    static let endDateRemovedForNeverRepeat = "End Date removed because Repeat is Never."
    static let backupFolderHint = "Backups stay in the selected Files folder even if the app is deleted. After reinstalling, choose the same folder again before restoring."
    static let pillHistoryFollowsSchedule = "History follows schedule from start date."
    static let pillHistoryCountsEveryDay = "History counts every day from the start date."
    static let habitHistoryFollowsSchedule = "History follows schedule from start date."
    static let habitHistoryCountsEveryDay = "History counts every day from the start date."
    static let pillDescriptionPlaceholder = "(optional)"
    static let habitHistoryHint = "Today: None, Completed, or Skipped.\nPast days: Completed or Skipped only."
    static let pillHistoryHint = "Today: None, Taken, or Skipped.\nPast days: Taken or Skipped only."

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

struct AppPlainValueRow: View {
    let title: String
    let value: String
    var valueColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    var showsChevron = false

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 6) {
                Text(value)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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

private struct AppPickerValueLabel: View {
    let text: String
    var isTinted = true
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
        }
        .modifier(AppPickerValueForegroundStyle(isTinted: isTinted))
    }
}

private struct AppPickerValueForegroundStyle: ViewModifier {
    let isTinted: Bool

    func body(content: Content) -> some View {
        if isTinted {
            content.appAccentForeground()
        } else {
            content.foregroundStyle(.primary)
        }
    }
}

struct AppSchedulePickerRow<PopoverContent: View>: View {
    let title: String
    let value: String
    let onTap: (() -> Void)?
    @ViewBuilder let popoverContent: PopoverContent
    @State private var isShowingPopover = false
    @State private var isValueTinted = false

    init(
        title: String = "Schedule",
        value: String,
        onTap: (() -> Void)? = nil,
        @ViewBuilder popoverContent: () -> PopoverContent
    ) {
        self.title = title
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
            .onChange(of: isShowingPopover) { _, isPresented in
                if !isPresented {
                    setValueTinted(false)
                }
            }
            .onDisappear {
                setValueTinted(false)
            }
            .popover(
                isPresented: popoverPresentationBinding,
                attachmentAnchor: .point(.trailing),
                arrowEdge: .trailing
            ) {
                popoverContent
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.clear)
                    .background {
                        AppPopoverLifecycleObserver(
                            onWillAppear: {
                                setValueTinted(true)
                            },
                            onWillDismiss: {
                                setValueTinted(false)
                            },
                            onWillDisappear: {
                                setValueTinted(false)
                            }
                        )
                    }
            }
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            AppPickerValueLabel(text: value, isTinted: isShowingPopover && isValueTinted, showsChevron: true)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
    }

    private var popoverPresentationBinding: Binding<Bool> {
        Binding(
            get: { isShowingPopover },
            set: { isPresented in
                if !isPresented {
                    setValueTinted(false)
                }
                isShowingPopover = isPresented
            }
        )
    }

    private func setValueTinted(_ isTinted: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil

        withTransaction(transaction) {
            isValueTinted = isTinted
        }
    }
}

private struct AppCreateRepeatPickerRow<Destination: View>: View {
    let value: String
    let onTap: (() -> Void)?
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 16) {
                Text("Repeat")
                    .foregroundStyle(.primary)

                Spacer()

                AppPickerValueLabel(text: value, isTinted: false, showsChevron: true)
            }
            .padding(.horizontal, AppLayout.rowHorizontalPadding)
            .padding(.vertical, AppLayout.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            AppDescriptionFieldSupport.dismissKeyboard()
            onTap?()
        })
    }
}

private struct AppPopoverLifecycleObserver: UIViewControllerRepresentable {
    let onWillAppear: () -> Void
    let onWillDismiss: () -> Void
    let onWillDisappear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(
            onWillAppear: onWillAppear,
            onWillDismiss: onWillDismiss,
            onWillDisappear: onWillDisappear
        )
    }

    func updateUIViewController(_ viewController: Controller, context: Context) {
        viewController.onWillAppear = onWillAppear
        viewController.onWillDismiss = onWillDismiss
        viewController.onWillDisappear = onWillDisappear
        viewController.attachDismissDelegate()
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate {
        var onWillAppear: () -> Void
        var onWillDismiss: () -> Void
        var onWillDisappear: () -> Void

        init(
            onWillAppear: @escaping () -> Void,
            onWillDismiss: @escaping () -> Void,
            onWillDisappear: @escaping () -> Void
        ) {
            self.onWillAppear = onWillAppear
            self.onWillDismiss = onWillDismiss
            self.onWillDisappear = onWillDisappear
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            DispatchQueue.main.async { [weak self] in
                self?.onWillAppear()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachDismissDelegate()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onWillDismiss()
            DispatchQueue.main.async { [weak self] in
                self?.onWillDisappear()
            }
        }

        func attachDismissDelegate() {
            let controllers = [
                self,
                parent,
                presentingViewController,
                parent?.presentingViewController,
            ].compactMap { $0 }

            for controller in controllers {
                if let popoverPresentationController = controller.presentationController as? UIPopoverPresentationController {
                    popoverPresentationController.delegate = self
                } else {
                    controller.presentationController?.delegate = self
                }

                controller.popoverPresentationController?.delegate = self
            }
        }

        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            onWillDismiss()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            onWillDisappear()
        }

        func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
            onWillDismiss()
            return true
        }

        func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
            onWillDisappear()
        }

        func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
            .none
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController,
            traitCollection: UITraitCollection
        ) -> UIModalPresentationStyle {
            .none
        }
    }
}

struct AppReminderTimeRows: View {
    @Binding var isEnabled: Bool
    @Binding var reminderDate: Date
    let onTimeTap: (() -> Void)?
    let isPickerPresentationBlocked: Bool

    init(
        isEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        onTimeTap: (() -> Void)? = nil,
        isPickerPresentationBlocked: Bool = false
    ) {
        _isEnabled = isEnabled
        _reminderDate = reminderDate
        self.onTimeTap = onTimeTap
        self.isPickerPresentationBlocked = isPickerPresentationBlocked
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
    }

    @ViewBuilder
    private var timePickerRow: some View {
        HStack(spacing: 16) {
            Text("Time")
                .foregroundStyle(.primary)

            Spacer()

            DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .appAccentTint()
                .fixedSize()
                .allowsHitTesting(!isPickerPresentationBlocked)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            dismissKeyboardForNonTextControl()
        })
    }

    private func dismissKeyboardForNonTextControl() {
        AppDescriptionFieldSupport.dismissKeyboard()
        onTimeTap?()
    }
}

struct AppStartDatePickerRow: View {
    @Binding var date: Date
    let range: ClosedRange<Date>?
    let onTap: (() -> Void)?
    let isPickerPresentationBlocked: Bool

    init(
        date: Binding<Date>,
        range: ClosedRange<Date>? = nil,
        onTap: (() -> Void)? = nil,
        isPickerPresentationBlocked: Bool = false
    ) {
        _date = date
        self.range = range
        self.onTap = onTap
        self.isPickerPresentationBlocked = isPickerPresentationBlocked
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("Start Date")
                .foregroundStyle(.primary)

            Spacer()

            datePicker
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            AppDescriptionFieldSupport.dismissKeyboard()
            onTap?()
        })
    }

    @ViewBuilder
    private var datePicker: some View {
        if let range {
            DatePicker("", selection: $date, in: range, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .appAccentTint()
                .fixedSize()
                .allowsHitTesting(!isPickerPresentationBlocked)
        } else {
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .appAccentTint()
                .fixedSize()
                .allowsHitTesting(!isPickerPresentationBlocked)
        }
    }
}

struct AppStartDateValueRow: View {
    let date: Date

    var body: some View {
        AppPlainValueRow(
            title: "Start Date",
            value: date.formatted(date: .abbreviated, time: .omitted)
        )
    }
}

struct AppEffectiveFromPickerRow: View {
    @Binding var date: Date
    let range: ClosedRange<Date>
    let isEnabled: Bool
    let onTap: (() -> Void)?
    let isPickerPresentationBlocked: Bool

    init(
        date: Binding<Date>,
        range: ClosedRange<Date>,
        isEnabled: Bool = true,
        onTap: (() -> Void)? = nil,
        isPickerPresentationBlocked: Bool = false
    ) {
        _date = date
        self.range = range
        self.isEnabled = isEnabled
        self.onTap = onTap
        self.isPickerPresentationBlocked = isPickerPresentationBlocked
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("Apply From")
                .foregroundStyle(.primary)

            Spacer()

            if isEnabled {
                DatePicker("", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .appAccentTint()
                    .fixedSize()
                    .allowsHitTesting(!isPickerPresentationBlocked)
            } else {
                AppReadOnlyValueCapsule(
                    text: Self.displayDate(date),
                    valueColor: AnyShapeStyle(.secondary)
                )
            }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard isEnabled else { return }
            AppDescriptionFieldSupport.dismissKeyboard()
            onTap?()
        })
    }

    private static func displayDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct AppOptionalEndDatePickerRow: View {
    let title: String
    let emptyTitle: String
    @Binding var date: Date?
    let range: PartialRangeFrom<Date>
    let fallbackDate: Date
    let isEnabled: Bool
    let onTap: (() -> Void)?
    let onOptionsPresentationChange: (Bool) -> Void
    let isPickerPresentationBlocked: Bool
    @State private var isShowingEndDateOptions = false

    init(
        title: String = "End Date",
        emptyTitle: String = "Never",
        date: Binding<Date?>,
        range: PartialRangeFrom<Date>,
        fallbackDate: Date,
        isEnabled: Bool = true,
        onTap: (() -> Void)? = nil,
        onOptionsPresentationChange: @escaping (Bool) -> Void = { _ in },
        isPickerPresentationBlocked: Bool = false
    ) {
        self.title = title
        self.emptyTitle = emptyTitle
        _date = date
        self.range = range
        self.fallbackDate = fallbackDate
        self.isEnabled = isEnabled
        self.onTap = onTap
        self.onOptionsPresentationChange = onOptionsPresentationChange
        self.isPickerPresentationBlocked = isPickerPresentationBlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    guard isEnabled else { return }
                    AppDescriptionFieldSupport.dismissKeyboard()
                    onTap?()
                    setEndDateOptionsPresented(true)
                } label: {
                    HStack(spacing: 6) {
                        Text(date == nil ? emptyTitle : "On Date")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(minWidth: 128, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
                .allowsHitTesting(isEnabled)
            }
            .padding(.horizontal, AppLayout.rowHorizontalPadding)
            .padding(.vertical, AppLayout.rowVerticalPadding)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                AppDescriptionFieldSupport.dismissKeyboard()
                onTap?()
            })
            .popover(
                isPresented: endDateOptionsPresentationBinding,
                attachmentAnchor: .point(.trailing),
                arrowEdge: .trailing
            ) {
                endDateOptionsPopover
            }

            if isEnabled, date != nil {
                AppSectionDivider()

                HStack(spacing: 16) {
                    Text("Date")
                        .foregroundStyle(.primary)

                    Spacer()

                    DatePicker("", selection: dateBinding, in: range, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .appAccentTint()
                        .fixedSize()
                        .allowsHitTesting(!isPickerPresentationBlocked)
                }
                .padding(.horizontal, AppLayout.rowHorizontalPadding)
                .padding(.vertical, AppLayout.rowVerticalPadding)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    AppDescriptionFieldSupport.dismissKeyboard()
                    onTap?()
                })
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var endDateOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            endDateOptionButton(title: "Never", isSelected: date == nil) {
                applyEndDateSelection(nil)
            }

            endDateOptionButton(title: "On Date", isSelected: date != nil) {
                applyEndDateSelection(clampedFallbackDate)
            }
        }
        .frame(width: 220)
        .padding(.vertical, 8)
        .presentationCompactAdaptation(.popover)
    }

    private func endDateOptionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
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

    private func applyEndDateSelection(_ newDate: Date?) {
        date = newDate
        setEndDateOptionsPresented(false)
    }

    private var endDateOptionsPresentationBinding: Binding<Bool> {
        Binding(
            get: { isShowingEndDateOptions },
            set: { isPresented in
                setEndDateOptionsPresented(isPresented)
            }
        )
    }

    private func setEndDateOptionsPresented(_ isPresented: Bool) {
        guard isShowingEndDateOptions != isPresented else { return }
        isShowingEndDateOptions = isPresented
        onOptionsPresentationChange(isPresented)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                date.map { Calendar.current.startOfDay(for: $0) } ?? clampedFallbackDate
            },
            set: { newValue in
                date = Calendar.current.startOfDay(for: newValue)
            }
        )
    }

    private var clampedFallbackDate: Date {
        let normalizedFallback = Calendar.current.startOfDay(for: fallbackDate)
        return max(normalizedFallback, range.lowerBound)
    }
}

struct AppCreateScheduleSection<RepeatDestination: View>: View {
    @Binding var startDate: Date
    let startDateRange: ClosedRange<Date>?
    @Binding var reminderEnabled: Bool
    @Binding var reminderDate: Date
    @Binding var endDate: Date?
    let endDateRange: PartialRangeFrom<Date>
    let isEndDateEnabled: Bool
    let endDateTitle: String
    let endDateEmptyTitle: String
    let repeatSummary: String
    let startDateTap: (() -> Void)?
    let reminderTimeTap: (() -> Void)?
    let repeatTap: (() -> Void)?
    let endDateTap: (() -> Void)?
    @ViewBuilder let repeatDestination: RepeatDestination
    @State private var isEndDateOptionsTransitionBlockingPickers = false
    @State private var endDateOptionsTransitionReleaseTask: Task<Void, Never>?

    init(
        startDate: Binding<Date>,
        startDateRange: ClosedRange<Date>? = nil,
        reminderEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        endDate: Binding<Date?>,
        endDateRange: PartialRangeFrom<Date>,
        isEndDateEnabled: Bool = true,
        endDateTitle: String = "End Date",
        endDateEmptyTitle: String = "Never",
        repeatSummary: String,
        startDateTap: (() -> Void)? = nil,
        reminderTimeTap: (() -> Void)? = nil,
        repeatTap: (() -> Void)? = nil,
        endDateTap: (() -> Void)? = nil,
        @ViewBuilder repeatDestination: () -> RepeatDestination
    ) {
        _startDate = startDate
        self.startDateRange = startDateRange
        _reminderEnabled = reminderEnabled
        _reminderDate = reminderDate
        _endDate = endDate
        self.endDateRange = endDateRange
        self.isEndDateEnabled = isEndDateEnabled
        self.endDateTitle = endDateTitle
        self.endDateEmptyTitle = endDateEmptyTitle
        self.repeatSummary = repeatSummary
        self.startDateTap = startDateTap
        self.reminderTimeTap = reminderTimeTap
        self.repeatTap = repeatTap
        self.endDateTap = endDateTap
        self.repeatDestination = repeatDestination()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFormSectionHeader(title: "Schedule")

            AppCard {
                VStack(alignment: .leading, spacing: 0) {
                    AppStartDatePickerRow(
                        date: $startDate,
                        range: startDateRange,
                        onTap: startDateTap,
                        isPickerPresentationBlocked: isEndDateOptionsTransitionBlockingPickers
                    )

                    AppSectionDivider()

                    AppReminderTimeRows(
                        isEnabled: $reminderEnabled,
                        reminderDate: $reminderDate,
                        onTimeTap: reminderTimeTap,
                        isPickerPresentationBlocked: isEndDateOptionsTransitionBlockingPickers
                    )

                    AppSectionDivider()

                    AppCreateRepeatPickerRow(
                        value: repeatSummary,
                        onTap: repeatTap
                    ) {
                        repeatDestination
                    }

                    AppSectionDivider()

                    AppOptionalEndDatePickerRow(
                        title: endDateTitle,
                        emptyTitle: endDateEmptyTitle,
                        date: $endDate,
                        range: endDateRange,
                        fallbackDate: startDate,
                        isEnabled: isEndDateEnabled,
                        onTap: endDateTap,
                        onOptionsPresentationChange: setEndDateOptionsPresentationActive,
                        isPickerPresentationBlocked: isEndDateOptionsTransitionBlockingPickers
                    )
                }
            }
        }
        .onDisappear {
            endDateOptionsTransitionReleaseTask?.cancel()
            isEndDateOptionsTransitionBlockingPickers = false
        }
    }

    private func setEndDateOptionsPresentationActive(_ isActive: Bool) {
        endDateOptionsTransitionReleaseTask?.cancel()

        if isActive {
            isEndDateOptionsTransitionBlockingPickers = true
        } else {
            endDateOptionsTransitionReleaseTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                isEndDateOptionsTransitionBlockingPickers = false
            }
        }
    }
}

struct AppEditScheduleSection<RepeatDestination: View>: View {
    @Binding var reminderEnabled: Bool
    @Binding var reminderDate: Date
    let repeatSummary: String
    @Binding var effectiveFrom: Date
    let effectiveFromRange: ClosedRange<Date>
    let isEffectiveFromEnabled: Bool
    @Binding var endDate: Date?
    let endDateRange: PartialRangeFrom<Date>
    let endDateFallback: Date
    let isEndDateEnabled: Bool
    let endDateTitle: String
    let endDateEmptyTitle: String
    let reminderTimeTap: (() -> Void)?
    let repeatTap: (() -> Void)?
    let effectiveFromTap: (() -> Void)?
    let endDateTap: (() -> Void)?
    @ViewBuilder let repeatDestination: RepeatDestination
    @State private var isEndDateOptionsTransitionBlockingPickers = false
    @State private var endDateOptionsTransitionReleaseTask: Task<Void, Never>?

    init(
        reminderEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        repeatSummary: String,
        effectiveFrom: Binding<Date>,
        effectiveFromRange: ClosedRange<Date>,
        isEffectiveFromEnabled: Bool,
        endDate: Binding<Date?>,
        endDateRange: PartialRangeFrom<Date>,
        endDateFallback: Date,
        isEndDateEnabled: Bool = true,
        endDateTitle: String = "End Date",
        endDateEmptyTitle: String = "Never",
        reminderTimeTap: (() -> Void)? = nil,
        repeatTap: (() -> Void)? = nil,
        effectiveFromTap: (() -> Void)? = nil,
        endDateTap: (() -> Void)? = nil,
        @ViewBuilder repeatDestination: () -> RepeatDestination
    ) {
        _reminderEnabled = reminderEnabled
        _reminderDate = reminderDate
        self.repeatSummary = repeatSummary
        _effectiveFrom = effectiveFrom
        self.effectiveFromRange = effectiveFromRange
        self.isEffectiveFromEnabled = isEffectiveFromEnabled
        _endDate = endDate
        self.endDateRange = endDateRange
        self.endDateFallback = endDateFallback
        self.isEndDateEnabled = isEndDateEnabled
        self.endDateTitle = endDateTitle
        self.endDateEmptyTitle = endDateEmptyTitle
        self.reminderTimeTap = reminderTimeTap
        self.repeatTap = repeatTap
        self.effectiveFromTap = effectiveFromTap
        self.endDateTap = endDateTap
        self.repeatDestination = repeatDestination()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFormSectionHeader(title: "Schedule")

            AppCard {
                VStack(alignment: .leading, spacing: 0) {
                    AppReminderTimeRows(
                        isEnabled: $reminderEnabled,
                        reminderDate: $reminderDate,
                        onTimeTap: reminderTimeTap,
                        isPickerPresentationBlocked: isEndDateOptionsTransitionBlockingPickers
                    )

                    AppSectionDivider()

                    AppCreateRepeatPickerRow(
                        value: repeatSummary,
                        onTap: repeatTap
                    ) {
                        repeatDestination
                    }

                    AppSectionDivider()

                    AppEffectiveFromPickerRow(
                        date: $effectiveFrom,
                        range: effectiveFromRange,
                        isEnabled: isEffectiveFromEnabled,
                        onTap: effectiveFromTap,
                        isPickerPresentationBlocked: isEndDateOptionsTransitionBlockingPickers
                    )

                    AppSectionDivider()

                    AppOptionalEndDatePickerRow(
                        title: endDateTitle,
                        emptyTitle: endDateEmptyTitle,
                        date: $endDate,
                        range: endDateRange,
                        fallbackDate: endDateFallback,
                        isEnabled: isEndDateEnabled,
                        onTap: endDateTap,
                        onOptionsPresentationChange: setEndDateOptionsPresentationActive,
                        isPickerPresentationBlocked: isEndDateOptionsTransitionBlockingPickers
                    )
                }
            }
        }
        .onDisappear {
            endDateOptionsTransitionReleaseTask?.cancel()
            isEndDateOptionsTransitionBlockingPickers = false
        }
    }

    private func setEndDateOptionsPresentationActive(_ isActive: Bool) {
        endDateOptionsTransitionReleaseTask?.cancel()

        if isActive {
            isEndDateOptionsTransitionBlockingPickers = true
        } else {
            endDateOptionsTransitionReleaseTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                isEndDateOptionsTransitionBlockingPickers = false
            }
        }
    }
}

struct AppNotificationSettingsSection<PopoverContent: View>: View {
    let scheduleSummary: String
    let scheduleTap: (() -> Void)?
    @Binding var reminderEnabled: Bool
    @Binding var reminderDate: Date
    let reminderTimeTap: (() -> Void)?
    let effectiveFromRow: AnyView?
    @ViewBuilder let schedulePopoverContent: PopoverContent

    init(
        scheduleSummary: String,
        scheduleTap: (() -> Void)? = nil,
        reminderEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        reminderTimeTap: (() -> Void)? = nil,
        effectiveFromRow: AnyView? = nil,
        @ViewBuilder schedulePopoverContent: () -> PopoverContent
    ) {
        self.scheduleSummary = scheduleSummary
        self.scheduleTap = scheduleTap
        _reminderEnabled = reminderEnabled
        _reminderDate = reminderDate
        self.reminderTimeTap = reminderTimeTap
        self.effectiveFromRow = effectiveFromRow
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

                    if let effectiveFromRow {
                        effectiveFromRow

                        AppSectionDivider()
                    }

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

private enum AppCreateRepeatFrequency: CaseIterable, Identifiable {
    case never
    case daily
    case weekdays
    case weekends
    case weekly

    var id: Self { self }

    var title: String {
        switch self {
        case .never:
            return "Never"
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekends:
            return "Weekends"
        case .weekly:
            return "Weekly"
        }
    }

}

private enum AppCreateRepeatMode: Equatable {
    case frequency(AppCreateRepeatFrequency)
    case customDays
    case customInterval
}

struct AppCreateRepeatEditorScreen: View {
    let backgroundStyle: AppBackgroundStyle
    let initialScheduleRule: ScheduleRule
    let startDate: Date
    let allowsNeverRepeat: Bool
    let onTap: (() -> Void)?
    let onSave: (ScheduleRule) -> Void
    @State private var mode: AppCreateRepeatMode
    @State private var customDays: WeekdaySet
    @State private var intervalDays: Int
    @State private var lastAppliedRule: ScheduleRule

    init(
        backgroundStyle: AppBackgroundStyle,
        scheduleRule: ScheduleRule,
        startDate: Date,
        allowsNeverRepeat: Bool = false,
        onTap: (() -> Void)? = nil,
        onSave: @escaping (ScheduleRule) -> Void
    ) {
        self.backgroundStyle = backgroundStyle
        initialScheduleRule = scheduleRule
        self.startDate = startDate
        self.allowsNeverRepeat = allowsNeverRepeat
        self.onTap = onTap
        self.onSave = onSave

        let initialRule = scheduleRule
        _mode = State(initialValue: Self.initialMode(for: initialRule, allowsNeverRepeat: allowsNeverRepeat))
        _customDays = State(initialValue: Self.initialCustomDays(for: initialRule, startDate: startDate))
        _intervalDays = State(initialValue: initialRule.customIntervalDays ?? ScheduleRule.defaultIntervalDays)
        _lastAppliedRule = State(initialValue: initialRule)
    }

    var body: some View {
        AppScreen(backgroundStyle: backgroundStyle, topPadding: 8) {
            VStack(alignment: .leading, spacing: 20) {
                frequencySection
                customDaysSection
                customIntervalSection
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var frequencySection: some View {
        AppFormCardSection(title: "Frequency") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(availableFrequencies.enumerated()), id: \.element.id) { index, frequency in
                    AppCreateRepeatOptionRow(
                        title: frequency.title,
                        isSelected: mode == .frequency(frequency),
                        isEnabled: true
                    ) {
                        selectFrequency(frequency)
                    }

                    if index < availableFrequencies.count - 1 {
                        AppSectionDivider()
                    }
                }
            }
        }
    }

    private var availableFrequencies: [AppCreateRepeatFrequency] {
        AppCreateRepeatFrequency.allCases.filter {
            allowsNeverRepeat || $0 != .never
        }
    }

    private var customDaysSection: some View {
        AppFormCardSection(title: "Custom Days") {
            AppCreateRepeatDaysSelector(
                selection: $customDays,
                isActive: mode == .customDays
            ) { updatedDays in
                mode = .customDays
                customDays = updatedDays
                applyRuleIfNeeded(.weekly(updatedDays))
            }
        }
    }

    private var customIntervalSection: some View {
        AppFormCardSection(title: "Custom Interval") {
            HStack(spacing: 16) {
                Text("Every \(intervalDays) days")
                    .foregroundStyle(.primary)

                Spacer()

                if mode == .customInterval {
                    Image(systemName: "checkmark")
                        .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                        .appAccentForeground()
                }

                Stepper("", value: intervalDaysBinding, in: ScheduleRule.intervalDaysRange)
                    .labelsHidden()
                    .disabled(mode != .customInterval)
                    .opacity(mode == .customInterval ? 1 : 0.45)
            }
            .padding(.horizontal, AppLayout.rowHorizontalPadding)
            .padding(.vertical, AppLayout.rowVerticalPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                selectCustomInterval()
            }
        }
    }

    private var intervalDaysBinding: Binding<Int> {
        Binding(
            get: { intervalDays },
            set: { newValue in
                intervalDays = newValue
                mode = .customInterval
                applyRuleIfNeeded(.intervalDays(newValue))
            }
        )
    }

    private func selectFrequency(_ frequency: AppCreateRepeatFrequency) {
        mode = .frequency(frequency)
        let rule: ScheduleRule

        switch frequency {
        case .never:
            customDays = Calendar.current.weekdaySet(for: startDate)
            rule = allowsNeverRepeat ? .oneTime : initialScheduleRule
        case .daily:
            customDays = .daily
            rule = .weekly(.daily)
        case .weekdays:
            customDays = .weekdays
            rule = .weekly(.weekdays)
        case .weekends:
            customDays = .weekends
            rule = .weekly(.weekends)
        case .weekly:
            let startWeekday = Calendar.current.weekdaySet(for: startDate)
            customDays = startWeekday
            rule = .weekly(startWeekday)
        }

        applyRuleIfNeeded(rule)
    }

    private func selectCustomInterval() {
        mode = .customInterval
        applyRuleIfNeeded(.intervalDays(intervalDays))
    }

    private func applyRuleIfNeeded(_ rule: ScheduleRule) {
        guard rule.isValidSelection, lastAppliedRule != rule else { return }
        lastAppliedRule = rule

        onTap?()
        onSave(rule)
    }

    private static func initialMode(for rule: ScheduleRule, allowsNeverRepeat: Bool) -> AppCreateRepeatMode {
        switch rule {
        case let .weekly(days):
            if days == .daily {
                return .frequency(.daily)
            }
            if days == .weekdays {
                return .frequency(.weekdays)
            }
            if days == .weekends {
                return .frequency(.weekends)
            }
            if days.rawValue.nonzeroBitCount == 1 {
                return .frequency(.weekly)
            }
            return .customDays
        case .intervalDays:
            return .customInterval
        case .oneTime:
            return allowsNeverRepeat ? .frequency(.never) : .frequency(.daily)
        }
    }

    private static func initialCustomDays(for rule: ScheduleRule, startDate: Date) -> WeekdaySet {
        if let weeklyDays = rule.weeklyDays, weeklyDays.rawValue != 0 {
            return weeklyDays
        }
        return Calendar.current.weekdaySet(for: startDate)
    }
}

private struct AppCreateRepeatOptionRow: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(isEnabled ? .primary : .tertiary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                    .appAccentForeground()
            }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            action()
        }
    }
}

private struct AppCreateRepeatDaysSelector: View {
    @Binding var selection: WeekdaySet
    let isActive: Bool
    let onSelectionChange: (WeekdaySet) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(WeekdayDisplay.fullNames.enumerated()), id: \.element.label) { index, day in
                HStack(spacing: 16) {
                    Text(day.label)
                        .foregroundStyle(.primary)

                    Spacer()

                    if isActive && selection.contains(day.value) {
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

                if index < WeekdayDisplay.fullNames.count - 1 {
                    AppSectionDivider()
                }
            }
        }
    }

    private func toggle(_ weekday: WeekdaySet) {
        var updatedSelection = isActive ? selection : []

        if updatedSelection.contains(weekday) {
            guard updatedSelection.rawValue.nonzeroBitCount > 1 else { return }
            updatedSelection.remove(weekday)
        } else {
            updatedSelection.insert(weekday)
        }

        onSelectionChange(updatedSelection)
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
    @Binding var scheduleRule: ScheduleRule
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    init(
        backgroundStyle: AppBackgroundStyle,
        scheduleRule: Binding<ScheduleRule>,
        onTap: (() -> Void)? = nil,
        useScheduleForHistory: Binding<Bool>? = nil,
        helperText: String? = nil
    ) {
        self.backgroundStyle = backgroundStyle
        _scheduleRule = scheduleRule
        self.onTap = onTap
        self.useScheduleForHistory = useScheduleForHistory
        self.helperText = helperText
    }

    var body: some View {
        AppScreen(backgroundStyle: backgroundStyle, topPadding: 8) {
            VStack(alignment: .leading, spacing: 8) {
                AppScheduleEditorSectionContent(
                    scheduleRule: $scheduleRule,
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
    @Binding var scheduleRule: ScheduleRule
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    init(
        scheduleRule: Binding<ScheduleRule>,
        onTap: (() -> Void)? = nil,
        useScheduleForHistory: Binding<Bool>? = nil,
        helperText: String? = nil
    ) {
        _scheduleRule = scheduleRule
        self.onTap = onTap
        self.useScheduleForHistory = useScheduleForHistory
        self.helperText = helperText
    }

    var body: some View {
        AppScheduleEditorPopoverBody(
            scheduleRule: $scheduleRule,
            onTap: onTap,
            useScheduleForHistory: useScheduleForHistory,
            helperText: helperText
        )
    }
}

private struct AppScheduleEditorSectionContent: View {
    @Binding var scheduleRule: ScheduleRule
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppCard {
                AppScheduleEditorListContent(
                    scheduleRule: $scheduleRule,
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
    @Binding var scheduleRule: ScheduleRule
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    let helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppScheduleEditorListContent(
                scheduleRule: $scheduleRule,
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
        .padding(.vertical, 8)
    }
}

private struct AppScheduleEditorListContent: View {
    @Binding var scheduleRule: ScheduleRule
    let onTap: (() -> Void)?
    let useScheduleForHistory: Binding<Bool>?
    @State private var rememberedCustomIntervalDays = ScheduleRule.defaultIntervalDays

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InlineDaysSelector(selection: weeklyDaysBinding)
                .appTapAction(onTap)

            intervalSelectionRow
                .appTapAction(onTap)

            intervalStepperRow
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

        }
    }

    private var intervalSelectionRow: some View {
        HStack {
            Text("Intervals")
                .foregroundStyle(.primary)

            Spacer()

            if isIntervalSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                    .appAccentForeground()
            }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.schedulePopoverRowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            selectIntervals()
        }
    }

    private var intervalStepperRow: some View {
        HStack(spacing: 16) {
            Spacer()

            Text("Every \(currentCustomIntervalDays) days")
                .foregroundStyle(.secondary)

            Stepper("", value: customIntervalDaysBinding, in: ScheduleRule.intervalDaysRange)
                .labelsHidden()
        }
        .disabled(!isIntervalSelected)
        .opacity(isIntervalSelected ? 1 : 0.45)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.scheduleStepperRowVerticalPadding)
    }

    private var weeklyDaysBinding: Binding<WeekdaySet> {
        Binding(
            get: { scheduleRule.weeklyDays ?? [] },
            set: {
                scheduleRule = .weekly($0)
            }
        )
    }

    private var isIntervalSelected: Bool {
        if case .intervalDays = scheduleRule {
            return true
        }
        return false
    }

    private var currentCustomIntervalDays: Int {
        scheduleRule.customIntervalDays ?? rememberedCustomIntervalDays
    }

    private var customIntervalDaysBinding: Binding<Int> {
        Binding(
            get: { currentCustomIntervalDays },
            set: { newValue in
                rememberedCustomIntervalDays = newValue
                scheduleRule = .intervalDays(newValue)
            }
        )
    }

    private func selectIntervals() {
        guard !isIntervalSelected else { return }
        scheduleRule = .intervalDays(rememberedCustomIntervalDays)
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

struct AppFloatingInfoBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBlue))

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
                        .fill(Color(uiColor: .systemBlue).opacity(0.16))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .systemBlue).opacity(0.28), lineWidth: 1)
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

enum FutureStartLabel {
    static func text(for startDate: Date) -> String {
        "Starts \(startDate.formatted(.dateTime.month(.abbreviated).day()))"
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
    let scheduleRule: ScheduleRule
    let backgroundStyle: AppBackgroundStyle

    var body: some View {
        AppScreen(backgroundStyle: backgroundStyle, topPadding: 8) {
            AppReadOnlyScheduleCard(scheduleRule: scheduleRule)
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .appTintedBackButton()
    }
}

struct AppReadOnlySchedulePopoverContent: View {
    let scheduleRule: ScheduleRule

    init(scheduleRule: ScheduleRule) {
        self.scheduleRule = scheduleRule
    }

    init(scheduleDays: WeekdaySet) {
        self.scheduleRule = .weekly(scheduleDays)
    }

    var body: some View {
        AppReadOnlyScheduleList(scheduleRule: scheduleRule)
            .frame(width: 280)
            .padding(.vertical, 8)
            .presentationCompactAdaptation(.popover)
    }
}

private struct AppReadOnlyScheduleCard: View {
    let scheduleRule: ScheduleRule

    var body: some View {
        AppCard {
            AppReadOnlyScheduleList(scheduleRule: scheduleRule)
        }
    }
}

private struct AppReadOnlyScheduleList: View {
    let scheduleRule: ScheduleRule

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch scheduleRule {
            case let .weekly(scheduleDays):
                ForEach(WeekdayDisplay.fullNames, id: \.label) { day in
                    AppReadOnlyScheduleRow(
                        title: day.label,
                        isSelected: scheduleDays.contains(day.value)
                    )
                }
            case .intervalDays:
                AppReadOnlyScheduleRow(
                    title: scheduleRule.summary,
                    isSelected: true
                )
            case .oneTime:
                AppReadOnlyScheduleRow(
                    title: scheduleRule.summary,
                    isSelected: true
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
