//
//  ColorThemeManager.swift
//  Raskmap
//
//  Gestiona los colores personalizables de cada categoría.
//  Se persiste en UserDefaults y se propaga por toda la app via @EnvironmentObject.
//

import SwiftUI
import UIKit
import Combine

@MainActor
class ColorThemeManager: ObservableObject {
    static let shared = ColorThemeManager()
    
    // Paleta por defecto (sRGB): tonos con saturación media, legibles sobre tiles de Apple Maps.
    // Visitados → #DC6647 (terracota vivo)
    // Próximos (wantToVisit) → #00CB7C (verde esmeralda)
    // Quiero (bucketList) → #E5B257 (ámbar dorado)
    static let defaultVisited: Color     = Color(.sRGB, red: 0xDC/255.0, green: 0x66/255.0, blue: 0x47/255.0, opacity: 1.0)
    static let defaultWantToVisit: Color = Color(.sRGB, red: 0x00/255.0, green: 0xCB/255.0, blue: 0x7C/255.0, opacity: 1.0)
    static let defaultLived: Color       = Color(.sRGB, red: 0x5D/255.0, green: 0xAD/255.0, blue: 0x6E/255.0, opacity: 1.0)
    static let defaultBucketList: Color  = Color(.sRGB, red: 0xE5/255.0, green: 0xB2/255.0, blue: 0x57/255.0, opacity: 1.0)

    @Published var visitedColor: Color {
        didSet { save(visitedColor, key: "color_visited") }
    }
    @Published var wantToVisitColor: Color {
        didSet { save(wantToVisitColor, key: "color_wantToVisit") }
    }
    @Published var livedColor: Color {
        didSet { save(livedColor, key: "color_lived") }
    }
    @Published var bucketListColor: Color {
        didSet { save(bucketListColor, key: "color_bucketList") }
    }

    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "app_isDarkMode")
            applyColorScheme()
        }
    }

    func applyColorScheme() {
        let style: UIUserInterfaceStyle = isDarkMode ? .dark : .light
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { window in
                window.overrideUserInterfaceStyle = style
                // Walk the full presented VC chain so open sheets update instantly
                var vc = window.rootViewController
                while let next = vc?.presentedViewController {
                    next.overrideUserInterfaceStyle = style
                    vc = next
                }
                window.rootViewController?.overrideUserInterfaceStyle = style
            }
    }

    init() {
        visitedColor   = ColorThemeManager.load(key: "color_visited",     default: Self.defaultVisited)
        wantToVisitColor = ColorThemeManager.load(key: "color_wantToVisit", default: Self.defaultWantToVisit)
        livedColor     = ColorThemeManager.load(key: "color_lived",       default: Self.defaultLived)
        bucketListColor = ColorThemeManager.load(key: "color_bucketList",  default: Self.defaultBucketList)
        isDarkMode     = UserDefaults.standard.bool(forKey: "app_isDarkMode")
    }

    func color(for status: CountryStatus) -> Color {
        switch status {
        case .none:        return .clear
        case .visited:     return visitedColor
        case .wantToVisit: return wantToVisitColor
        case .lived:       return livedColor
        case .bucketList:  return bucketListColor
        }
    }

    func uiColor(for status: CountryStatus) -> UIColor {
        UIColor(color(for: status))
    }

    var bucketListUIColor: UIColor { UIColor(bucketListColor) }

    // MARK: - Persistencia
    private static func load(key: String, default fallback: Color) -> Color {
        guard let data = UserDefaults.standard.data(forKey: key),
              let components = try? JSONDecoder().decode([Double].self, from: data),
              components.count == 4 else { return fallback }
        return Color(.sRGB, red: components[0], green: components[1],
                     blue: components[2], opacity: components[3])
    }

    private func save(_ color: Color, key: String) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let data = try? JSONEncoder().encode([Double(r), Double(g), Double(b), Double(a)])
        UserDefaults.standard.set(data, forKey: key)
    }
    
    // MARK: - SwiftUI color scheme modifier
    /// Apply to every sheet's root so it re-renders instantly when isDarkMode changes.
    struct Scheme: ViewModifier {
        @ObservedObject fileprivate var mgr = ColorThemeManager.shared
        func body(content: Content) -> some View {
            content
                .preferredColorScheme(mgr.isDarkMode ? .dark : .light)
                .presentationBackground(Color(.systemGroupedBackground))
        }
    }

    func resetToDefaults() {
        visitedColor = Self.defaultVisited
        wantToVisitColor = Self.defaultWantToVisit
        livedColor = Self.defaultLived
        bucketListColor = Self.defaultBucketList
    }
}

extension View {
    func appColorScheme() -> some View {
        modifier(ColorThemeManager.Scheme())
    }
}
