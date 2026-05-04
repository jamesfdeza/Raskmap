//
//  SplashView.swift
//  Raskmap
//

import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.85
    @State private var pinScale: Double = 0.7
    @State private var pinDrop: CGFloat = -28

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0x12/255, green: 0x1B/255, blue: 0x3A/255),
                    Color(red: 0x1E/255, green: 0x33/255, blue: 0x6A/255),
                    Color(red: 0x40/255, green: 0x6E/255, blue: 0xC9/255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Glow halo behind the pin — gives the cobalt accent room to breathe.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0x6A/255, green: 0xA8/255, blue: 1.0).opacity(0.55),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 220
                    )
                )
                .frame(width: 460, height: 460)
                .blur(radius: 30)
                .opacity(opacity * 0.85)

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            .frame(width: 132, height: 132)
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            .frame(width: 168, height: 168)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.white)
                            .scaleEffect(pinScale)
                            .offset(y: pinDrop)
                    }
                    .opacity(opacity)

                    VStack(spacing: 6) {
                        Text("RASKMAP")
                            .font(.custom("Satoshi-Bold", size: 38))
                            .tracking(8)
                            .foregroundStyle(.white)
                            .scaleEffect(scale)
                            .opacity(opacity)
                        Text("Tu mundo, en un mapa")
                            .font(.custom("Satoshi-Regular", size: 13))
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.6))
                            .opacity(opacity)
                    }
                }
                .onAppear {
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.05)) {
                        opacity = 1
                        scale = 1
                    }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.15)) {
                        pinScale = 1
                        pinDrop = 0
                    }
                }
                Spacer()
            }

            VStack(spacing: 4) {
                Spacer()
                let year = Calendar.current.component(.year, from: Date())
                Text("v.1.0  ·  \(String(year))")
                    .font(.custom("Satoshi-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Todos los derechos reservados")
                    .font(.custom("Satoshi-Regular", size: 11))
                    .foregroundStyle(.white.opacity(0.32))
                    .padding(.bottom, 48)
            }
            .opacity(opacity)
        }
    }
}
