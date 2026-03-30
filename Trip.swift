//
//  Trip.swift
//  Raskmap
//
import Foundation
import SwiftData

struct TripAirport: Codable, Hashable {
    let iata: String
    var count: Int
}

struct TripAirline: Codable, Hashable {
    let name: String
    var count: Int
}

@Model
class Trip {
    var isoCode: String = ""
    var title: String?
    var dateFrom: Date = Date()
    var dateTo: Date?
    var transport: String?
    var hasLayover: Bool = false
    var airport: String?          // Legacy single airport
    var airportsRaw: String?      // JSON-encoded [TripAirport]
    var airlinesRaw: String?      // JSON-encoded [TripAirline]
    var airlineCountsRaw: String? // Legacy - kept for migration
    var createdAt: Date = Date()

    init(isoCode: String, title: String? = nil, dateFrom: Date, dateTo: Date? = nil,
         transport: String? = nil,
         tripAirports: [TripAirport] = [], tripAirlines: [TripAirline] = []) {
        self.isoCode = isoCode
        self.title = title
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.transport = transport
        self.airport = nil
        self.airlineCountsRaw = nil
        self.airportsRaw = tripAirports.isEmpty ? nil :
            (try? JSONEncoder().encode(tripAirports)).flatMap { String(data: $0, encoding: .utf8) }
        self.airlinesRaw = tripAirlines.isEmpty ? nil :
            (try? JSONEncoder().encode(tripAirlines)).flatMap { String(data: $0, encoding: .utf8) }
        self.createdAt = Date()
    }

    var tripAirports: [TripAirport] {
        get {
            var result: [TripAirport] = []
            if let raw = airportsRaw, let data = raw.data(using: .utf8) {
                if let arr = try? JSONDecoder().decode([TripAirport].self, from: data) {
                    result = arr
                } else if let arr = try? JSONDecoder().decode([String].self, from: data) {
                    // Legacy [String] format
                    result = arr.map { TripAirport(iata: $0, count: 1) }
                } else if let arr = try? JSONDecoder().decode([[String: String]].self, from: data) {
                    // Legacy TripAirport with roundTrip bool
                    result = arr.compactMap { d in
                        guard let iata = d["iata"] else { return nil }
                        return TripAirport(iata: iata, count: d["roundTrip"] == "true" ? 2 : 1)
                    }
                }
            }
            // Migrate legacy single airport field
            if let legacy = airport, !legacy.isEmpty, !result.contains(where: { $0.iata == legacy }) {
                result.insert(TripAirport(iata: legacy, count: 1), at: 0)
            }
            return result
        }
        set {
            airportsRaw = newValue.isEmpty ? nil :
                (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
            if !newValue.isEmpty { airport = nil }
        }
    }

    var tripAirlines: [TripAirline] {
        get {
            guard let raw = airlinesRaw, let data = raw.data(using: .utf8) else { return [] }
            if let arr = try? JSONDecoder().decode([TripAirline].self, from: data) { return arr }
            // Legacy [String] format
            if let arr = try? JSONDecoder().decode([String].self, from: data) {
                // Check airlineCountsRaw for manual counts
                var counts: [String: Int] = [:]
                if let cr = airlineCountsRaw, let cd = cr.data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: Int].self, from: cd) {
                    counts = dict
                }
                return arr.map { TripAirline(name: $0, count: counts[$0] ?? 1) }
            }
            return []
        }
        set {
            airlinesRaw = newValue.isEmpty ? nil :
                (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    // Convenience
    var airports: [String] { tripAirports.map { $0.iata } }
    var airlines: [String] { tripAirlines.map { $0.name } }

    var airportCountForStats: [String: Int] {
        Dictionary(tripAirports.map { ($0.iata, $0.count) }, uniquingKeysWith: +)
    }

    var year: Int { Calendar.current.component(.year, from: dateTo ?? dateFrom) }
    var effectiveEndDate: Date { dateTo ?? dateFrom }
}
