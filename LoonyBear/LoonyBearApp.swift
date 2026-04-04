//
//  LoonyBearApp.swift
//  LoonyBear
//
//  Created by Valerii Vedmid on 05.04.2026.
//

import SwiftUI
import CoreData

@main
struct LoonyBearApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
