//
//  RaskmapApp.swift
//  Raskmap
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Bloqueo de orientación

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
        orientationLock = orientation
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

// MARK: - App

@main
struct RaskmapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var showSplash: Bool = true
    @State private var splashTimerDone: Bool = false
    @State private var contentReady: Bool = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Country.self, Trip.self])
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

    @StateObject private var colorTheme = ColorThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(onContentReady: {
                        contentReady = true
                        dismissSplashIfReady()
                    })
                    .modelContainer(sharedModelContainer)
                    .environment(\.font, .custom("Palatino", size: 16))
                    .environmentObject(colorTheme)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                        .onAppear {
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
