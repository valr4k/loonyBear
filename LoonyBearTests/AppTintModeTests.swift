import Foundation
import SwiftUI
import Testing
import UIKit

@testable import LoonyBear

@MainActor
struct AppTintModeTests {
    private static let tabs: [AppTab] = [.myPills, .myHabits, .events, .settings]

    @Test(arguments: AppTint.allCases)
    func singleModeKeepsTheSelectedColorInEverySection(_ tint: AppTint) {
        for tab in Self.tabs {
            #expect(AppTintMode.single.tint(for: tab, singleTint: tint) == tint)
        }
    }

    @Test(arguments: AppTint.allCases)
    func sectionModeAlwaysUsesTheExistingPalette(_ savedTint: AppTint) {
        let mode = AppTintMode.bySection
        #expect(mode.tint(for: .myPills, singleTint: savedTint) == .amber)
        #expect(mode.tint(for: .myHabits, singleTint: savedTint) == .green)
        #expect(mode.tint(for: .events, singleTint: savedTint) == .indigo)
        #expect(mode.tint(for: .settings, singleTint: savedTint) == .blue)
    }

    @Test
    func missingOrUnknownModeFallsBackToSingleColor() {
        #expect(AppTintMode.stored(rawValue: "") == .single)
        #expect(AppTintMode.stored(rawValue: "unknown") == .single)
        #expect(AppTintMode.stored(rawValue: "bySection") == .bySection)
    }

    @Test
    func legacyBackupSettingsDecodeWithoutTintMode() throws {
        let json = Data(#"{"appearanceMode":"dark","appTint":"green"}"#.utf8)
        let settings = try JSONDecoder().decode(BackupAppSettings.self, from: json)
        #expect(settings.appTintMode == nil)
        #expect(settings.appTint == "green")
    }

    @Test(arguments: AppTintMode.allCases)
    func backupSettingsRoundTripPreservesModeAndSingleColor(_ mode: AppTintMode) throws {
        let settings = BackupAppSettings(appearanceMode: "dark", appTint: "amber", appTintMode: mode.rawValue)
        let decoded = try JSONDecoder().decode(BackupAppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test
    func titleControllersStyleOnlyTheirOwnNavigationStack() {
        let pills = AppNavigationTitleTintController.Controller()
        let habits = AppNavigationTitleTintController.Controller()
        let pillNavigation = UINavigationController(rootViewController: pills)
        let habitNavigation = UINavigationController(rootViewController: habits)
        pills.updateTint(.amber)
        habits.updateTint(.green)

        #expect(titleColor(pillNavigation) == AppTint.amber.accentUIColor)
        #expect(titleColor(habitNavigation) == AppTint.green.accentUIColor)

        pills.updateTint(.indigo)
        #expect(titleColor(pillNavigation) == AppTint.indigo.accentUIColor)
        #expect(titleColor(habitNavigation) == AppTint.green.accentUIColor)
    }

    @Test
    func titleControllerAppliesTintAfterItJoinsNavigationStack() {
        let controller = AppNavigationTitleTintController.Controller()
        controller.updateTint(.green)
        let navigation = UINavigationController(rootViewController: controller)
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        #expect(titleColor(navigation) == AppTint.green.accentUIColor)
    }

    private func titleColor(_ navigation: UINavigationController) -> UIColor? {
        navigation.navigationBar.titleTextAttributes?[.foregroundColor] as? UIColor
    }
}
