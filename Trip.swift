//
//  Trip.swift
//  Raskmap
//
import Foundation
import SwiftData

struct TripAirport: Codable, Hashable {
    let iata: String
    var roundTrip: Bool
}

@Model
class Trip {
    var isoCode: String
    var title: String?
    var dateFrom: Date
    var dateTo: Date?
    var transport: String?
    var airport: String?        // Legacy single airport
    var airportsRaw: String?    // JSON-encoded [TripAirport]
    var airlinesRaw: String?    // JSON-encoded [String]
    var airlineCountsRaw: String? // JSON-encoded [String: Int] manual counts (multi-airline only)
    var createdAt: Date

    init(isoCode: String, title: String? = nil, dateFrom: Date, dateTo: Date? = nil,
         transport: String? = nil, airport: String? = nil,
         tripAirports: [TripAirport] = [], airlines: [String] = [],
         airlineCounts: [String: Int] = [:]) {
        self.isoCode = isoCode
        self.title = title
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.transport = transport
        self.airport = nil
        var all = tripAirports
        if let ap = airport, !ap.isEmpty, !all.contains(where: { $0.iata == ap }) {
            all.insert(TripAirport(iata: ap, roundTrip: false), at: 0)
        }
        self.airportsRaw = all.isEmpty ? nil : (try? JSONEncoder().encode(all)).flatMap { String(data: $0, encoding: .utf8) }
        self.airlinesRaw = airlines.isEmpty ? nil : (try? JSONEncoder().encode(airlines)).flatMap { String(data: $0, encoding: .utf8) }
        self.airlineCountsRaw = airlineCounts.isEmpty ? nil : (try? JSONEncoder().encode(airlineCounts)).flatMap { String(data: $0, encoding: .utf8) }
        self.createdAt = Date()
    }

    var tripAirports: [TripAirport] {
        get {
            var result: [TripAirport] = []
            if let raw = airportsRaw, let data = raw.data(using: .utf8) {
                if let arr = try? JSONDecoder().decode([TripAirport].self, from: data) {
                    result = arr
                } else if let arr = try? JSONDecoder().decode([String].self, from: data) {
                    result = arr.map { TripAirport(iata: $0, roundTrip: false) }
                }
            }
            if let legacy = airport, !legacy.isEmpty, !result.contains(where: { $0.iata == legacy }) {
                result.insert(TripAirport(iata: legacy, roundTrip: false), at: 0)
            }
            return result
        }
        set {
            airportsRaw = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
            if !newValue.isEmpty { airport = nil }
        }
    }

    var airports: [String] { tripAirports.map { $0.iata } }

    // Total legs per airport for stats
    var airportCountForStats: [String: Int] {
        var result: [String: Int] = [:]
        for ap in tripAirports {
            result[ap.iata, default: 0] += ap.roundTrip ? 2 : 1
        }
        return result
    }

    var airlines: [String] {
        get {
            guard let raw = airlinesRaw, let data = raw.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }
        set {
            airlinesRaw = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    // Manual counts for multi-airline trips
    var airlineCounts: [String: Int] {
        get {
            guard let raw = airlineCountsRaw, let data = raw.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            return dict
        }
        set {
            airlineCountsRaw = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    // Effective count for each airline in stats
    func countForAirline(_ name: String) -> Int {
        let als = airlines
        if als.count == 1 {
            // Auto: sum all airport legs
            return tripAirports.reduce(0) { $0 + ($1.roundTrip ? 2 : 1) }
        } else {
            // Manual: use stored count, default 0
            return airlineCounts[name] ?? 0
        }
    }

    var year: Int { Calendar.current.component(.year, from: dateTo ?? dateFrom) }
    var effectiveEndDate: Date { dateTo ?? dateFrom }
}
