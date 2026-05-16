import Testing
import UIKit

@testable import LoonyBear

@MainActor
@Suite(.serialized)
struct HomeQuickActionTests {
    @Test
    func createBackupShortcutMapsToCreateBackupAction() {
        let shortcutItem = UIApplicationShortcutItem(
            type: HomeQuickActions.createBackupType,
            localizedTitle: "Create Backup"
        )

        #expect(HomeQuickActions.action(for: shortcutItem) == .createBackup)
    }

    @Test
    func unknownShortcutIsIgnored() {
        let shortcutItem = UIApplicationShortcutItem(
            type: "unknown",
            localizedTitle: "Unknown"
        )

        #expect(HomeQuickActions.action(for: shortcutItem) == nil)
    }

    @Test
    func createBackupShortcutRouteOnlyOpensBackupSettings() {
        let route = HomeQuickActionRouter.route(for: .createBackup)

        #expect(route == HomeQuickActionRoute(selectedTab: .settings, settingsPath: [.backup]))
    }

    @Test
    func nilShortcutActionHasNoRoute() {
        #expect(HomeQuickActionRouter.route(for: nil) == nil)
    }

    @Test
    func handleCreateBackupShortcutPublishesNavigationIntent() {
        HomeQuickActionCenter.shared.consume(.createBackup)
        let shortcutItem = UIApplicationShortcutItem(
            type: HomeQuickActions.createBackupType,
            localizedTitle: "Create Backup"
        )

        #expect(HomeQuickActions.handle(shortcutItem))

        #expect(HomeQuickActionCenter.shared.pendingAction == .createBackup)
        HomeQuickActionCenter.shared.consume(.createBackup)
    }

    @Test
    func consumeCreateBackupShortcutClearsNavigationIntent() {
        HomeQuickActionCenter.shared.request(.createBackup)

        HomeQuickActionCenter.shared.consume(.createBackup)

        #expect(HomeQuickActionCenter.shared.pendingAction == nil)
    }
}
