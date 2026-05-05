import Combine
import SwiftUI
import UIKit

enum AppLayout {
    static let screenSpacing: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 18
    static let repeatRowVerticalPadding: CGFloat = 12
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

struct AppNeutralCapsuleActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background {
                Capsule()
                    .fill(Color(uiColor: .systemFill))
            }
            .opacity(configuration.isPressed && isEnabled ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    static let chooseAtLeastOneDay = "Select at least one day."
    static let notificationsRequired = "Turn on notifications in Settings to use reminders."
    static let endDateRemovedForNeverRepeat = "End date removed. Repeat is set to Never."
    static let noScheduledDayBeforeEndDate = "End date must be on or after the first scheduled day."
    static let backupFolderHint = "Backups stay in the selected Files folder even if the app is deleted. After reinstalling, choose the same folder again before restoring."
    static let pillHistoryFollowsSchedule = "History follows schedule from start date."
    static let pillHistoryCountsEveryDay = "History counts every day from the start date."
    static let habitHistoryFollowsSchedule = "History follows schedule from start date."
    static let habitHistoryCountsEveryDay = "History counts every day from the start date."
    static let pillDescriptionPlaceholder = "(optional)"

    static func overdueScheduledDayEditMessage(actionLabel: String) -> String {
        "Mark each overdue day as \(actionLabel) or Skipped."
    }

    static func overdueScheduledDayDetailsMessage(actionLabel _: String) -> String {
        "Finish updating overdue days."
    }

    static func missingScheduledDaysDetailsMessage(actionLabel _: String) -> String {
        "Finish updating past days."
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

    func appTouchDownAction(_ action: @escaping () -> Void) -> some View {
        modifier(AppTouchDownActionModifier(action: action))
    }
}

private struct AppTouchDownActionModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.background(
            AppTouchDownActionInstaller(action: action)
                .allowsHitTesting(false)
        )
    }
}

private struct AppTouchDownActionInstaller: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {
        context.coordinator.action = action
        uiView.coordinator = context.coordinator
        uiView.scheduleInstallation()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    final class MarkerView: UIView {
        weak var coordinator: Coordinator?
        private weak var installedWindow: UIWindow?
        private var recognizer: TouchDownRecognizer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        deinit {
            uninstallRecognizer()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            scheduleInstallation()
        }

        func scheduleInstallation() {
            DispatchQueue.main.async { [weak self] in
                self?.installRecognizerIfNeeded()
            }
        }

        private func installRecognizerIfNeeded() {
            guard let window else {
                uninstallRecognizer()
                return
            }

            if installedWindow === window {
                return
            }

            uninstallRecognizer()

            let recognizer = TouchDownRecognizer(markerView: self) { [weak self] in
                self?.coordinator?.action()
            }
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = coordinator
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            installedWindow = window
        }

        private func uninstallRecognizer() {
            if let recognizer, let installedWindow {
                installedWindow.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }
    }

    final class TouchDownRecognizer: UIGestureRecognizer {
        private weak var markerView: MarkerView?
        private let onTouchDown: () -> Void
        private var didFire = false

        init(markerView: MarkerView, onTouchDown: @escaping () -> Void) {
            self.markerView = markerView
            self.onTouchDown = onTouchDown
            super.init(target: nil, action: nil)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard !didFire else { return }
            guard let markerView, let window = markerView.window else {
                state = .failed
                return
            }
            guard touches.contains(where: { touch in
                let touchLocation = touch.location(in: window)
                let markerFrame = markerView.convert(markerView.bounds, to: window)
                return markerFrame.insetBy(dx: -8, dy: -8).contains(touchLocation)
            }) else {
                state = .failed
                return
            }
            didFire = true
            onTouchDown()
            state = .failed
        }

        override func reset() {
            didFire = false
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

private extension View {
    func appExclusiveTouchScope() -> some View {
        background(AppExclusiveTouchScopeConfigurator().allowsHitTesting(false))
    }
}

private struct AppExclusiveTouchScopeConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> MarkerView {
        MarkerView()
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {
        uiView.scheduleConfiguration()
    }

    final class MarkerView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            isMultipleTouchEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleConfiguration()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleConfiguration()
        }

        func scheduleConfiguration() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.configureScope()
            }
        }

        private func configureScope() {
            guard let scopeRoot = Self.scopeRoot(from: self) else { return }
            Self.applyExclusiveTouch(in: scopeRoot)
        }

        private static func scopeRoot(from marker: UIView) -> UIView? {
            let markerSize = marker.bounds.size
            var candidate = marker.superview
            var firstControlAncestor: UIView?

            while let view = candidate, view !== marker.window {
                if containsControl(in: view, excluding: marker) {
                    if firstControlAncestor == nil {
                        firstControlAncestor = view
                    }

                    if size(view.bounds.size, roughlyMatches: markerSize) {
                        return view
                    }
                }

                candidate = view.superview
            }

            return firstControlAncestor
        }

        private static func size(_ lhs: CGSize, roughlyMatches rhs: CGSize) -> Bool {
            guard rhs.width > 0, rhs.height > 0 else { return false }
            return abs(lhs.width - rhs.width) < 24 && abs(lhs.height - rhs.height) < 24
        }

        private static func containsControl(in view: UIView, excluding marker: UIView) -> Bool {
            for subview in view.subviews where subview !== marker {
                if subview is UIControl || containsControl(in: subview, excluding: marker) {
                    return true
                }
            }
            return false
        }

        private static func applyExclusiveTouch(in view: UIView) {
            view.isMultipleTouchEnabled = false
            view.isExclusiveTouch = view.isUserInteractionEnabled

            for subview in view.subviews {
                applyExclusiveTouch(in: subview)
            }
        }
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

struct AppReminderTimeRows: View {
    @Binding var isEnabled: Bool
    @Binding var reminderDate: Date
    let onTimeTap: (() -> Void)?
    let onPickerTouchDown: (() -> Void)?
    let isPickerPresentationBlocked: Bool

    init(
        isEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        onTimeTap: (() -> Void)? = nil,
        onPickerTouchDown: (() -> Void)? = nil,
        isPickerPresentationBlocked: Bool = false
    ) {
        _isEnabled = isEnabled
        _reminderDate = reminderDate
        self.onTimeTap = onTimeTap
        self.onPickerTouchDown = onPickerTouchDown
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
                .appTouchDownAction {
                    onPickerTouchDown?()
                }
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

struct AppOptionalEndDatePickerRow: View {
    let title: String
    let emptyTitle: String
    @Binding var date: Date?
    let range: PartialRangeFrom<Date>
    let fallbackDate: Date
    let isEnabled: Bool
    let onTap: (() -> Void)?
    let dismissOptionsSignal: Int
    let onOptionsPresentationChange: (Bool) -> Void
    let onOptionsTouchDown: (() -> Void)?
    let isOptionsPresentationBlocked: Bool
    let isPickerPresentationBlocked: Bool
    @State private var isShowingEndDateOptions = false

    init(
        title: String = "End Repeat",
        emptyTitle: String = "Never",
        date: Binding<Date?>,
        range: PartialRangeFrom<Date>,
        fallbackDate: Date,
        isEnabled: Bool = true,
        onTap: (() -> Void)? = nil,
        dismissOptionsSignal: Int = 0,
        onOptionsPresentationChange: @escaping (Bool) -> Void = { _ in },
        onOptionsTouchDown: (() -> Void)? = nil,
        isOptionsPresentationBlocked: Bool = false,
        isPickerPresentationBlocked: Bool = false
    ) {
        self.title = title
        self.emptyTitle = emptyTitle
        _date = date
        self.range = range
        self.fallbackDate = fallbackDate
        self.isEnabled = isEnabled
        self.onTap = onTap
        self.dismissOptionsSignal = dismissOptionsSignal
        self.onOptionsPresentationChange = onOptionsPresentationChange
        self.onOptionsTouchDown = onOptionsTouchDown
        self.isOptionsPresentationBlocked = isOptionsPresentationBlocked
        self.isPickerPresentationBlocked = isPickerPresentationBlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    guard isEnabled, !isOptionsPresentationBlocked else { return }
                    AppDescriptionFieldSupport.dismissKeyboard()
                    onTap?()
                    guard !isShowingEndDateOptions else {
                        setEndDateOptionsPresented(false)
                        return
                    }
                    onOptionsTouchDown?()
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
                .appTouchDownAction {
                    guard isEnabled, !isOptionsPresentationBlocked, !isShowingEndDateOptions else { return }
                    onOptionsTouchDown?()
                }
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
                    Text("End Date")
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
        .onChange(of: dismissOptionsSignal) { _, _ in
            setEndDateOptionsPresented(false)
        }
        .onDisappear {
            setEndDateOptionsPresented(false)
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

@MainActor
private final class AppSchedulePresentationGuard: ObservableObject {
    @Published private(set) var isPickerPresentationBlocked = false
    @Published private(set) var isEndDateOptionsPresentationBlocked = false

    private static let pickerTouchBlockDurationNanoseconds: UInt64 = 200_000_000
    private static let endDateOptionsTouchBlockDurationNanoseconds: UInt64 = 200_000_000
    private var pickerTouchReleaseTask: Task<Void, Never>?
    private var endDateOptionsTouchReleaseTask: Task<Void, Never>?

    deinit {
        pickerTouchReleaseTask?.cancel()
        endDateOptionsTouchReleaseTask?.cancel()
    }

    func setEndDateOptionsPresented(_ isPresented: Bool) {
        endDateOptionsTouchReleaseTask?.cancel()
        endDateOptionsTouchReleaseTask = nil
        isPickerPresentationBlocked = isPresented
    }

    func blockEndDateOptionsForPickerTouch() {
        pickerTouchReleaseTask?.cancel()
        isEndDateOptionsPresentationBlocked = true
        pickerTouchReleaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.pickerTouchBlockDurationNanoseconds)
            guard !Task.isCancelled else { return }
            isEndDateOptionsPresentationBlocked = false
        }
    }

    func blockPickersForEndDateOptionsTouch() {
        endDateOptionsTouchReleaseTask?.cancel()
        isPickerPresentationBlocked = true
        endDateOptionsTouchReleaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.endDateOptionsTouchBlockDurationNanoseconds)
            guard !Task.isCancelled else { return }
            isPickerPresentationBlocked = false
        }
    }

    func reset() {
        pickerTouchReleaseTask?.cancel()
        endDateOptionsTouchReleaseTask?.cancel()
        pickerTouchReleaseTask = nil
        endDateOptionsTouchReleaseTask = nil
        isPickerPresentationBlocked = false
        isEndDateOptionsPresentationBlocked = false
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
    @StateObject private var presentationGuard = AppSchedulePresentationGuard()
    @State private var endDateOptionsDismissSignal = 0

    init(
        startDate: Binding<Date>,
        startDateRange: ClosedRange<Date>? = nil,
        reminderEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        endDate: Binding<Date?>,
        endDateRange: PartialRangeFrom<Date>,
        isEndDateEnabled: Bool = true,
        endDateTitle: String = "End Repeat",
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
                        isPickerPresentationBlocked: presentationGuard.isPickerPresentationBlocked
                    )

                    AppSectionDivider()

                    AppReminderTimeRows(
                        isEnabled: $reminderEnabled,
                        reminderDate: $reminderDate,
                        onTimeTap: reminderTimeTap,
                        onPickerTouchDown: presentationGuard.blockEndDateOptionsForPickerTouch,
                        isPickerPresentationBlocked: presentationGuard.isPickerPresentationBlocked
                    )

                    AppSectionDivider()

                    AppCreateRepeatPickerRow(
                        value: repeatSummary,
                        onTap: {
                            dismissEndDateOptionsForRepeatNavigation()
                            repeatTap?()
                        }
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
                        dismissOptionsSignal: endDateOptionsDismissSignal,
                        onOptionsPresentationChange: presentationGuard.setEndDateOptionsPresented,
                        onOptionsTouchDown: presentationGuard.blockPickersForEndDateOptionsTouch,
                        isOptionsPresentationBlocked: presentationGuard.isEndDateOptionsPresentationBlocked,
                        isPickerPresentationBlocked: presentationGuard.isPickerPresentationBlocked
                    )
                }
            }
            .appExclusiveTouchScope()
        }
        .onDisappear {
            presentationGuard.reset()
        }
    }

    private func dismissEndDateOptionsForRepeatNavigation() {
        endDateOptionsDismissSignal += 1
        presentationGuard.blockEndDateOptionsForPickerTouch()
    }
}

struct AppEditScheduleSection<RepeatDestination: View>: View {
    @Binding var reminderEnabled: Bool
    @Binding var reminderDate: Date
    let repeatSummary: String
    @Binding var endDate: Date?
    let endDateRange: PartialRangeFrom<Date>
    let endDateFallback: Date
    let isEndDateEnabled: Bool
    let endDateTitle: String
    let endDateEmptyTitle: String
    let reminderTimeTap: (() -> Void)?
    let repeatTap: (() -> Void)?
    let endDateTap: (() -> Void)?
    @ViewBuilder let repeatDestination: RepeatDestination
    @StateObject private var presentationGuard = AppSchedulePresentationGuard()
    @State private var endDateOptionsDismissSignal = 0

    init(
        reminderEnabled: Binding<Bool>,
        reminderDate: Binding<Date>,
        repeatSummary: String,
        endDate: Binding<Date?>,
        endDateRange: PartialRangeFrom<Date>,
        endDateFallback: Date,
        isEndDateEnabled: Bool = true,
        endDateTitle: String = "End Repeat",
        endDateEmptyTitle: String = "Never",
        reminderTimeTap: (() -> Void)? = nil,
        repeatTap: (() -> Void)? = nil,
        endDateTap: (() -> Void)? = nil,
        @ViewBuilder repeatDestination: () -> RepeatDestination
    ) {
        _reminderEnabled = reminderEnabled
        _reminderDate = reminderDate
        self.repeatSummary = repeatSummary
        _endDate = endDate
        self.endDateRange = endDateRange
        self.endDateFallback = endDateFallback
        self.isEndDateEnabled = isEndDateEnabled
        self.endDateTitle = endDateTitle
        self.endDateEmptyTitle = endDateEmptyTitle
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
                    AppReminderTimeRows(
                        isEnabled: $reminderEnabled,
                        reminderDate: $reminderDate,
                        onTimeTap: reminderTimeTap,
                        onPickerTouchDown: presentationGuard.blockEndDateOptionsForPickerTouch,
                        isPickerPresentationBlocked: presentationGuard.isPickerPresentationBlocked
                    )

                    AppSectionDivider()

                    AppCreateRepeatPickerRow(
                        value: repeatSummary,
                        onTap: {
                            dismissEndDateOptionsForRepeatNavigation()
                            repeatTap?()
                        }
                    ) {
                        repeatDestination
                    }

                    AppSectionDivider()

                    AppOptionalEndDatePickerRow(
                        title: endDateTitle,
                        emptyTitle: endDateEmptyTitle,
                        date: $endDate,
                        range: endDateRange,
                        fallbackDate: endDateFallback,
                        isEnabled: isEndDateEnabled,
                        onTap: endDateTap,
                        dismissOptionsSignal: endDateOptionsDismissSignal,
                        onOptionsPresentationChange: presentationGuard.setEndDateOptionsPresented,
                        onOptionsTouchDown: presentationGuard.blockPickersForEndDateOptionsTouch,
                        isOptionsPresentationBlocked: presentationGuard.isEndDateOptionsPresentationBlocked,
                        isPickerPresentationBlocked: presentationGuard.isPickerPresentationBlocked
                    )
                }
            }
            .appExclusiveTouchScope()
        }
        .onDisappear {
            presentationGuard.reset()
        }
    }

    private func dismissEndDateOptionsForRepeatNavigation() {
        endDateOptionsDismissSignal += 1
        presentationGuard.blockEndDateOptionsForPickerTouch()
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

private enum AppCreateRepeatMode: Equatable {
    case never
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
                customDaysSection
                customIntervalSection
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
        .appTintedBackButton()
    }

    private var customDaysSection: some View {
        AppFormCardSection(title: "Days") {
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
        AppFormCardSection(title: "Interval") {
            VStack(spacing: 0) {
                customIntervalRow

                if allowsNeverRepeat {
                    AppSectionDivider()

                    AppCreateRepeatOptionRow(
                        title: "Never",
                        isSelected: mode == .never,
                        isEnabled: true
                    ) {
                        selectNever()
                    }
                }
            }
        }
    }

    private var customIntervalRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Every")

                    Text("\(intervalDays)")
                        .monospacedDigit()

                    Text("days")
                }

                Stepper("", value: intervalDaysBinding, in: ScheduleRule.intervalDaysRange)
                    .labelsHidden()
                    .disabled(mode != .customInterval)
            }
            .foregroundStyle(.primary)
            .opacity(mode == .customInterval ? 1 : 0.45)

            Spacer()

            if mode == .customInterval {
                Image(systemName: "checkmark")
                    .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                    .appAccentForeground()
            }
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            selectCustomInterval()
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

    private func selectNever() {
        guard allowsNeverRepeat else { return }
        mode = .never
        applyRuleIfNeeded(.oneTime)
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
        case .weekly:
            return .customDays
        case .intervalDays:
            return .customInterval
        case .oneTime:
            return allowsNeverRepeat ? .never : .customDays
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
                .foregroundStyle(.primary)
                .opacity(rowOpacity)

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

    private var rowOpacity: Double {
        guard isEnabled else { return 0.35 }
        return isSelected ? 1 : 0.45
    }
}

private struct AppCreateRepeatDaysSelector: View {
    @Binding var selection: WeekdaySet
    let isActive: Bool
    let onSelectionChange: (WeekdaySet) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(WeekdayDisplay.fullNames.enumerated()), id: \.element.label) { index, day in
                let isSelected = isActive && selection.contains(day.value)

                HStack(spacing: 16) {
                    Text(day.label)
                        .foregroundStyle(.primary)
                        .opacity(isSelected ? 1 : 0.45)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: AppLayout.listIconSize, weight: .semibold))
                            .appAccentForeground()
                    }
                }
                .padding(.horizontal, AppLayout.rowHorizontalPadding)
                .padding(.vertical, AppLayout.repeatRowVerticalPadding)
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
            .accessibilityLabel("Dismiss")
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
            .accessibilityLabel("Dismiss")
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
        return AppDateLabels.cardDate(normalizedOverdueDay)
    }
}

enum FutureStartLabel {
    static func text(for startDate: Date) -> String {
        "Starts \(AppDateLabels.cardDate(startDate))"
    }
}

enum AppDateLabels {
    static func cardDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
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
