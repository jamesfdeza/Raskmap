//
//  RaskmapApp.swift
//  Raskmap
//
//  Punto de entrada de la app. Igual que el main() de Java.
//  Solo cambiamos Item.self por Country.self
//

import SwiftUI
import SwiftData

@main
struct RaskmapApp: App {
    var sharedModelContainer: ModelContainer = {
        // Schema = lista de modelos que SwiftData debe gestionar
        // (como listar las @Entity en persistence.xml de JPA)
        let schema = Schema([
            Country.self,   // ← Reemplazamos Item.self por Country.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false  // false = persiste en disco (SQLite interno)
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
