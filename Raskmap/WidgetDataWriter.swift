//
//  WidgetDataWriter.swift
//  Raskmap  ← target PRINCIPAL
//

import Foundation
import WidgetKit
import MapKit
import UIKit

private let appGroupID = "group.com.jaime.raskmap"

struct WidgetDataWriter {

    /// Store del App Group compartido con los widgets. Si la entitlement de
    /// AppGroups no está bien configurada (TestFlight provisioning, dev cert
    /// sin permisos, etc.) este `UserDefaults(suiteName:)` devuelve `nil` y
    /// TODAS las funciones de sync se vuelven no-op silenciosas → los widgets
    /// se quedan con datos stale sin pista del por qué.
    ///
    /// Logueamos UNA vez en DEBUG si el store falla al abrirse (es `static let`
    /// → se evalúa al primer uso del struct). En release no logueamos para no
    /// contaminar Console.app de usuarios reales.
    private static let store: UserDefaults? = {
        let s = UserDefaults(suiteName: appGroupID)
        #if DEBUG
        if s == nil {
            print("⚠️ WidgetDataWriter: UserDefaults(suiteName: \"\(appGroupID)\") devolvió nil. Widget sync será no-op. Revisa entitlement de AppGroups en project settings + provisioning profile.")
        }
        #endif
        return s
    }()

    static func sync(countries: [Country]) {
        guard let store else { return }

        let visitedIsoCodes = Set(countries
            .filter { $0.status == .visited || $0.status == .lived }
            .map { $0.isoCode })

        let un = visitedIsoCodes.filter {
            CountingMode.unMembers.contains($0)
        }.count

        let unPlus = visitedIsoCodes.filter {
            CountingMode.unMembers.contains($0) || CountingMode.unObservers.contains($0)
        }.count

        let all = visitedIsoCodes.count

        store.set(un,     forKey: "widget_visited_un")
        store.set(unPlus, forKey: "widget_visited_unPlus")
        store.set(all,    forKey: "widget_visited_all")

        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncColor(hex: String) {
        guard let store else { return }
        store.set(hex, forKey: "widget_bg_color")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncNextTrip(flag: String?, days: Int?, name: String? = nil,
                             transport: String? = nil, dateFrom: Date? = nil,
                             bookingRef: String? = nil, title: String? = nil) {
        guard let store else { return }
        store.set(flag ?? "", forKey: "widget_next_flag")
        store.set(days ?? -1, forKey: "widget_next_days")
        store.set(name ?? "", forKey: "widget_next_name")
        store.set(transport ?? "", forKey: "widget_next_transport")
        store.set(bookingRef ?? "", forKey: "widget_next_booking")
        store.set(title ?? "", forKey: "widget_next_title")
        if let d = dateFrom {
            store.set(d.timeIntervalSince1970, forKey: "widget_next_date")
        } else {
            store.removeObject(forKey: "widget_next_date")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncFontFamily(_ family: String) {
        guard let store else { return }
        store.set(family, forKey: "appFontFamily")
    }

    static func syncPro(_ isPro: Bool) {
        guard let store else { return }
        store.set(isPro, forKey: "widget_is_pro")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func syncCountingMode(_ mode: String) {
        guard let store else { return }
        store.set(mode, forKey: "widget_counting_mode")
    }

    static func syncAllFlags(_ flags: String) {
        guard let store else { return }
        store.set(flags, forKey: "widget_all_flags")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Flags de países visitados (pre-computadas como string). Hasta 12 emojis para caber en el widget grande.
    static func syncTopVisitedFlags(_ flags: String) {
        guard let store else { return }
        store.set(flags, forKey: "widget_top_visited_flags")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Snapshot del próximo vuelo

    private static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
    private static var flightSnapshotURL: URL? {
        sharedContainerURL?.appendingPathComponent("next_flight_map.png")
    }

    /// Snapshotter actualmente en curso. Si el usuario cambia de viaje 5 veces
    /// rápido (o se reentra en `handleTripsCountChange`), el callback async
    /// del previo se solaparía y podría escribir una imagen "vieja" sobre la
    /// "nueva". Mantenemos referencia para cancelar el anterior antes de
    /// arrancar uno nuevo.
    nonisolated(unsafe) private static var pendingSnapshotter: MKMapSnapshotter?

    /// Genera (en background) un snapshot del próximo vuelo con la línea
    /// gran-circular dibujada y lo guarda en el App Group para que el widget
    /// lo pueda cargar como `UIImage(contentsOfFile:)`.
    /// Pasar `nil` borra el snapshot existente (sin próximo vuelo).
    static func syncNextFlightSnapshot(depIATA: String?, arrIATA: String?, depCoord: CLLocationCoordinate2D?, arrCoord: CLLocationCoordinate2D?) {
        guard let url = flightSnapshotURL else { return }
        // Cancela cualquier snapshot en curso para evitar callbacks que escriban
        // imágenes obsoletas encima del último estado pedido.
        pendingSnapshotter?.cancel()
        pendingSnapshotter = nil
        guard let depCoord, let arrCoord, depIATA != nil, arrIATA != nil else {
            try? FileManager.default.removeItem(at: url)
            store?.set("", forKey: "widget_next_flight_dep_iata")
            store?.set("", forKey: "widget_next_flight_arr_iata")
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        store?.set(depIATA, forKey: "widget_next_flight_dep_iata")
        store?.set(arrIATA, forKey: "widget_next_flight_arr_iata")

        // Tamaño objetivo: el widget large iOS es ~360x380 pt; renderizamos a 2x.
        let pointSize = CGSize(width: 360, height: 360)
        let region = boundingRegion(for: depCoord, and: arrCoord)

        let opts = MKMapSnapshotter.Options()
        opts.region = region
        opts.size = pointSize
        opts.scale = 2
        opts.pointOfInterestFilter = .excludingAll
        opts.mapType = .mutedStandard

        let snapshotter = MKMapSnapshotter(options: opts)
        pendingSnapshotter = snapshotter
        snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, error in
            // Si ya no somos el snapshotter activo (cancelado o reemplazado),
            // descartamos el resultado para no sobrescribir imagen más reciente.
            guard pendingSnapshotter === snapshotter else { return }
            pendingSnapshotter = nil
            guard error == nil, let snapshot else { return }
            let composed = composeFlightImage(snapshot: snapshot, dep: depCoord, arr: arrCoord)
            if let data = composed.pngData() {
                try? data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    /// Encuadre que abarca dep + arr con padding lateral generoso para que la
    /// línea gran-circular nunca quede tangente al borde.
    private static func boundingRegion(for a: CLLocationCoordinate2D, and b: CLLocationCoordinate2D) -> MKCoordinateRegion {
        // Sample puntos a lo largo de una línea geodésica y calcula el bounding
        // box real — una línea recta lat/lng se desvía mucho de la trayectoria real
        // del avión y el snapshot saldría mal cuadrado.
        let coords = sampleGeodesic(from: a, to: b, samples: 64)
        var minLat =  90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        for c in coords {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Padding factor: 1.6 → la línea queda con holgura visible respecto al borde.
        let span = MKCoordinateSpan(
            latitudeDelta: max(2.0, (maxLat - minLat) * 1.6),
            longitudeDelta: max(2.0, (maxLon - minLon) * 1.6)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Linealización paramétrica de una línea geodésica (gran-círculo) entre dos
    /// puntos. Usa la fórmula slerp en coordenadas cartesianas y reproyecta.
    private static func sampleGeodesic(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, samples: Int) -> [CLLocationCoordinate2D] {
        let lat1 = a.latitude * .pi / 180,  lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180,  lon2 = b.longitude * .pi / 180
        let d = 2 * asin(sqrt(pow(sin((lat2 - lat1) / 2), 2)
                              + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)))
        guard d > 0 else { return [a, b] }
        var result: [CLLocationCoordinate2D] = []
        for i in 0...samples {
            let f = Double(i) / Double(samples)
            let A = sin((1 - f) * d) / sin(d)
            let B = sin(f * d) / sin(d)
            let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
            let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
            let z = A * sin(lat1) + B * sin(lat2)
            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi
            result.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        return result
    }

    private static func composeFlightImage(snapshot: MKMapSnapshotter.Snapshot, dep: CLLocationCoordinate2D, arr: CLLocationCoordinate2D) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext

            // Línea geodésica
            let coords = sampleGeodesic(from: dep, to: arr, samples: 96)
            let points = coords.map { snapshot.point(for: $0) }
            guard points.count >= 2 else { return }

            cg.setStrokeColor(UIColor(red: 0.25, green: 0.45, blue: 0.83, alpha: 0.95).cgColor)
            cg.setLineWidth(3.0)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.move(to: points[0])
            for p in points.dropFirst() { cg.addLine(to: p) }
            cg.strokePath()

            // Marcadores en cada extremo (anillo blanco + relleno cobalto)
            for p in [snapshot.point(for: dep), snapshot.point(for: arr)] {
                let outer = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
                let inner = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: outer)
                cg.setFillColor(UIColor(red: 0.25, green: 0.45, blue: 0.83, alpha: 1.0).cgColor)
                cg.fillEllipse(in: inner)
            }
        }
    }
}
