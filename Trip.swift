//
//  Trip.swift
//  Raskmap
//
//  Modelo para viajes individuales a un país.
//

import Foundation
import SwiftData

@Model
class Trip {
    var isoCode: String       // País al que pertenece este viaje
    var dateFrom: Date        // Fecha inicio
    var dateTo: Date?         // Fecha fin (opcional)
    var transport: String?    // Emoji de transporte
    var createdAt: Date

    init(isoCode: String, dateFrom: Date, dateTo: Date? = nil, transport: String? = nil) {
        self.isoCode = isoCode
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.transport = transport
        self.createdAt = Date()
    }

    // Año del viaje (basado en dateTo o dateFrom)
    var year: Int {
        Calendar.current.component(.year, from: dateTo ?? dateFrom)
    }

    // Fecha efectiva de fin (dateTo o dateFrom si no hay fin)
    var effectiveEndDate: Date {
        dateTo ?? dateFrom
    }
}
