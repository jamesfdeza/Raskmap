//
//  SubscriptionSheet.swift
//  Raskmap
//
//  Sheet de Raskmap Pro. Maneja la compra StoreKit 2 + Restore Purchases.
//  Self-contained — usa @AppStorage para sincronizar el estado Pro entre
//  la app principal y el widget. Las IDs de producto y la lista de
//  productos están definidas en el header del archivo.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import StoreKit


// MARK: - Raskmap Pro
// IDs de producto en App Store Connect.
// `internal` (default access) para que ContentView pueda leerlos al hacer
// matching contra `raskmapProPlanID` desde su SettingsSheet inline.
let raskmapProLifetimeID = "com.raskmap.pro.lifetime"
let raskmapProAllIDs     = [raskmapProLifetimeID]

struct SubscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("raskmapProPlanID") private var raskmapProPlanID: String = ""
    @AppStorage("raskmapProByCode") private var raskmapProByCode: Bool = false

    @State private var lifetimeProduct: Product? = nil
    @State private var isLoading: Bool = true
    @State private var purchasingID: String? = nil
    @State private var isActivePro: Bool = false
    @State private var errorMessage: String? = nil

    private var isPurchasing: Bool { purchasingID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {

                    // Hero
                    VStack(spacing: 14) {
                        Text("✈️")
                            .font(.system(size: 64))
                        Text("Raskmap Pro")
                            .font(.palatino(.largeTitle, weight: .bold))
                            .foregroundStyle(.purple)
                        Text("Apoya el desarrollo de Raskmap\ny desbloquea funciones exclusivas")
                            .font(.palatino(.body))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 36)

                    // Beneficios
                    VStack(alignment: .leading, spacing: 18) {
                        proBenefitRow(icon: "map.fill",              text: "Exportación de tu mapa y listas personalizadas")
                        proBenefitRow(icon: "chart.bar.fill",        text: "Estadísticas avanzadas de transportes")
                        proBenefitRow(icon: "trophy.fill",           text: "Sistema de logros")
                        proBenefitRow(icon: "globe.americas.fill",   text: "Ve tu porcentaje del mundo visitado")
                        proBenefitRow(icon: "timer",                 text: "Cuentas atrás y Live Activities")
                        proBenefitRow(icon: "paintpalette.fill",     text: "Personaliza tu mapa con colores")
                        proBenefitRow(icon: "crown.fill",            text: "Insignia Pro")
                        proBenefitRow(icon: "heart.fill",            text: "Apoyas el desarrollo independiente")
                    }
                    .padding(.horizontal, 36)

                    // Estado / botones
                    if isLoading {
                        ProgressView()
                            .padding(.top, 8)
                    } else if isActivePro {
                        VStack(spacing: 16) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.purple)
                            VStack(spacing: 6) {
                                Text("Pro activo")
                                    .font(.palatino(.title3, weight: .bold))
                                    .foregroundStyle(.purple)
                                Text("Pago único · Vitalicio")
                                    .font(.palatino(.subheadline))
                                    .foregroundStyle(.secondary)
                            }
                            Text("¡Gracias por apoyar Raskmap!")
                                .font(.palatino(.body))
                                .foregroundStyle(.secondary)

                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            purchaseButton(
                                product: lifetimeProduct,
                                productID: raskmapProLifetimeID,
                                label: lifetimeProduct.map { "Pago único · \($0.displayPrice)" } ?? "Pago único · 3,99 €",
                                isProminent: true
                            )

                            Button {
                                Task { await restorePurchases() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Restaurar compras")
                                        .font(.palatino(.body, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.purple.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.purple)
                            }
                            .buttonStyle(.plain)
                            .disabled(isPurchasing)
                            .accessibilityLabel("Restaurar compras anteriores")
                            .accessibilityHint("Verifica con tu Apple ID si ya compraste Raskmap Pro previamente")
                        }
                        .padding(.horizontal, 32)

                        if let error = errorMessage {
                            Text(error)
                                .font(.palatino(.caption))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }

                    // Legal
                    Text("El pago único desbloquea Pro de forma permanente.")
                        .font(.palatino(.caption2))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 48)
                }
            }
            .navigationTitle("Raskmap Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .font(.palatino(.body))
                }
            }
        }
        .appColorScheme()
        .task {
            await loadProducts()
            await checkProStatus()
        }
    }

    @ViewBuilder
    private func purchaseButton(product: Product?, productID: String, label: String, isProminent: Bool) -> some View {
        Button {
            Task { await purchase(productID: productID, product: product) }
        } label: {
            Group {
                if purchasingID == productID {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(label)
                        .font(.palatino(.body, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                (isPurchasing || product == nil) ? Color.purple.opacity(0.4) : Color.purple,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || product == nil)
    }

    @ViewBuilder
    private func proBenefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.purple)
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(.palatino(.body))
                .foregroundStyle(.primary)
        }
    }

    private func loadProducts() async {
        isLoading = true
        do {
            let products = try await Product.products(for: raskmapProAllIDs)
            lifetimeProduct = products.first { $0.id == raskmapProLifetimeID }
            if lifetimeProduct == nil {
                errorMessage = "El producto no está disponible todavía."
            }
        } catch {
            errorMessage = "No se pudieron cargar las opciones. Comprueba tu conexión."
        }
        isLoading = false
    }

    private func checkProStatus() async {
        #if DEBUG
        if isRaskmapPro { isActivePro = true; return }
        #endif
        guard !raskmapProByCode else { isActivePro = true; return }
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == raskmapProLifetimeID {
                found = true
                break
            }
        }
        isActivePro = found
        isRaskmapPro = found
        raskmapProPlanID = found ? raskmapProLifetimeID : ""
    }

    private func purchase(productID: String, product: Product?) async {
        guard let product else { return }
        purchasingID = productID
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(_) = verification {
                    await checkProStatus()
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Compra pendiente de aprobación parental."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Error al procesar el pago. Inténtalo de nuevo."
        }
        purchasingID = nil
    }

    private func restorePurchases() async {
        purchasingID = raskmapProLifetimeID // bloquea UI
        errorMessage = nil
        do {
            try await AppStore.sync()
            await checkProStatus()
            if !isActivePro {
                errorMessage = "No se encontró ninguna compra anterior."
            }
        } catch {
            errorMessage = "No se pudieron restaurar las compras."
        }
        purchasingID = nil
    }
}
