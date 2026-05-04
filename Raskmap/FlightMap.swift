//
//  FlightMap.swift
//  Raskmap
//
//  Coordenadas de aeropuertos + lógica de rutas aéreas para el modo vuelos.
//

import Foundation
import CoreLocation
import MapKit

enum AirportCoordinates {
    static let lookup: [String: CLLocationCoordinate2D] = {
        guard let url = Bundle.main.url(forResource: "airport_coords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        var result: [String: CLLocationCoordinate2D] = [:]
        for (iata, arr) in dict where arr.count == 2 {
            result[iata] = CLLocationCoordinate2D(latitude: arr[0], longitude: arr[1])
        }
        return result
    }()

    static func coordinate(for iata: String) -> CLLocationCoordinate2D? { lookup[iata] }
}

struct FlightRoutePair: Hashable {
    let a: String
    let b: String
    init(_ x: String, _ y: String) {
        if x <= y { a = x; b = y } else { a = y; b = x }
    }
}

enum FlightRouteFilter: String, Hashable {
    case past      // dateFrom <= hoy
    case upcoming  // dateFrom > hoy
}

enum FlightRoutesBuilder {
    static func build(from trips: [Trip],
                      filter: FlightRouteFilter = .past) -> (routes: Set<FlightRoutePair>, airports: Set<String>) {
        let today = Calendar.current.startOfDay(for: Date())
        var routes = Set<FlightRoutePair>()
        var airports = Set<String>()

        func addPair(_ a: String, _ b: String) {
            guard a != b else { return }
            guard AirportCoordinates.coordinate(for: a) != nil,
                  AirportCoordinates.coordinate(for: b) != nil else { return }
            routes.insert(FlightRoutePair(a, b))
            airports.insert(a)
            airports.insert(b)
        }

        func addSequence(_ iatas: [String]) {
            guard iatas.count >= 2 else { return }
            for i in 0..<(iatas.count - 1) { addPair(iatas[i], iatas[i + 1]) }
        }

        for trip in trips {
            let tripStart = Calendar.current.startOfDay(for: trip.dateFrom)
            switch filter {
            case .past:     guard tripStart <= today else { continue }
            case .upcoming: guard tripStart >  today else { continue }
            }
            let segs = trip.tripSegments
            if !segs.isEmpty {
                for seg in segs where seg.transport == "✈️" {
                    if let outs = seg.airports { addSequence(outs.map { $0.iata }) }
                    if let rets = seg.returnAirports { addSequence(rets.map { $0.iata }) }
                }
            } else if trip.transport == "✈️" {
                let iatas = trip.tripAirports.map { $0.iata }
                // Sin segmentos no conocemos el orden real de la ruta: solo conectamos el
                // caso directo (2 aeropuertos) para evitar trazar rutas inventadas.
                if iatas.count == 2 { addPair(iatas[0], iatas[1]) }
            }
        }
        return (routes, airports)
    }

    /// Variante de `build` con early-exit: devuelve `true` en cuanto encuentra una
    /// ruta válida para el filtro dado. Útil para decidir si mostrar empty-state
    /// sin materializar todo el set de rutas.
    static func hasAnyRoute(in trips: [Trip], filter: FlightRouteFilter = .past) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())

        func pairValid(_ a: String, _ b: String) -> Bool {
            guard a != b else { return false }
            return AirportCoordinates.coordinate(for: a) != nil
                && AirportCoordinates.coordinate(for: b) != nil
        }
        func sequenceHasPair(_ iatas: [String]) -> Bool {
            guard iatas.count >= 2 else { return false }
            for i in 0..<(iatas.count - 1) where pairValid(iatas[i], iatas[i + 1]) { return true }
            return false
        }

        for trip in trips {
            let tripStart = Calendar.current.startOfDay(for: trip.dateFrom)
            switch filter {
            case .past:     guard tripStart <= today else { continue }
            case .upcoming: guard tripStart >  today else { continue }
            }
            if !trip.tripSegments.isEmpty {
                for seg in trip.tripSegments where seg.transport == "✈️" {
                    if let outs = seg.airports, sequenceHasPair(outs.map { $0.iata }) { return true }
                    if let rets = seg.returnAirports, sequenceHasPair(rets.map { $0.iata }) { return true }
                }
            } else if trip.transport == "✈️" {
                let iatas = trip.tripAirports.map { $0.iata }
                if iatas.count == 2 && pairValid(iatas[0], iatas[1]) { return true }
            }
        }
        return false
    }
}

// MARK: - Annotation

final class AirportDotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let iata: String
    init(iata: String, coordinate: CLLocationCoordinate2D) {
        self.iata = iata
        self.coordinate = coordinate
    }
}

