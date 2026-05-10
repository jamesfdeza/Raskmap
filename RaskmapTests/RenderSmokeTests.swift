//
//  RenderSmokeTests.swift
//  RaskmapTests
//
//  Smoke tests "render-no-crash" para layouts críticos.
//  Verifican que `ImageRenderer` produce una UIImage no-nil con dimensiones
//  esperadas. No es snapshot diffing real (requiere swift-snapshot-testing
//  como dep), pero atrapa regresiones tipo "la vista hace crash al renderizar"
//  o "ImageRenderer devuelve nil por layout inválido".
//

import Testing
import SwiftUI
import UIKit
@testable import Raskmap

@MainActor
struct RenderSmokeTests {

    /// Helper que renderiza una View a UIImage usando ImageRenderer.
    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844)) -> UIImage? {
        let sized = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: sized)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = false
        return renderer.uiImage
    }

    @Test("FlagLabel renderiza sin crash con bandera estándar")
    func flagLabelRenders() {
        let view = FlagLabel(emoji: "🇪🇸", size: 32)
        #expect(render(view, size: CGSize(width: 64, height: 64)) != nil)
    }

    @Test("FlagLabel con fallback (🌐) renderiza con mismas dimensiones")
    func flagLabelFallbackRenders() {
        let view = FlagLabel(emoji: "🌐", size: 32)
        let img = render(view, size: CGSize(width: 64, height: 64))
        #expect(img != nil)
        // Mismo bounding box que la versión Twemoji (frame fixed).
        #expect(img?.size.width == 64)
    }

    @Test("TwemojiFlag con ISO inválido cae a fallback sin crashear")
    func twemojiInvalidISO() {
        let view = TwemojiFlag(iso2: "XX", size: 32, fallbackEmoji: "🌐")
        #expect(render(view, size: CGSize(width: 64, height: 64)) != nil)
    }

    @Test("FlightInfo Codable round-trip preserva estructura completa")
    func flightInfoCodableRoundTrip() throws {
        var info = FlightInfo()
        info.bookingRef = "ABC123"
        info.outboundLegs = [
            FlightLegInfo(seatNumber: "12A", seatPosition: "ventana", cabinClass: "turista"),
            FlightLegInfo(seatNumber: "5C", seatPosition: "pasillo", cabinClass: "business")
        ]
        info.returnLegs = [
            FlightLegInfo(seatNumber: "20B", seatPosition: "medio", cabinClass: "turista")
        ]
        let encoded = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(FlightInfo.self, from: encoded)
        #expect(decoded.bookingRef == "ABC123")
        #expect(decoded.outboundLegs.count == 2)
        #expect(decoded.outboundLegs[0].seatNumber == "12A")
        #expect(decoded.outboundLegs[1].cabinClass == "business")
        #expect(decoded.returnLegs.count == 1)
        #expect(decoded.returnLegs[0].seatPosition == "medio")
    }

    @Test("FlightInfo legacy (escalares only) decodifica con campos faltantes")
    func flightInfoLegacyDecode() throws {
        // JSON simulando datos antiguos sin outboundLegs/returnLegs.
        let legacyJSON = """
        {
            "bookingRef": "OLD123",
            "seatNumber": "1A",
            "seatPosition": "ventana",
            "cabinClass": "first"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FlightInfo.self, from: legacyJSON)
        #expect(decoded.bookingRef == "OLD123")
        #expect(decoded.seatNumber == "1A")
        #expect(decoded.outboundLegs.isEmpty)
        #expect(decoded.returnLegs.isEmpty)
        // allLegs sintetiza un leg desde escalares.
        #expect(decoded.allLegs.count == 1)
        #expect(decoded.allLegs.first?.seatNumber == "1A")
    }

    @Test("FlightInfo hasAnyData detecta correctamente los 3 paths")
    func flightInfoHasAnyData() {
        var info = FlightInfo()
        #expect(info.hasAnyData == false)
        info.bookingRef = "X"
        #expect(info.hasAnyData == true)
        info.bookingRef = ""
        info.outboundLegs = [FlightLegInfo(seatNumber: "12A")]
        #expect(info.hasAnyData == true)
        info.outboundLegs = []
        info.returnLegs = [FlightLegInfo(cabinClass: "business")]
        #expect(info.hasAnyData == true)
    }

    @Test("FlightLegInfo hasAnyData con seat empty cabin empty")
    func legInfoEmpty() {
        let leg = FlightLegInfo()
        #expect(leg.hasAnyData == false)
    }
}
