//
//  FlightModeTransition.swift
//  Raskmap
//
//  Pantalla de carga full-screen al alternar modo vuelos / mapa.
//

import SwiftUI

struct FlightModeTransition: View {
    let toFlightMode: Bool

    @State private var planeProgress: CGFloat = 0
    @State private var trailProgress: CGFloat = 0
    @State private var iconOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.7
    @State private var pulseScale: CGFloat = 0.35
    @State private var pulseOpacity: Double = 0

    private let accent = BrandColor.accent

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if toFlightMode { airplaneBody } else { mapBody }
        }
        .onAppear(perform: runAnimation)
    }

    private var airplaneBody: some View {
        GeometryReader { geo in
            let lineY = geo.size.height / 2
            let startX: CGFloat = geo.size.width * 0.17
            let endX: CGFloat = geo.size.width * 0.83
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: startX, y: lineY))
                    p.addLine(to: CGPoint(x: endX, y: lineY))
                }
                .trim(from: 0, to: trailProgress)
                .stroke(accent.opacity(0.32),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 6]))

                Image(systemName: "airplane")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(accent)
                    .position(x: startX + (endX - startX) * planeProgress, y: lineY)
                    .opacity(iconOpacity)
            }
        }
    }

    private var mapBody: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(accent.opacity(0.35), lineWidth: 1.2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseScale + CGFloat(i) * 0.18)
                    .opacity(pulseOpacity)
            }
            Image(systemName: "map.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(accent)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
        }
    }

    private func runAnimation() {
        if toFlightMode {
            withAnimation(.easeOut(duration: 0.28)) { iconOpacity = 1 }
            withAnimation(.easeInOut(duration: 1.35).delay(0.18)) {
                planeProgress = 1
                trailProgress = 1
            }
            withAnimation(.easeIn(duration: 0.28).delay(1.65)) { iconOpacity = 0 }
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                iconScale = 1
                iconOpacity = 1
            }
            withAnimation(.easeOut(duration: 1.35).delay(0.2)) { pulseScale = 1.75 }
            withAnimation(.easeInOut(duration: 0.5).delay(0.2)) { pulseOpacity = 0.9 }
            withAnimation(.easeIn(duration: 0.7).delay(0.9)) { pulseOpacity = 0 }
            withAnimation(.easeIn(duration: 0.28).delay(1.65)) { iconOpacity = 0 }
        }
    }
}
