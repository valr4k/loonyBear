import SwiftUI

enum AppTintMode: String, CaseIterable, Identifiable {
    static let storageKey = "app_tint_mode"

    case single
    case bySection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "Single color"
        case .bySection: "By section"
        }
    }

    static func stored(rawValue: String) -> AppTintMode {
        AppTintMode(rawValue: rawValue) ?? .single
    }

    func tint(for tab: AppTab, singleTint: AppTint) -> AppTint {
        guard self == .bySection else { return singleTint }
        return switch tab {
        case .myPills: .amber
        case .myHabits: .green
        case .events: .indigo
        case .settings: .blue
        }
    }
}

extension EnvironmentValues {
    @Entry var appTint: AppTint = .blue
}

extension View {
    func appTintScope(_ tint: AppTint) -> some View {
        environment(\.appTint, tint)
            .tint(tint.accentColor)
    }
}
