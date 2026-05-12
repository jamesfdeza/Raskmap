//
//  SnapshotTests.swift
//  RaskmapTests
//
//  Snapshot tests reales con pointfreeco/swift-snapshot-testing. Captan
//  regresiones visuales (cambios accidentales de paleta, layout, etc.)
//  que `RenderSmokeTests` solo detecta a nivel "rendered? sí/no".
//
//  Para activar estos tests:
//
//  1. En Xcode: File → Add Package Dependencies…
//     URL: https://github.com/pointfreeco/swift-snapshot-testing
//     Version: from 1.17.0
//     Add to target: RaskmapTests
//
//  2. Borrar el `#if canImport(SnapshotTesting)` (líneas inferiores) o
//     dejarlo — funciona en cuanto el módulo esté presente.
//
//  3. Primera ejecución generará los snapshots de referencia en
//     `RaskmapTests/__Snapshots__/`. Re-ejecutar para validar.
//
//  4. Tras cambios visuales intencionales (ej. paleta refinada):
//     borra el snapshot afectado y re-ejecuta, o pasa
//     `isRecording = true` temporalmente.
//
//  Cobertura inicial: 6 capturas de UI crítica. Ampliar progresivamente.
//

import Testing
import SwiftUI
@testable import Raskmap

#if canImport(SnapshotTesting)
import SnapshotTesting

@MainActor
struct SnapshotTests {

    // Helper que envuelve cualquier View en un frame controlado para que
    // el snapshot sea determinista (independiente del tamaño del simulador).
    private func capture<V: View>(_ view: V,
                                  size: CGSize = CGSize(width: 390, height: 100),
                                  named: String,
                                  file: StaticString = #file,
                                  testName: String = #function) {
        let sized = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: sized)
        host.view.frame = CGRect(origin: .zero, size: size)
        assertSnapshot(of: host, as: .image(on: .iPhone15), named: named,
                       file: file, testName: testName)
    }

    @Test("FlagLabel con bandera estándar")
    func flagLabel_standard() {
        capture(FlagLabel(emoji: "🇪🇸", size: 32),
                size: CGSize(width: 64, height: 64),
                named: "flagLabel_ES")
    }

    @Test("FlagLabel con fallback (🌐)")
    func flagLabel_fallback() {
        capture(FlagLabel(emoji: "🌐", size: 32),
                size: CGSize(width: 64, height: 64),
                named: "flagLabel_fallback")
    }

    @Test("StatBadge con valor pequeño")
    func statBadge_small() {
        capture(StatBadge(value: 12, label: "Visitados", color: BrandColor.accent),
                size: CGSize(width: 120, height: 60),
                named: "statBadge_12")
    }

    @Test("StatBadge con valor grande (3 dígitos)")
    func statBadge_large() {
        capture(StatBadge(value: 193, label: "Visitados", color: BrandColor.accent),
                size: CGSize(width: 120, height: 60),
                named: "statBadge_193")
    }

    @Test("LegendItem")
    func legendItem() {
        capture(LegendItem(color: ColorThemeManager.defaultVisited, label: "Visitados"),
                size: CGSize(width: 140, height: 30),
                named: "legendItem")
    }

    @Test("Paleta refinada: cuatro chips de color")
    func palette_refined() {
        let view = HStack(spacing: 8) {
            ForEach([
                ("Visited", ColorThemeManager.defaultVisited),
                ("Próx.",   ColorThemeManager.defaultWantToVisit),
                ("Vivido",  ColorThemeManager.defaultLived),
                ("Bucket",  ColorThemeManager.defaultBucketList)
            ], id: \.0) { name, color in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .frame(width: 64, height: 40)
                    Text(name).font(.system(size: 10))
                }
            }
        }
        capture(view, size: CGSize(width: 360, height: 80), named: "palette_v2")
    }
}

#else
// Stub vacío para que el target compile incluso sin la dep SPM.
// Cuando añadas swift-snapshot-testing al target RaskmapTests,
// los tests reales arriba se activan automáticamente.
@MainActor
struct SnapshotTests {
    @Test("Placeholder — SnapshotTesting no disponible")
    func placeholderUntilSPMAdded() {
        // Para activar: File → Add Package Dependencies en Xcode con
        // https://github.com/pointfreeco/swift-snapshot-testing
        #expect(true)
    }
}
#endif
