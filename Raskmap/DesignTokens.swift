//
//  DesignTokens.swift
//  Raskmap
//
//  Sistema de design tokens semánticos para mantener coherencia visual
//  cross-sheet. Centraliza colores, radios, tipografía y animaciones
//  que actualmente están hardcoded en ~24 archivos de `Sheets/` + el
//  root de ContentView.swift.
//
//  Auditoría del estado actual (top valores hardcoded):
//  · cornerRadius: 12 (×48), 14 (×41), 10 (×25), 16 (×12), 22 (×7), 8 (×6)
//  · font size: 11 (×23), 22 (×21), 18 (×19), 10 (×18), 20 (×16), 15 (×16),
//               13 (×16), 14 (×15), 16 (×12), 17 (×10), 12 (×10)
//  · 11 valores distintos de cornerRadius → consolidar a 5 tokens.
//  · 15+ font sizes → consolidar a 7 escalas semánticas.
//
//  Plan de migración: estos tokens están disponibles AHORA para uso
//  en nuevos sheets/widgets. La migración progresiva del código
//  hardcoded existente se hará en commits separados (no invasivo).
//
//  Nota: NO sustituye `ColorThemeManager` que gestiona los 4 colores
//  de estado de país (visited/wantToVisit/lived/bucketList) que el
//  usuario puede personalizar desde Ajustes. Aquí están los colores
//  FIJOS de marca + UI neutral.
//

import SwiftUI

// MARK: - Brand colors

/// Colores fijos de marca Raskmap (no personalizables por el usuario).
/// Para los 4 colores de estado de país, usar `ColorThemeManager.shared`.
enum BrandColor {
    /// Azul cobalto — accent primario. Aparece en ~11 sitios hardcoded
    /// como `Color(red: 64/255, green: 114/255, blue: 212/255)`.
    /// Usado para botones primarios, flight mode, links, badges activos.
    static let accent = Color(red: 64/255, green: 114/255, blue: 212/255)

    /// Azul más claro — variante del accent. Aparece en onboarding como
    /// `#53A3FE` (línea 1467 anterior a refactor). Para hover/active
    /// states e indicadores secundarios.
    static let accentLight = Color(red: 83/255, green: 163/255, blue: 254/255)

    /// Azul oscuro de mapa — fondo dark para Live Activity / Wrapped.
    static let mapDark = Color(red: 0.05, green: 0.07, blue: 0.14)

    /// Fondo gradiente fin para Live Activity / Wrapped.
    static let mapDarkSecondary = Color(red: 0.08, green: 0.10, blue: 0.22)
}

// MARK: - Radius

/// Radii semánticos. Reduce los 11 valores distintos de cornerRadius
/// detectados en el código (8, 10, 11, 12, 14, 16, 18, 20, 22, 24...)
/// a 5 escalas con propósito claro.
enum Radius {
    /// 8pt — chips pequeños, capsule alternativa, etiquetas inline.
    static let chip: CGFloat = 8

    /// 12pt — celdas estándar de lista, secciones agrupadas en formularios.
    /// El valor MÁS usado del codebase (48 ocurrencias).
    static let cell: CGFloat = 12

    /// 14pt — cards más grandes, action buttons, botones CTA inline.
    /// Segundo más usado (41 ocurrencias).
    static let card: CGFloat = 14

    /// 16pt — secciones / containers / dialog content.
    static let section: CGFloat = 16

    /// 22pt — sheets full-screen, toasts, fondos con elevación notable.
    /// Reservado para el contenedor más exterior de presentaciones.
    static let sheet: CGFloat = 22
}

// MARK: - Typography

/// Escalas tipográficas semánticas con Satoshi. Para texto fluido
/// (que debe respetar Dynamic Type), usar `.font(.body)` nativo de SwiftUI.
///
/// La extensión `Font.palatino(_:)` (en ContentView.swift) sigue siendo
/// la vía preferida para texto que debe escalar con Dynamic Type. Estas
/// fuentes están pensadas para títulos, etiquetas y números grandes
/// donde el tamaño fijo es intencional.
enum Typography {
    /// 28pt Bold — display grande (números del wrapped, hero text).
    static let display: Font = .custom("Satoshi-Bold", size: 28)

    /// 22pt Bold — títulos de pantalla principal, headers de sheet.
    static let title: Font = .custom("Satoshi-Bold", size: 22)

    /// 18pt Bold — títulos de sección, sub-headers.
    static let titleS: Font = .custom("Satoshi-Bold", size: 18)

    /// 17pt Regular — body principal en sheets. Aproxima a `.body` system.
    static let body: Font = .custom("Satoshi-Regular", size: 17)

    /// 15pt Medium — body secundario, labels de fila.
    static let bodyS: Font = .custom("Satoshi-Medium", size: 15)

    /// 13pt Bold — labels de form, badges, chips.
    static let label: Font = .custom("Satoshi-Bold", size: 13)

    /// 11pt Bold tracked — eyebrows, all-caps headers ("MIS DESTINOS", "DESDE").
    static let eyebrow: Font = .custom("Satoshi-Bold", size: 11)

    /// 10pt Medium — text auxiliar mínimo, footnotes.
    static let caption: Font = .custom("Satoshi-Medium", size: 10)

    /// 14pt Bold monospaced — números/contadores que deben no saltar.
    static let mono: Font = .custom("Satoshi-Bold", size: 14).monospacedDigit()
}

// MARK: - Spacing

/// Spacing tokens (HStack/VStack `spacing:`, padding, etc.) — escala
/// 4pt base.
enum Spacing {
    /// 4pt — gap inline entre icono y texto cortos.
    static let xs: CGFloat = 4

    /// 8pt — gap estándar entre elementos de fila.
    static let s: CGFloat = 8

    /// 12pt — gap entre secciones cercanas, padding moderado.
    static let m: CGFloat = 12

    /// 16pt — padding estándar de container, gap entre cards.
    static let l: CGFloat = 16

    /// 20pt — padding entre bloques separados verticalmente.
    static let xl: CGFloat = 20

    /// 28pt — separación generosa entre secciones distintas.
    static let xxl: CGFloat = 28
}

// MARK: - Animations

/// Animaciones tokenizadas. Reduce la variedad ad-hoc (≥4 configuraciones
/// distintas de spring/smooth/easeInOut en código actual) a 3 intenciones
/// semánticas claras.
enum Anim {
    /// Snappy — botones, toggles, taps. Respuesta rápida con poco bounce.
    static let snappy: Animation = .spring(response: 0.3, dampingFraction: 0.8)

    /// Smooth — transiciones de sheets, navegación entre estados. Más
    /// elegante, sutilmente bouncy.
    static let smooth: Animation = .spring(response: 0.45, dampingFraction: 0.75)

    /// Bouncy — momentos de celebración (Wrapped, unlock de logros).
    /// Más teatral.
    static let bouncy: Animation = .smooth(duration: 0.5, extraBounce: 0.15)

    /// Linear gentle — color fades, opacity changes (no spring).
    static let gentle: Animation = .easeInOut(duration: 0.25)
}

// MARK: - Tap target minimum

/// Tamaño mínimo de tap target según Apple HIG (44×44 pt). Usar en
/// `.frame(minWidth: TapTarget.min, minHeight: TapTarget.min)` para
/// botones small que actualmente quedan por debajo.
enum TapTarget {
    static let min: CGFloat = 44
}
