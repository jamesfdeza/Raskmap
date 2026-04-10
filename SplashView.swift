//
//  SplashView.swift
//  Raskmap
//

import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.85

    var body: some View {
        ZStack {
            Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255)
                .ignoresSafeArea()

            Text("Raskmap")
                .font(.custom("Satoshi-Bold", size: 52))
                .foregroundStyle(.white)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.5)) {
                        opacity = 1
                        scale = 1
                    }
                }

            VStack(spacing: 4) {
                Spacer()
                let year = Calendar.current.component(.year, from: Date())
                Text("\(String(year))–\(String(year + 1))")
                    .font(.custom("Satoshi-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                Text("v.1.0")
                    .font(.custom("Satoshi-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Todos los derechos reservados")
                    .font(.custom("Satoshi-Regular", size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 48)
            }
            .opacity(opacity)
        }
    }
}
