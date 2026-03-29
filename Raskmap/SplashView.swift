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
            // Fondo verde del icono
            Color(red: 0.18, green: 0.74, blue: 0.35)
                .ignoresSafeArea()

            Text("Raskmap")
                .font(.custom("Palatino-Bold", size: 52))
                .foregroundStyle(.white)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    opacity = 1
                    scale = 1
                }
            }
        }
    }
}
