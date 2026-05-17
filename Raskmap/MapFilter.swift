//
//  MapFilter.swift
//  Raskmap
//
//  Filtro visual del mapa principal. Cuando hay un filtro activo, sólo
//  los países cuyo `status` matchea siguen pintándose con su color real;
//  el resto se renderizan como `.none` (transparentes) — el mapa
//  efectivamente "enfoca" en una categoría a la vez sin tocar los datos.
//
//  No persiste — vive en `@State` de ContentView; al cerrar y reabrir la
//  app, el filtro vuelve a `.all`. Si en el futuro quieres que persista,
//  cambiar a `@AppStorage("mapFilter")`.
//

import Foundation

enum MapFilter: Hashable, Identifiable {
    case all
    case visited
    case wantToVisit   // "Próximos"
    case bucketList
    /// Filtro por transporte: muestra solo países visitados/próximos cuyo
    /// trip principal usó el emoji indicado. ✈️ 🚗 🚂 🚌 🚢 🚶🏻
    case transport(String)

    var id: String {
        switch self {
        case .all:               return "all"
        case .visited:           return "visited"
        case .wantToVisit:       return "wantToVisit"
        case .bucketList:        return "bucketList"
        case .transport(let e):  return "transport_\(e)"
        }
    }

    /// Label para el menú UI.
    var label: String {
        switch self {
        case .all:               return "Todos"
        case .visited:           return "Solo visitados"
        case .wantToVisit:       return "Solo próximos"
        case .bucketList:        return "Solo bucket list"
        case .transport(let e):  return "Solo \(e)"
        }
    }

    /// SF Symbol para el menú (los transport filters no usan SF, ver
    /// `emoji` para el caso especial).
    var systemImage: String {
        switch self {
        case .all:         return "globe.americas.fill"
        case .visited:     return "checkmark.circle.fill"
        case .wantToVisit: return "calendar"
        case .bucketList:  return "star.fill"
        case .transport:   return "airplane"  // genérico — el emoji se usa en label
        }
    }

    /// Devuelve `true` si el filtro está activo (≠ .all).
    var isActive: Bool {
        if case .all = self { return false }
        return true
    }

    /// Lista de los 4 filtros básicos (sin transport — éstos se generan
    /// dinámicamente en el Menu UI según los emojis disponibles).
    static var primaryCases: [MapFilter] {
        [.all, .visited, .wantToVisit, .bucketList]
    }

    /// Devuelve el status "efectivo" tras aplicar el filtro. Si el filtro
    /// no matchea el status real del país, devuelve `.none` (el mapa lo
    /// pintará transparente). Si el filtro está en `.all`, pasa el status
    /// sin tocar.
    ///
    /// Para `.transport(emoji)`, el país solo pasa si está visitado o
    /// próximo Y tiene algún trip cuyo `transport` matchea (o algún
    /// `tripSegment.transport` matchea). El check requiere data fuera del
    /// status, por eso el caller debe usar `effectiveStatus(_:trips:)`
    /// con la sobrecarga.
    /// Nota: `.lived` matchea con el filtro `.visited` (vivir cuenta como visitar).
    func effectiveStatus(_ status: CountryStatus) -> CountryStatus {
        switch self {
        case .all:
            return status
        case .visited:
            return (status == .visited || status == .lived) ? status : .none
        case .wantToVisit:
            return status == .wantToVisit ? status : .none
        case .bucketList:
            return status == .bucketList ? status : .none
        case .transport:
            // Para transport filter necesitamos info de trips, no solo
            // status. El default devuelve .none — el caller debe usar
            // la sobrecarga con trips. Si llamas a esta versión con
            // .transport, todo se filtra fuera (defensivo).
            return .none
        }
    }

    /// Sobrecarga para filtro por transporte: necesita la lista de trips
    /// del país para chequear si alguno usa el emoji indicado.
    func effectiveStatus(_ status: CountryStatus, tripsForCountry: [Trip]) -> CountryStatus {
        switch self {
        case .all, .visited, .wantToVisit, .bucketList:
            return effectiveStatus(status)
        case .transport(let emoji):
            // Normalizamos 🚶 a 🚶🏻 (skin-tone) para agrupar caminatas.
            let normalize: (String) -> String = { $0 == "🚶" ? "🚶🏻" : $0 }
            let target = normalize(emoji)
            let hasMatch = tripsForCountry.contains { trip in
                if normalize(trip.transport ?? "") == target { return true }
                return trip.tripSegments.contains { normalize($0.transport) == target }
            }
            return hasMatch ? status : .none
        }
    }
}
