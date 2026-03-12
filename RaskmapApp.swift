//
//  RaskmapApp.swift
//  Raskmap
//

import SwiftUI
import SwiftData

@main
struct RaskmapApp: App {
    @State private var showSplash: Bool = true
    @State private var splashTimerDone: Bool = false
    @State private var contentReady: Bool = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Country.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    func dismissSplashIfReady() {
        guard splashTimerDone && contentReady else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            showSplash = false
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(onContentReady: {
                        contentReady = true
                        dismissSplashIfReady()
                    })
                    .modelContainer(sharedModelContainer)
                    .environment(\.font, .custom("Palatino", size: 16))

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                        .onAppear {
                            // Timer mínimo de 3s
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                splashTimerDone = true
                                dismissSplashIfReady()
                            }
                        }
                }
            }
        }
    }
}
