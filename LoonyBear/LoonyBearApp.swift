import CoreData
import SwiftUI
import UIKit

@main
struct LoonyBearApp: App {
    private let bootstrapState = AppEnvironment.live()
    @AppStorage("appearance_mode") private var appearanceModeRawValue = AppearanceMode.system.rawValue

    init() {
        configureTabBarAppearance()
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
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceModeRawValue) ?? .system {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()

        let selectedColor = UIColor.systemBlue
        let normalColor = UIColor.label
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
        UITabBar.appearance().unselectedItemTintColor = normalColor
    }
}
