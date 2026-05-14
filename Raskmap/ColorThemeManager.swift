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
    
    // Paleta refinada (sRGB) — Sprint 4 item 15.
    //
    // Cambios respecto a la paleta anterior (motivados por auditoría UX/UI):
    //  · Visitados: #DC6647 (terracota vivo) → #D65B3F (siena tostado)
    //    Más cálido, evoca "tierra explorada". Diferencia más clara contra
    //    el ámbar (bucketList).
    //  · Próximos: #00CB7C (verde esmeralda saturado) → #5BA89B (verde mar)
    //    Menos chillón, descansa la vista en mapas con muchos países en
    //    próximos. Mantiene la asociación "verde = futuro/avance".
    //  · Vivido: #5DAD6E (verde salvia) → #7B5BAB (violeta apagado)
    //    FIX crítico: el salvia y el esmeralda anteriores eran demasiado
    //    parecidos (semánticamente confundibles). Violeta diferencia
    //    visualmente "echar raíces" (vivido) del "futuro" (próximos).
    //  · Quiero (bucketList): #E5B257 (ámbar dorado) → #F2C265 (miel)
    //    Ligeramente más suave; mantiene el tono dorado pero menos saturado
    //    para coexistir mejor con la nueva siena del visited.
    //
    // Usuarios que ya personalizaron colores vía Ajustes: NO se ven afectados
    // — sus elecciones persisten en UserDefaults. Solo los nuevos usuarios o
    // los que pulsen "Restablecer colores" verán la nueva paleta.
    static let defaultVisited: Color     = Color(.sRGB, red: 0xD6/255.0, green: 0x5B/255.0, blue: 0x3F/255.0, opacity: 1.0)
    static let defaultWantToVisit: Color = Color(.sRGB, red: 0x5B/255.0, green: 0xA8/255.0, blue: 0x9B/255.0, opacity: 1.0)
    static let defaultLived: Color       = Color(.sRGB, red: 0x7B/255.0, green: 0x5B/255.0, blue: 0xAB/255.0, opacity: 1.0)
    static let defaultBucketList: Color  = Color(.sRGB, red: 0xF2/255.0, green: 0xC2/255.0, blue: 0x65/255.0, opacity: 1.0)

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
        // Default to DARK en primer launch — bool(forKey:) devolvería `false`
        // si la key no existe, lo que daría light por accidente. Detectamos
        // explícitamente la ausencia de la key vía `object(forKey:)` y
        // persistimos el default para mantener consistencia.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "app_isDarkMode") == nil {
            defaults.set(true, forKey: "app_isDarkMode")
            isDarkMode = true
        } else {
            isDarkMode = defaults.bool(forKey: "app_isDarkMode")
        }
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
