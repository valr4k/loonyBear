import Testing
import UIKit

@testable import LoonyBear

@MainActor
struct AppNavigationTitleAppearanceTests {
    @Test(arguments: AppTint.allCases)
    func appliesSelectedTintToEveryBarAppearance(_ tint: AppTint) throws {
        let bar = UINavigationBar()
        bar.compactAppearance = UINavigationBarAppearance()
        bar.scrollEdgeAppearance = UINavigationBarAppearance()
        bar.compactScrollEdgeAppearance = UINavigationBarAppearance()

        AppNavigationTitleAppearance.apply(to: bar, tint: tint)

        #expect((bar.titleTextAttributes?[.foregroundColor] as? UIColor) == tint.accentUIColor)
        #expect((bar.largeTitleTextAttributes?[.foregroundColor] as? UIColor) == tint.accentUIColor)
        let appearances = [
            bar.standardAppearance,
            try #require(bar.compactAppearance),
            try #require(bar.scrollEdgeAppearance),
            try #require(bar.compactScrollEdgeAppearance),
        ]
        for appearance in appearances {
            #expect((appearance.titleTextAttributes[.foregroundColor] as? UIColor) == tint.accentUIColor)
            #expect((appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor) == tint.accentUIColor)
        }
    }

    @Test
    func preservesNativeFallbacksWhenOptionalAppearancesAreAbsent() {
        let bar = UINavigationBar()
        bar.compactAppearance = nil
        bar.scrollEdgeAppearance = nil
        bar.compactScrollEdgeAppearance = nil
        let item = UINavigationItem(title: "Details")
        bar.items = [item]

        AppNavigationTitleAppearance.apply(to: bar, tint: .green)

        #expect(bar.compactAppearance == nil)
        #expect(bar.scrollEdgeAppearance == nil)
        #expect(bar.compactScrollEdgeAppearance == nil)
        #expect(item.standardAppearance == nil)
        #expect(item.compactAppearance == nil)
        #expect(item.scrollEdgeAppearance == nil)
        #expect(item.compactScrollEdgeAppearance == nil)
    }

    @Test
    func preservesFontsBackgroundAndButtonStyling() {
        let bar = UINavigationBar()
        let font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        let largeFont = UIFont.systemFont(ofSize: 32, weight: .bold)
        let appearance = UINavigationBarAppearance()
        appearance.titleTextAttributes = [.font: font, .foregroundColor: UIColor.red]
        appearance.largeTitleTextAttributes = [.font: largeFont]
        appearance.backgroundColor = .systemGray
        appearance.shadowColor = .systemPink
        appearance.titlePositionAdjustment = UIOffset(horizontal: 2, vertical: 1)
        appearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemPurple]
        bar.standardAppearance = appearance
        bar.tintColor = .systemTeal

        AppNavigationTitleAppearance.apply(to: bar, tint: .amber)

        let updated = bar.standardAppearance
        #expect((updated.titleTextAttributes[.font] as? UIFont) == font)
        #expect((updated.largeTitleTextAttributes[.font] as? UIFont) == largeFont)
        #expect(updated.backgroundColor == .systemGray)
        #expect(updated.shadowColor == .systemPink)
        #expect(updated.titlePositionAdjustment == appearance.titlePositionAdjustment)
        #expect((updated.buttonAppearance.normal.titleTextAttributes[.foregroundColor] as? UIColor) == .systemPurple)
        #expect(bar.tintColor == .systemTeal)
        #expect((appearance.titleTextAttributes[.foregroundColor] as? UIColor) == .red)
    }

    @Test
    func updatesExistingBarsAndPerScreenOverridesAfterTintChanges() throws {
        let bar = UINavigationBar()
        let item = UINavigationItem(title: "Backup")
        let override = UINavigationBarAppearance()
        override.backgroundColor = .systemGray
        item.standardAppearance = override
        item.compactAppearance = override
        item.scrollEdgeAppearance = override
        item.compactScrollEdgeAppearance = override
        bar.items = [item]
        AppNavigationTitleAppearance.apply(to: bar, tint: .blue)
        AppNavigationTitleAppearance.apply(to: bar, tint: .indigo)

        #expect((bar.titleTextAttributes?[.foregroundColor] as? UIColor) == AppTint.indigo.accentUIColor)
        for appearance in [
            try #require(item.standardAppearance),
            try #require(item.compactAppearance),
            try #require(item.scrollEdgeAppearance),
            try #require(item.compactScrollEdgeAppearance),
        ] {
            #expect((appearance.titleTextAttributes[.foregroundColor] as? UIColor) == AppTint.indigo.accentUIColor)
            #expect((appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor) == AppTint.indigo.accentUIColor)
            #expect(appearance.backgroundColor == .systemGray)
        }
    }
}
