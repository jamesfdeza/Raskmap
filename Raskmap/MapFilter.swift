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

enum MapFilter: String, CaseIterable, Identifiable {
    case all          = "all"
    case visited      = "visited"
    case wantToVisit  = "wantToVisit"   // "Próximos"
    case bucketList   = "bucketList"

    var id: String { rawValue }

    /// Label para el menú UI.
    var label: String {
        switch self {
        case .all:         return "Todos"
        case .visited:     return "Solo visitados"
        case .wantToVisit: return "Solo próximos"
        case .bucketList:  return "Solo bucket list"
        }
    }

    /// SF Symbol para el menú.
    var systemImage: String {
        switch self {
        case .all:         return "globe.americas.fill"
        case .visited:     return "checkmark.circle.fill"
        case .wantToVisit: return "calendar"
        case .bucketList:  return "star.fill"
        }
    }

    /// Devuelve el status "efectivo" tras aplicar el filtro. Si el filtro
    /// no matchea el status real del país, devuelve `.none` (el mapa lo
    /// pintará transparente). Si el filtro está en `.all`, pasa el status
    /// sin tocar.
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
        }
    }
}
