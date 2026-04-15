//
//  SplashView.swift
//  Raskmap
//

import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.88
    @State private var globeOffset: CGFloat = 12

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0x3A/255, green: 0x91/255, blue: 0xF0/255),
                    Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 20) {
                    Text("🌍")
                        .font(.system(size: 56))
                        .offset(y: globeOffset)
                        .opacity(opacity)
                    Text("Raskmap")
                        .font(.custom("Satoshi-Bold", size: 52))
                        .foregroundStyle(.white)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                        opacity = 1
                        scale = 1
                        globeOffset = 0
                    }
                }
                Spacer()
            }

            VStack(spacing: 4) {
                Spacer()
                let year = Calendar.current.component(.year, from: Date())
                Text("v.1.0  ·  \(String(year))")
                    .font(.custom("Satoshi-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Todos los derechos reservados")
                    .font(.custom("Satoshi-Regular", size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 48)
            }
            .opacity(opacity)
        }
    }
}
