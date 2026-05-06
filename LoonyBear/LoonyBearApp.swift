import CoreData
import SwiftUI
import UIKit

@main
struct LoonyBearApp: App {
    @UIApplicationDelegateAdaptor(LoonyBearAppDelegate.self) private var appDelegate
    private let bootstrapState = AppEnvironment.live()
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

    init() {
        Self.configureTabBarAppearance(for: .blue)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch bootstrapState {
                case .ready(let environment):
                    ContentView(
                        appState: environment.appState,
                        pillAppState: environment.pillAppState,
                        notificationCoordinator: environment.notificationCoordinator,
                        badgeService: environment.badgeService,
                        lifecycleRefreshCoordinator: environment.lifecycleRefreshCoordinator,
                        startupHealthCheckCoordinator: environment.startupHealthCheckCoordinator
                    )
                        .environment(\.managedObjectContext, environment.persistenceController.container.viewContext)
                case .persistenceFailure(let error):
                    PersistenceErrorView(error: error)
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .onAppear {
                configureTabBarAppearance()
            }
            .onChange(of: appTintRawValue) { _, _ in
                configureTabBarAppearance()
            }
            .onChange(of: appearanceModeRawValue) { _, _ in
                configureTabBarAppearance()
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch AppearanceMode.stored(rawValue: appearanceModeRawValue) {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var appTint: AppTint {
        AppTint.stored(rawValue: appTintRawValue)
    }

    private func configureTabBarAppearance() {
        Self.configureTabBarAppearance(for: appTint)
    }

    static func refreshTabBarAppearance(for tint: AppTint) {
        configureTabBarAppearance(for: tint)
    }

    private static func configureTabBarAppearance(for tint: AppTint) {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let selectedColor = tint.accentUIColor
        let normalColor = UIColor.secondaryLabel
        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ]

        itemAppearances.forEach { itemAppearance in
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selectedColor
        UITabBar.appearance().unselectedItemTintColor = normalColor

        updateVisibleTabBars(
            appearance: appearance,
            selectedColor: selectedColor,
            normalColor: normalColor
        )
    }

    private static func updateVisibleTabBars(
        appearance: UITabBarAppearance,
        selectedColor: UIColor,
        normalColor: UIColor
    ) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach {
                updateTabBars(
                    in: $0,
                    appearance: appearance,
                    selectedColor: selectedColor,
                    normalColor: normalColor
                )
            }
    }

    private static func updateTabBars(
        in view: UIView,
        appearance: UITabBarAppearance,
        selectedColor: UIColor,
        normalColor: UIColor
    ) {
        if let tabBar = view as? UITabBar {
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = selectedColor
            tabBar.unselectedItemTintColor = normalColor
            tabBar.tintAdjustmentMode = .normal
        }

        view.subviews.forEach {
            updateTabBars(
                in: $0,
                appearance: appearance,
                selectedColor: selectedColor,
                normalColor: normalColor
            )
        }
    }

}
