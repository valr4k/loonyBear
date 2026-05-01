import Combine
import UIKit

enum HomeQuickAction: Equatable, Sendable {
    case createBackup
}

final class HomeQuickActionCenter: ObservableObject {
    static let shared = HomeQuickActionCenter()

    @Published private(set) var pendingAction: HomeQuickAction?

    private init() {}

    @MainActor
    func request(_ action: HomeQuickAction) {
        pendingAction = action
    }

    @MainActor
    func consume(_ action: HomeQuickAction) {
        guard pendingAction == action else { return }
        pendingAction = nil
    }
}

enum HomeQuickActions {
    static let createBackupType = "com.valr4k.LoonyBear.quickAction.createBackup"

    static func configure(application: UIApplication = .shared) {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: createBackupType,
                localizedTitle: "Create Backup",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "arrow.clockwise"),
                userInfo: nil
            )
        ]
    }

    static func action(for shortcutItem: UIApplicationShortcutItem) -> HomeQuickAction? {
        switch shortcutItem.type {
        case createBackupType:
            return .createBackup
        default:
            return nil
        }
    }

    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = action(for: shortcutItem) else { return false }

        Task { @MainActor in
            HomeQuickActionCenter.shared.request(action)
        }

        return true
    }
}

final class LoonyBearAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HomeQuickActions.configure(application: application)
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        HomeQuickActions.configure(application: application)
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(HomeQuickActions.handle(shortcutItem))
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            HomeQuickActions.handle(shortcutItem)
        }

        let configuration = UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = LoonyBearSceneDelegate.self
        return configuration
    }
}

final class LoonyBearSceneDelegate: NSObject, UIWindowSceneDelegate {
    func sceneDidBecomeActive(_ scene: UIScene) {
        HomeQuickActions.configure()
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(HomeQuickActions.handle(shortcutItem))
    }
}
