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

class ColorThemeManager: ObservableObject {
    static let shared = ColorThemeManager()
    
    static let defaultVisited: Color = .red
    static let defaultWantToVisit: Color = .blue
    static let defaultLived: Color = .green

    @Published var visitedColor: Color {
        didSet { save(visitedColor, key: "color_visited") }
    }
    @Published var wantToVisitColor: Color {
        didSet { save(wantToVisitColor, key: "color_wantToVisit") }
    }
    @Published var livedColor: Color {
        didSet { save(livedColor, key: "color_lived") }
    }

    init() {
        visitedColor   = ColorThemeManager.load(key: "color_visited",     default: Self.defaultVisited)
        wantToVisitColor = ColorThemeManager.load(key: "color_wantToVisit", default: Self.defaultWantToVisit)
        livedColor     = ColorThemeManager.load(key: "color_lived",       default: Self.defaultLived)
    }

    func color(for status: CountryStatus) -> Color {
        switch status {
        case .none:        return .clear
        case .visited:     return visitedColor
        case .wantToVisit: return wantToVisitColor
        case .lived:       return livedColor
        }
    }

    func uiColor(for status: CountryStatus) -> UIColor {
        UIColor(color(for: status))
    }

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
    
    func resetToDefaults() {
        visitedColor = Self.defaultVisited
        wantToVisitColor = Self.defaultWantToVisit
        livedColor = Self.defaultLived
    }
}
