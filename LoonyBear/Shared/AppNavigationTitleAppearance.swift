import SwiftUI
import UIKit

@MainActor
enum AppNavigationTitleAppearance {
    static func apply(to bar: UINavigationBar, tint: AppTint) {
        var titleAttributes = bar.titleTextAttributes ?? [:]
        titleAttributes[.foregroundColor] = tint.accentUIColor
        bar.titleTextAttributes = titleAttributes

        var largeTitleAttributes = bar.largeTitleTextAttributes ?? [:]
        largeTitleAttributes[.foregroundColor] = tint.accentUIColor
        bar.largeTitleTextAttributes = largeTitleAttributes

        bar.standardAppearance = tinted(bar.standardAppearance, tint: tint)
        bar.compactAppearance = bar.compactAppearance.map { tinted($0, tint: tint) }
        bar.scrollEdgeAppearance = bar.scrollEdgeAppearance.map { tinted($0, tint: tint) }
        bar.compactScrollEdgeAppearance = bar.compactScrollEdgeAppearance.map { tinted($0, tint: tint) }

        // Preserve per-screen overrides, including their native material and button styling.
        for item in bar.items ?? [] {
            item.standardAppearance = item.standardAppearance.map { tinted($0, tint: tint) }
            item.compactAppearance = item.compactAppearance.map { tinted($0, tint: tint) }
            item.scrollEdgeAppearance = item.scrollEdgeAppearance.map { tinted($0, tint: tint) }
            item.compactScrollEdgeAppearance = item.compactScrollEdgeAppearance.map { tinted($0, tint: tint) }
        }
    }

    private static func tinted(_ appearance: UINavigationBarAppearance, tint: AppTint) -> UINavigationBarAppearance {
        let updated = UINavigationBarAppearance(barAppearance: appearance)
        updated.titleTextAttributes[.foregroundColor] = tint.accentUIColor
        updated.largeTitleTextAttributes[.foregroundColor] = tint.accentUIColor
        return updated
    }
}

extension View {
    func appNavigationTitleTint() -> some View {
        modifier(AppNavigationTitleTintModifier())
    }
}

private struct AppNavigationTitleTintModifier: ViewModifier {
    @Environment(\.appTint) private var tint

    func body(content: Content) -> some View {
        content.background {
            AppNavigationTitleTintController(tint: tint)
                .frame(width: 0, height: 0)
        }
    }
}

struct AppNavigationTitleTintController: UIViewControllerRepresentable {
    let tint: AppTint

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.updateTint(tint)
    }

    final class Controller: UIViewController {
        private var tint: AppTint = .blue
        private var appliedTint: AppTint?
        private weak var styledBar: UINavigationBar?

        func updateTint(_ tint: AppTint) {
            self.tint = tint
            applyTintIfNeeded()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyTintIfNeeded()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyTintIfNeeded(force: true)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyTintIfNeeded()
        }

        private func applyTintIfNeeded(force: Bool = false) {
            guard let bar = navigationController?.navigationBar else { return }
            let titleColor = bar.titleTextAttributes?[.foregroundColor] as? UIColor
            guard force || styledBar !== bar || appliedTint != tint || titleColor != tint.accentUIColor else { return }
            // Only this navigation stack is styled, never another tab or sheet.
            AppNavigationTitleAppearance.apply(to: bar, tint: tint)
            styledBar = bar
            appliedTint = tint
        }
    }
}
