//
//  BannerComputer.swift
//  Raskmap
//
//  Cómputos puros para los banners "Quedan X días" del modo mapa y modo
//  vuelo. Extraído de ContentView para:
//   1) Reducir el tamaño de ContentView (era monolito 2987 líneas).
//   2) Permitir tests unitarios sin levantar @State/@AppStorage/@Query.
//   3) Reusar lógica desde Widgets y futuras vistas.
//
//  Las funciones son puras (sin side effects): toman snapshots de trips +
//  countries + features y devuelven el banner correspondiente.
//

import Foundation
import CoreLocation

/// Computa los datos del banner "Quedan X días" del modo mapa.
/// El banner muestra el próximo viaje futuro: bandera + nombre del país +
/// días hasta la fecha de inicio. Considera tanto países en `.wantToVisit`
/// con fecha programada como países `.visited` con trips futuros.
struct ProximosBannerData: Equatable {
    let days: Int
    let flag: String
    let name: String
    let isoCode: String
    let transport: String?
    let dateFrom: Date?
    let bookingRef: String
    let title: String?
}

/// Computa los datos del banner del modo vuelo: días al próximo vuelo +
/// IATA de salida. Análogo a ProximosBannerData pero solo para trips ✈️.
struct FlightCounterData: Equatable {
    let days: Int
    let depIATA: String
}

/// Ruta del próximo vuelo (origen → destino) con coordenadas para
/// dibujar la línea en el mapa de modo vuelo.
struct NextFlightRoute: Equatable {
    let depIATA: String
    let arrIATA: String
    let depCoord: CLLocationCoordinate2D
    let arrCoord: CLLocationCoordinate2D

    static func == (lhs: NextFlightRoute, rhs: NextFlightRoute) -> Bool {
        lhs.depIATA == rhs.depIATA && lhs.arrIATA == rhs.arrIATA &&
        lhs.depCoord.latitude == rhs.depCoord.latitude &&
        lhs.depCoord.longitude == rhs.depCoord.longitude &&
        lhs.arrCoord.latitude == rhs.arrCoord.latitude &&
        lhs.arrCoord.longitude == rhs.arrCoord.longitude
    }
}

enum BannerComputer {

    /// Banner del modo mapa: próximo viaje futuro.
    /// - `proximoRows`: filas Próximos pre-computadas (con `dateFrom`).
    /// - `trips`: lista completa para buscar trips futuros de países `.visited`.
    /// - `countries`: para checar `status` de cada país.
    /// - `features`: para obtener bandera + nombre localizado por ISO.
    /// - `now`: inyectable para tests. Por defecto Date() real.
    @MainActor
    static func nextProximosBanner(
        proximoRows: [ProximoRow],
        trips: [Trip],
        countries: [Country],
        features: [CountryFeature],
        now: Date = Date()
    ) -> ProximosBannerData? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var entries: [(days: Int, flag: String, name: String, isoCode: String, date: Date, transport: String?, dateFrom: Date?, trip: Trip?, title: String?)] = []
        // wantToVisit countries — earliest future trip
        for row in proximoRows where row.country.status == .wantToVisit {
            guard let date = row.dateFrom else { continue }
            let d = cal.startOfDay(for: date)
            guard d > today else { continue }
            let days = cal.dateComponents([.day], from: today, to: d).day ?? 0
            let flag = features.first(where: { $0.isoCode == row.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == row.isoCode })?.localizedName ?? row.country.name
            entries.append((days, flag, name, row.isoCode, d, row.transport, date, row.trip, row.rowTitle))
        }
        // visited countries with future trips
        for trip in trips where trip.isoCode != "" {
            let d = cal.startOfDay(for: trip.dateFrom)
            guard d >= today else { continue }
            guard countries.first(where: { $0.isoCode == trip.isoCode })?.status == .visited else { continue }
            let days = cal.dateComponents([.day], from: today, to: d).day ?? 0
            guard days > 0 else { continue }
            let flag = features.first(where: { $0.isoCode == trip.isoCode })?.flagEmoji ?? "🌐"
            let name = features.first(where: { $0.isoCode == trip.isoCode })?.localizedName ?? trip.isoCode
            entries.append((days, flag, name, trip.isoCode, d, trip.transport, trip.dateFrom, trip, trip.title))
        }
        guard let next = entries.sorted(by: { $0.date < $1.date }).first else { return nil }
        let ref = bookingRefFromTrip(next.trip)
        return ProximosBannerData(
            days: next.days, flag: next.flag, name: next.name, isoCode: next.isoCode,
            transport: next.transport, dateFrom: next.dateFrom, bookingRef: ref, title: next.title
        )
    }

    /// BookingRef del próximo trip (de su flightInfo / flightDetails).
    @MainActor
    static func bookingRefFromTrip(_ trip: Trip?) -> String {
        guard let trip else { return "" }
        if let seg = trip.tripSegments.first(where: { $0.transport == "✈️" }),
           let ref = seg.flightInfo?.bookingRef, !ref.isEmpty { return ref }
        return trip.flightDetails?.bookingRef ?? ""
    }

    /// Banner del modo vuelo: próximo trip ✈️ futuro → días + IATA salida.
    /// Considera tanto segments como trip.transport legacy.
    @MainActor
    static func nextFlightCounter(trips: [Trip], now: Date = Date()) -> FlightCounterData? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let candidates = trips.filter {
            !$0.isSegmentChild && cal.startOfDay(for: $0.dateFrom) >= today
        }.sorted { $0.dateFrom < $1.dateFrom }
        for trip in candidates {
            if let seg = trip.tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom })
                            .first(where: { $0.transport == "✈️" && ($0.airports?.count ?? 0) >= 1 }),
               let firstAp = seg.airports?.first {
                let days = cal.dateComponents([.day],
                    from: today,
                    to: cal.startOfDay(for: seg.dateFrom)).day ?? 0
                return FlightCounterData(days: max(0, days), depIATA: firstAp.iata)
            }
            if trip.tripSegments.isEmpty, trip.transport == "✈️",
               let firstAp = trip.tripAirports.first {
                let days = cal.dateComponents([.day],
                    from: today,
                    to: cal.startOfDay(for: trip.dateFrom)).day ?? 0
                return FlightCounterData(days: max(0, days), depIATA: firstAp.iata)
            }
        }
        return nil
    }

    /// Ruta del próximo vuelo (para dibujar línea en el mapa de modo vuelo).
    /// nil si no hay vuelo futuro o falta resolver coordenadas.
    @MainActor
    static func nextFlightRoute(trips: [Trip], now: Date = Date()) -> NextFlightRoute? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let candidates = trips.filter {
            !$0.isSegmentChild &&
            cal.startOfDay(for: $0.dateFrom) >= today
        }.sorted { $0.dateFrom < $1.dateFrom }
        for trip in candidates {
            if let seg = trip.tripSegments.sorted(by: { $0.dateFrom < $1.dateFrom })
                            .first(where: { $0.transport == "✈️" && ($0.airports?.count ?? 0) >= 2 }),
               let aps = seg.airports,
               let firstAp = aps.first,
               let lastAp = aps.last,
               let depCoord = AirportCoordinates.coordinate(for: firstAp.iata),
               let arrCoord = AirportCoordinates.coordinate(for: lastAp.iata) {
                return NextFlightRoute(depIATA: firstAp.iata, arrIATA: lastAp.iata,
                                       depCoord: depCoord, arrCoord: arrCoord)
            }
            if trip.tripSegments.isEmpty, trip.transport == "✈️", trip.tripAirports.count >= 2,
               let depCoord = AirportCoordinates.coordinate(for: trip.tripAirports[0].iata),
               let arrCoord = AirportCoordinates.coordinate(for: trip.tripAirports[1].iata) {
                return NextFlightRoute(depIATA: trip.tripAirports[0].iata,
                                       arrIATA: trip.tripAirports[1].iata,
                                       depCoord: depCoord, arrCoord: arrCoord)
            }
        }
        return nil
    }
}
