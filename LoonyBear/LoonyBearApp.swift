import CoreData
import SwiftUI

@main
struct LoonyBearApp: App {
    private let bootstrapState = AppEnvironment.live()
    @AppStorage("appearance_mode") private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch bootstrapState {
                case .ready(let environment):
                    ContentView(
                        appState: environment.appState,
                        pillAppState: environment.pillAppState,
                        notificationCoordinator: environment.notificationCoordinator,
                        badgeService: environment.badgeService
                    )
                        .environment(\.managedObjectContext, environment.persistenceController.container.viewContext)
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                environment.appState.refreshDashboard()
                                environment.pillAppState.refreshDashboard()
                                environment.appState.notificationService.handleAppDidBecomeActive()
                                environment.pillAppState.handleAppDidBecomeActive()
                            }
                        }
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
}
