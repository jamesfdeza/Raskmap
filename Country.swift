//
//  Country.swift
//  Raskmap
//
//  Modelo de datos para cada país.
//  En Java sería equivalente a una @Entity de JPA.
//

import Foundation
import SwiftData
import UIKit

// MARK: - Estado del país (como un enum de Java)
enum CountryStatus: String, Codable, Identifiable {
    var id: String { rawValue }
    case none        = "none"
    case visited     = "visited"     // Rojo
    case wantToVisit = "wantToVisit" // Azul
    case lived       = "lived"       // Verde
    case bucketList  = "bucketList"  // Naranja

    var overlayColor: UIColor {
        ColorThemeManager.shared.uiColor(for: self)
    }

    var strokeColor: UIColor {
        switch self {
        case .none: return UIColor.systemGray.withAlphaComponent(0.2)
        default:    return ColorThemeManager.shared.uiColor(for: self)
        }
    }

    var label: String {
        switch self {
        case .none:        return "Sin marcar"
        case .visited:     return "✅ Visitados"
        case .wantToVisit: return "🔜 Próximos"
        case .lived:       return "🏠 Vivido"
        case .bucketList:  return "📝 Bucket List"
        }
    }
}

// MARK: - Modelo SwiftData (equivalente a una clase @Entity en Java/JPA)
// @Model es como @Entity — SwiftData gestiona la persistencia automáticamente.
@Model
class Country {
    var name: String        // Nombre del país (ej: "Spain")
    var isoCode: String     // Código ISO A3 (ej: "ESP")
    var statusRaw: String   // Guardamos el rawValue del enum como String
    var plannedDate: Date?     // Fecha desde (inicio del viaje)
    var plannedDateTo: Date?   // Fecha hasta (fin del viaje)
    var transport: String?     // Medio de transporte
    var visitCount: Int = 0   // Número de veces visitado

    // Propiedad calculada para trabajar con el enum (como un getter/setter en Java)
    var status: CountryStatus {
        get { CountryStatus(rawValue: statusRaw) ?? .none }
        set { statusRaw = newValue.rawValue }
    }

    init(name: String, isoCode: String, status: CountryStatus = .none,
         plannedDate: Date? = nil, plannedDateTo: Date? = nil,
         transport: String? = nil, visitCount: Int = 0) {
        self.name = name
        self.isoCode = isoCode
        self.statusRaw = status.rawValue
        self.plannedDate = plannedDate
        self.plannedDateTo = plannedDateTo
        self.transport = transport
        self.visitCount = visitCount
    }
    
    func cycleStatus() {
        switch status {
        case .none:        status = .visited
        case .visited:     status = .wantToVisit
        case .wantToVisit: status = .lived
        case .lived:       status = .bucketList
        case .bucketList:  status = .none
        }
    }
}
