//
//  SettingsSheet.swift
//  Raskmap
//
//  Pantalla de Ajustes. 13 secciones aprox: perfil, modo de conteo,
//  tema/colores, widgets, recordatorios, legal, datos, contacto,
//  suscripción Pro, créditos, etc. La sheet más grande junto con
//  ProfileSheet — punto neurálgico de configuración.
//
//  Acceso a `raskmapProLifetimeID` cross-file (internal, en
//  SubscriptionSheet.swift) y a `confirmCardContent` (internal, en
//  PlannedDatePickerSheet.swift).
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI
import SwiftData
import UIKit
import StoreKit
import ActivityKit
import UserNotifications
import WidgetKit

// MARK: - Pantalla de ajustes
struct SettingsSheet: View {
    @Binding var username: String
    @Binding var selectedPassport: String
    @Binding var countingModeRaw: String
    @Binding var menuPositionRaw: String
    @Binding var showBucketList: Bool
    @AppStorage("showCountdown") private var showCountdown: Bool = true
    var onClearStatus: (CountryStatus) -> Void = { _ in }

    @State private var pendingClear: CountryStatus? = nil
    @State private var showWipeConfirm: Bool = false
    /// Feedback al reintentar sync del widget. Se muestra brevemente
    /// tras tappear "Reintentar sincronización" para confirmar al user
    /// que la acción se ejecutó.
    @State private var widgetSyncToast: String? = nil
    @State private var showWipeFinalConfirm: Bool = false
    @State private var isWiping: Bool = false
    @State private var showWipeDoneToast: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportFileURL: URL? = nil
    @State private var showImagePicker: Bool = false
    @State private var usernameDraft: String = ""
    @FocusState private var usernameFocused: Bool
    @State private var showContact: Bool = false
    @State private var showMultiContinent: Bool = false
    @State private var showMultiHemisphere: Bool = false

    @EnvironmentObject private var colorTheme: ColorThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showCountingToast: Bool = false
    @State private var showResetToast: Bool = false
    @State private var showFavoriteAirportPicker: Bool = false
    @State private var showSubscription: Bool = false
    @State private var showFAQ: Bool = false
    @State private var showNovedades: Bool = false
    @State private var showWidgetLockScreen: Bool = false
    @State private var showWidgetHome: Bool = false
    @State private var showWidgetWatch: Bool = false
    @State private var showLegalPrivacy: Bool = false
    @State private var showLegalTerms: Bool = false
    @State private var showLegalImprint: Bool = false
    @State private var showLegalGDPR: Bool = false
    @State private var showLegalCredits: Bool = false
    @AppStorage("isRaskmapPro") private var isRaskmapPro: Bool = false
    @AppStorage("raskmapProPlanID") private var raskmapProPlanID: String = ""
    @AppStorage("raskmapProByCode") private var raskmapProByCode: Bool = false
    @AppStorage("appFontFamily") private var appFontFamily: String = "satoshi"
    @State private var proCodeDraft: String = ""
    @State private var proCodeError: Bool = false
    @AppStorage("widgetBgColorHex") private var widgetBgColorHex: String = "#EE6E7D"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = false
    @AppStorage("tripRemindersEnabled") private var tripRemindersEnabled: Bool = false
    @AppStorage("multiHemisphereRaw") private var multiHemisphereRaw: String = "{}"

    @AppStorage("favoriteAirport") private var favoriteAirport: String = ""

    @State private var pendingVisitedColor: Color = ColorThemeManager.defaultVisited
    @State private var pendingWantToVisitColor: Color = ColorThemeManager.defaultWantToVisit
    @State private var pendingBucketListColor: Color = ColorThemeManager.defaultBucketList
    @State private var isApplyingColors: Bool = false
    /// Alert de confirmación antes de resetear los colores. Igual que el flujo
    /// de "Cambiar colores", el reset es destructivo (sobreescribe lo que el
    /// usuario tenía) y por eso ahora pasa por un paso explícito de confirmación.
    @State private var showResetColorsAlert: Bool = false

    private var countingMode: CountingMode { CountingMode(rawValue: countingModeRaw) ?? .all }

    @ViewBuilder private var proCodeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.caption)
                .foregroundStyle(.purple.opacity(0.6))
            TextField("Código de activación", text: $proCodeDraft)
                .font(.palatino(.body))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: proCodeDraft) { _, _ in proCodeError = false }
            if proCodeError {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Button("Activar") { activateProCode() }
                .font(.palatino(.footnote, weight: .bold))
                .foregroundStyle(proCodeDraft.isEmpty ? Color.secondary : Color.purple)
                .disabled(proCodeDraft.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func activateProCode() {
        if proCodeDraft.lowercased().trimmingCharacters(in: .whitespaces) == "alexelcapo" {
            isRaskmapPro = true
            raskmapProPlanID = raskmapProLifetimeID
            raskmapProByCode = true
            proCodeDraft = ""
            proCodeError = false
        } else {
            proCodeError = true
        }
    }

    @ViewBuilder private var proRowLabel: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill").font(.system(size: 13)).foregroundStyle(.purple)
                Text("Raskmap Pro").font(.palatino(.body, weight: .bold)).foregroundStyle(.purple)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.purple.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
    }

    @ViewBuilder private func settingsRowLocked(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: isRaskmapPro ? action : { showSubscription = true }) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.palatino(.body))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isRaskmapPro ? "chevron.right" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(isRaskmapPro ? Color.secondary : Color.purple)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func settingsRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.palatino(.body))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var favoriteAirportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selecciona tu aeropuerto favorito:")
                .font(.palatino(.subheadline, weight: .bold))
                .foregroundStyle(.secondary)
            Button { showFavoriteAirportPicker = true } label: {
                HStack {
                    if favoriteAirport.isEmpty {
                        Text("Ninguno")
                            .font(.palatino(.body))
                            .foregroundStyle(.secondary)
                    } else {
                        let apData = RoutePickerSheet.allAirports.first { $0.iata == favoriteAirport }
                        let apLabel = "\(favoriteAirport)\(apData.map { " – \($0.name)" } ?? "")"
                        HStack(spacing: 8) {
                            FlagLabel(emoji: apData?.flagEmoji ?? "🌐", size: 17)
                            Text("⭐️").font(.caption)
                            Text(apLabel)
                                .font(.palatino(.body))
                                .foregroundStyle(.primary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colores del mapa:")
                .font(.palatino(.subheadline, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            ZStack {
                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        ColorPickerRow(label: "Visitado", color: $pendingVisitedColor)
                        Divider().padding(.leading, 56)
                        ColorPickerRow(label: "Quiero", color: $pendingBucketListColor)
                        Divider().padding(.leading, 56)
                        ColorPickerRow(label: "Próximo", color: $pendingWantToVisitColor)
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    .padding(.horizontal, 24)
                    Button {
                        colorTheme.visitedColor = pendingVisitedColor
                        colorTheme.wantToVisitColor = pendingWantToVisitColor
                        colorTheme.bucketListColor = pendingBucketListColor
                        isApplyingColors = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(5))
                            isApplyingColors = false
                        }
                    } label: {
                        Text("Cambiar colores")
                            .font(.palatino(.body, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: Radius.cell))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .disabled(isApplyingColors)
                    Button {
                        showResetColorsAlert = true
                    } label: {
                        Text("Restablecer colores predeterminados")
                            .font(.palatino(.footnote, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: Radius.cell))
                    }
                    .padding(.horizontal, 24)
                    .disabled(isApplyingColors)
                    .alert("¿Restablecer colores predeterminados?", isPresented: $showResetColorsAlert) {
                        Button("Cancelar", role: .cancel) { }
                        Button("Restablecer", role: .destructive) {
                            pendingVisitedColor = ColorThemeManager.defaultVisited
                            pendingWantToVisitColor = ColorThemeManager.defaultWantToVisit
                            pendingBucketListColor = ColorThemeManager.defaultBucketList
                            colorTheme.resetToDefaults()
                            isApplyingColors = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(5))
                                isApplyingColors = false
                            }
                        }
                    } message: {
                        Text("Se descartará tu paleta personalizada y volverán los colores originales del mapa.")
                    }
                }
                .blur(radius: isRaskmapPro ? 0 : 6)
                .allowsHitTesting(isRaskmapPro)
                if !isRaskmapPro {
                    Button { showSubscription = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.purple)
                            Text("Función Pro")
                                .font(.palatino(.caption, weight: .bold))
                                .foregroundStyle(.purple)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Perfil: foto + nombre
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 16) {
                            Button { showImagePicker = true } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    PassportAvatarView(key: selectedPassport, height: 86)
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                        .background(Color(.systemBackground), in: Circle())
                                        .offset(x: 4, y: 4)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cambiar pasaporte")
                            .accessibilityHint("Abre el selector de pasaportes")

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Nombre de usuario")
                                    .font(.palatino(.caption, weight: .bold))
                                    .foregroundStyle(.secondary)
                                ZStack(alignment: .leading) {
                                    HStack(spacing: 2) {
                                        Text("@")
                                            .font(.palatino(.body, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text(usernameDraft.isEmpty ? "usuario" : usernameDraft)
                                            .font(.palatino(.body))
                                            .foregroundStyle(usernameDraft.isEmpty ? .tertiary : .primary)
                                        Button { usernameFocused = true } label: {
                                            Image(systemName: "pencil")
                                                .font(.callout)
                                                .foregroundStyle(.blue)
                                        }
                                        .accessibilityLabel("Editar nombre de usuario")
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: Radius.cell))
                                    TextField("", text: $usernameDraft)
                                        .font(.palatino(.body))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .focused($usernameFocused)
                                        .opacity(usernameFocused ? 1 : 0.01)
                                        .padding(10)
                                        .background(usernameFocused ? Color(.systemGray5) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.cell))
                                        .onChange(of: usernameDraft) {
                                            usernameDraft = String(usernameDraft.filter { $0.isLetter || $0.isNumber }.prefix(10))
                                        }
                                }
                                Text("Máx. 10 caracteres alfanuméricos")
                                    .font(.palatino(.caption))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // ── Raskmap Pro ──
                    if raskmapProPlanID != raskmapProLifetimeID {
                        VStack(spacing: 10) {
                            Button { showSubscription = true } label: { proRowLabel }
                                .buttonStyle(.plain)
                            proCodeRow
                        }
                        .padding(.horizontal, 24)
                    } else {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                    .fill(Color.purple.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.purple)
                            }
                            Text("Raskmap Pro")
                                .font(.palatino(.body, weight: .bold))
                                .foregroundStyle(.purple)
                            Spacer()
                            Text("Vitalicio ✓")
                                .font(.palatino(.footnote))
                                .foregroundStyle(.purple.opacity(0.7))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .padding(.horizontal, 24)
                    }

                    // Aeropuerto favorito
                    favoriteAirportSection

                    // Conteo de territorios
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conteo de territorios/países:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            ForEach(CountingMode.allCases, id: \.self) { mode in
                                let isSelected = countingMode == mode
                                Button {
                                    countingModeRaw = mode.rawValue
                                    showCountingToast = true
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.5))
                                        showCountingToast = false
                                    }
                                } label: {
                                    Text(mode.label)
                                        .font(.custom(isSelected ? "Satoshi-Bold" : "Satoshi-Regular", size: 13))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(
                                            isSelected
                                                ? Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255)
                                                : Color(.systemGray5),
                                            in: RoundedRectangle(cornerRadius: Radius.cell, style: .continuous)
                                        )
                                        .foregroundStyle(isSelected ? .white : .primary)
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                            }
                        }
                        VStack(spacing: 8) {
                            Button { showMultiContinent = true } label: {
                                HStack {
                                    Text("Países en más de un continente")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { showMultiHemisphere = true } label: {
                                HStack {
                                    Text("Países en más de un hemisferio")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Contador próximo viaje
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contador próximo viaje:")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundStyle(.primary)
                                    .frame(width: 20)
                                Text("Mostrar contador")
                                    .font(.palatino(.body))
                                Spacer()
                                ZStack {
                                    Toggle("", isOn: $showCountdown)
                                        .labelsHidden()
                                        .tint(.blue)
                                        .blur(radius: isRaskmapPro ? 0 : 6)
                                        .allowsHitTesting(isRaskmapPro)
                                    if !isRaskmapPro {
                                        Button { showSubscription = true } label: {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.purple)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            HStack {
                                Label("Live Activities", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.palatino(.body))
                                    .foregroundStyle(.primary)
                                Spacer()
                                ZStack {
                                    Toggle("", isOn: $liveActivityEnabled)
                                        .labelsHidden()
                                        .tint(.blue)
                                        .blur(radius: isRaskmapPro ? 0 : 6)
                                        .allowsHitTesting(isRaskmapPro)
                                    if !isRaskmapPro {
                                        Button { showSubscription = true } label: {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.purple)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            // Recordatorios de viaje (notificaciones locales) — gratis.
                            HStack {
                                Label("Recordatorios de viaje", systemImage: "bell")
                                    .font(.palatino(.body))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Toggle("", isOn: $tripRemindersEnabled)
                                    .labelsHidden()
                                    .tint(.blue)
                                    .onChange(of: tripRemindersEnabled) { _, enabled in
                                        Task {
                                            if enabled {
                                                let granted = await TripNotifications.requestAuthorization()
                                                if !granted {
                                                    await MainActor.run { tripRemindersEnabled = false }
                                                }
                                            } else {
                                                TripNotifications.cancelAll()
                                            }
                                        }
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                        Text("Si activas los recordatorios, recibirás avisos 7 días antes, el día anterior y el día del viaje.")
                            .font(.palatino(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24)

                    // Selección de colores
                    colorPickerSection

                    // Widgets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Widgets")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            settingsRow(label: "Pantalla principal", icon: "rectangle.grid.3x2") { showWidgetHome = true }
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            settingsRowLocked(label: "Pantalla de bloqueo", icon: "lock.display") { showWidgetLockScreen = true }
                            Rectangle().fill(Color(.separator)).frame(height: 0.5).padding(.leading, 16)
                            settingsRowLocked(label: "Apple Watch", icon: "applewatch") { showWidgetWatch = true }
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    }
                    .padding(.horizontal, 24)

                    // Ayuda
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ayuda")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            settingsRow(label: "Contacto", icon: "envelope") { showContact = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "FAQ", icon: "questionmark.circle") { showFAQ = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Novedades", icon: "sparkles") { showNovedades = true }
                            Divider().padding(.leading, 16)
                            Button {
                                // URLs literales pero protegidas con if-let por estilo.
                                guard let appURL = URL(string: "instagram://user?username=jaimeviajando"),
                                      let webURL = URL(string: "https://instagram.com/jaimeviajando") else { return }
                                if UIApplication.shared.canOpenURL(appURL) {
                                    UIApplication.shared.open(appURL)
                                } else {
                                    UIApplication.shared.open(webURL)
                                }
                            } label: {
                                HStack {
                                    Label("Instagram", systemImage: "camera")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("@jaimeviajando")
                                        .font(.palatino(.footnote))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    }
                    .padding(.horizontal, 24)

                    // Legal
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legal")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            settingsRow(label: "Política de privacidad", icon: "lock.shield") { showLegalPrivacy = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Términos de uso", icon: "doc.text") { showLegalTerms = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Aviso legal", icon: "building.columns") { showLegalImprint = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Tus derechos (RGPD)", icon: "person.badge.shield.checkmark") { showLegalGDPR = true }
                            Divider().padding(.leading, 16)
                            settingsRow(label: "Atribuciones", icon: "text.badge.checkmark") { showLegalCredits = true }
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                    }
                    .padding(.horizontal, 24)

                    // ── Datos: export + wipe (App Store / GDPR Art. 17/20) ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Datos")
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            // Exportar (GDPR Art. 20 — portabilidad)
                            Button {
                                showExportSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                    Text("Exportar mis datos")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                            // Reintentar sync del widget — útil si el widget en
                            // home/lock screen muestra datos stale (puede pasar
                            // tras instalar la app, cambios de entitlements, etc).
                            Button {
                                retryWidgetSync()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                    Text("Reintentar sincronización del widget")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if widgetSyncToast != nil {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.body).foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                            // Borrar (GDPR Art. 17 — derecho al olvido)
                            Button {
                                showWipeConfirm = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.red)
                                        .frame(width: 24)
                                    Text("Borrar todos mis datos")
                                        .font(.palatino(.body))
                                        .foregroundStyle(.red)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: Radius.cell))
                        Text("Exportar genera un JSON con tus países, viajes y preferencias para que puedas guardarlo o moverlo a otro dispositivo. Borrar elimina todo localmente; con iCloud activo, también se sincroniza el borrado.")
                            .font(.palatino(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24)

                    #if DEBUG
                    // ── Dev: simular planes Pro ──
                    VStack(spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { raskmapProPlanID == raskmapProLifetimeID && !raskmapProByCode },
                            set: { active in
                                isRaskmapPro = active
                                raskmapProPlanID = active ? raskmapProLifetimeID : ""
                                if active { raskmapProByCode = false }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: "wrench.and.screwdriver").foregroundStyle(.orange)
                                Text("Simular Pro vitalicio (DEV)")
                                    .font(.palatino(.footnote, weight: .bold)).foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 4)
                    #endif

                    Color.clear.frame(height: 32)
                }
                .padding(.top, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        let clean = String(usernameDraft.filter { $0.isLetter || $0.isNumber }.prefix(10))
                        if !clean.isEmpty { username = clean }
                        dismiss()
                    }
                    .font(.palatino(.body))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        colorTheme.isDarkMode.toggle()
                    } label: {
                        Image(systemName: colorTheme.isDarkMode ? "sun.max" : "moon")
                            .font(.body)
                    }
                }
            }
            .onAppear { usernameDraft = username }
            .alert("¿Eliminar datos?", isPresented: Binding(
                get: { pendingClear != nil },
                set: { if !$0 { pendingClear = nil } }
            )) {
                Button("Eliminar", role: .destructive) {
                    if let status = pendingClear {
                        if status == .bucketList { showBucketList = false }
                        onClearStatus(status)
                    }
                    pendingClear = nil
                }
                Button("Cancelar", role: .cancel) {
                    pendingClear = nil
                }
            } message: {
                Text("Se eliminarán todos los países de Bucket list. Esta acción no se puede deshacer.")
            }
            .sheet(isPresented: $showExportSheet) {
                ExportDataSheet(
                    countriesProvider: { fetchAllCountries() },
                    tripsProvider: { fetchAllTrips() }
                )
            }
            // Wipe completo (App Store / GDPR): paso 1 — aviso, paso 2 — confirmación final.
            .alert("¿Borrar todos tus datos?", isPresented: $showWipeConfirm) {
                Button("Continuar", role: .destructive) { showWipeFinalConfirm = true }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Vas a borrar TODOS los países, viajes, premios, listas y preferencias. Esta acción no se puede deshacer.")
            }
            .alert("Confirmación final", isPresented: $showWipeFinalConfirm) {
                Button("Sí, borrar todo", role: .destructive) {
                    Task { await wipeAllData() }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Última oportunidad. Si tienes iCloud activo los datos también se eliminarán de tu nube tras la siguiente sincronización.")
            }
            .overlay {
                if showCountingToast || showResetToast || showWipeDoneToast {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                        Text(showWipeDoneToast ? "Datos borrados" :
                             (showCountingToast ? "Conteo actualizado" : "Colores restablecidos"))
                            .font(.palatino(.subheadline, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.section))
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCountingToast)
            .animation(.easeInOut(duration: 0.2), value: showResetToast)
            .animation(.easeInOut(duration: 0.2), value: showWipeDoneToast)
        }
        .fullScreenCover(isPresented: $showImagePicker) {
            PassportPickerSheet(selection: $selectedPassport)
        }
        .sheet(isPresented: $showContact) {
            ContactSheet(username: username)
        }
        .sheet(isPresented: $showMultiContinent) {
            MultiContinentSheet()
        }
        .sheet(isPresented: $showMultiHemisphere) {
            MultiHemisphereSheet()
        }
        .sheet(isPresented: $showFavoriteAirportPicker) {
            FavoriteAirportPickerSheet(selected: $favoriteAirport)
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionSheet()
        }
        .sheet(isPresented: $showFAQ) {
            SettingsInfoSheet(title: "FAQ", icon: "questionmark.circle", content: "Aquí irán las preguntas frecuentes sobre Raskmap.\n\nPróximamente.")
        }
        .sheet(isPresented: $showNovedades) {
            SettingsInfoSheet(title: "Novedades", icon: "sparkles", content: "Aquí aparecerán las novedades de cada versión de Raskmap.\n\nPróximamente.")
        }
        .sheet(isPresented: $showWidgetLockScreen) {
            WidgetLockScreenSheet()
        }
        .sheet(isPresented: $showWidgetHome) {
            WidgetHomeColorSheet()
        }
        .sheet(isPresented: $showWidgetWatch) {
            WidgetWatchSheet()
        }
        .fullScreenCover(isPresented: $showLegalPrivacy) {
            LegalInfoSheet(
                title: "Política de privacidad",
                icon: "lock.shield",
                content: "Raskmap no recopila ningún dato personal fuera de tu dispositivo.\n\nTodos tus datos (países visitados, viajes, aeropuertos y preferencias) se almacenan localmente en tu dispositivo mediante SwiftData. Si tienes iCloud activado, se sincronizan de forma privada a través de tu propia cuenta de iCloud utilizando CloudKit (Apple Inc.). El desarrollador no tiene acceso a estos datos en ningún momento.\n\nNo compartimos información con terceros. Raskmap no incluye herramientas de análisis, publicidad ni seguimiento de ningún tipo. No se utilizan cookies, identificadores publicitarios ni SDKs externos.\n\nLas compras dentro de la aplicación (Raskmap Pro) se procesan exclusivamente a través de la App Store. El desarrollador no recibe ni almacena datos de pago; Apple gestiona la transacción conforme a su propia Política de Privacidad.\n\nEdad mínima recomendada: 13 años. Raskmap no está dirigida a menores de 13 años y no recopila conscientemente datos de esta franja de edad.\n\nRetención de datos: tus datos permanecen en tu dispositivo y/o tu iCloud mientras tú quieras conservarlos. Puedes eliminarlos en cualquier momento desde la propia aplicación o desinstalándola y borrando los datos asociados en Ajustes → [tu nombre] → iCloud.\n\nDerecho a reclamar: si resides en la Unión Europea, puedes presentar una reclamación ante la autoridad de control competente. En España, la Agencia Española de Protección de Datos (AEPD) — www.aepd.es.\n\nResponsable del tratamiento: Jaime Fernández Arenas (España)\nContacto: raskmap_soporte@icloud.com\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalTerms) {
            LegalInfoSheet(
                title: "Términos de uso",
                icon: "doc.text",
                content: "El uso de Raskmap implica la aceptación de estos términos.\n\nRaskmap es una aplicación de uso personal para el registro de viajes. El contenido introducido por el usuario (países, viajes, rutas, notas y preferencias) es de su exclusiva propiedad y permanece en su dispositivo y/o su cuenta de iCloud.\n\nEdad mínima de uso: 13 años, o la edad mínima equivalente exigida por la legislación de tu país para aceptar un contrato.\n\nLicencia de uso: la aplicación se distribuye mediante la App Store de Apple y queda sujeta, salvo indicación en contrario, al Acuerdo de Licencia de Usuario Final estándar de Apple (Apple Licensed Application End User License Agreement), disponible en https://www.apple.com/legal/internet-services/itunes/dev/stdeula/\n\nCompras dentro de la aplicación: Raskmap Pro se ofrece como pago único (no es una suscripción con renovación automática). Las condiciones de compra y devolución se rigen por los Términos y Condiciones de Apple y por la política de reembolsos de la App Store.\n\nResponsabilidad: la aplicación se proporciona «tal cual», sin garantías de ningún tipo, expresas o implícitas. El desarrollador no se hace responsable de pérdidas de datos derivadas de fallos del dispositivo, del servicio iCloud o de cambios en el sistema operativo, ni de daños directos o indirectos derivados del uso de la aplicación, en la máxima medida permitida por la legislación aplicable.\n\nModificaciones: el desarrollador se reserva el derecho a modificar, añadir o retirar funcionalidades, así como a interrumpir el servicio, con previo aviso razonable a través de la App Store.\n\nLey aplicable: legislación española y normativa de la Unión Europea.\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalImprint) {
            LegalInfoSheet(
                title: "Aviso legal",
                icon: "building.columns",
                content: "Desarrollador y responsable de la aplicación:\n\nJaime Fernández Arenas (persona física, particular)\nEspaña\n\nContacto: raskmap_soporte@icloud.com\n\nRaskmap es una aplicación independiente desarrollada a título individual. No pertenece a ninguna empresa ni entidad jurídica y no desarrolla una actividad comercial sujeta a inscripción en registros mercantiles.\n\nDistribución: Raskmap se distribuye exclusivamente a través de la App Store de Apple (Apple Inc., One Apple Park Way, Cupertino, CA 95014, EE. UU.). El uso de la aplicación queda sujeto al Acuerdo de Licencia de Usuario Final estándar de Apple.\n\nPropiedad intelectual: el nombre «Raskmap», su logotipo, interfaz y contenidos originales son propiedad del desarrollador. Los contenidos y datos de terceros se reconocen en el apartado «Atribuciones».\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalGDPR) {
            LegalInfoSheet(
                title: "Tus derechos (RGPD)",
                icon: "person.badge.shield.checkmark",
                content: "Como usuario en la Unión Europea, el Reglamento General de Protección de Datos (RGPD — Reglamento UE 2016/679) te otorga los siguientes derechos:\n\n· Acceso: puedes consultar en cualquier momento todos tus datos directamente en la app.\n\n· Rectificación: puedes editar o corregir cualquier dato desde la propia aplicación.\n\n· Supresión: puedes eliminar cualquier viaje o país visitado desde la app. Para eliminar todos los datos puedes desinstalar la aplicación y borrar los datos de iCloud desde Ajustes → [tu nombre] → iCloud → Gestionar almacenamiento.\n\n· Portabilidad: tus datos residen en tu dispositivo y/o tu cuenta de iCloud y permanecen bajo tu control en todo momento.\n\n· Limitación del tratamiento: dado que todos los datos se procesan localmente en tu dispositivo, no existe tratamiento de datos por parte del desarrollador.\n\n· Oposición: dado que no tratamos datos con fines comerciales ni de análisis, este derecho no aplica en el contexto de Raskmap.\n\n· Reclamación ante la autoridad de control: tienes derecho a presentar una reclamación ante la autoridad de protección de datos competente. En España, la Agencia Española de Protección de Datos (AEPD) — www.aepd.es.\n\nRaskmap no realiza perfilado automatizado ni toma de decisiones automatizadas sobre los usuarios. El desarrollador no transfiere datos fuera del Espacio Económico Europeo; el almacenamiento en iCloud depende de tu configuración personal con Apple.\n\nResponsable del tratamiento: Jaime Fernández Arenas (España)\nContacto: raskmap_soporte@icloud.com\n\nFecha de última actualización: abril de 2026."
            )
        }
        .fullScreenCover(isPresented: $showLegalCredits) {
            LegalInfoSheet(
                title: "Atribuciones",
                icon: "text.badge.checkmark",
                content: "Raskmap utiliza los siguientes recursos de terceros:\n\n· Datos geográficos: Natural Earth (naturalearthdata.com). Dominio público. Los polígonos de países se obtienen de su dataset vectorial de libre uso.\n\n· Fuente tipográfica: Satoshi, diseñada por Deni Anggara y distribuida bajo licencia libre a través de Fontshare (Indian Type Foundry).\n\n· Datos de fronteras adicionales: geo-countries (github.com/datasets/geo-countries), Open Database License (ODbL).\n\n· Datos de aeropuertos IATA: recopilación propia basada en fuentes públicas.\n\n· Cartografía y tiles de mapa: MapKit y Apple Maps, © Apple Inc. y sus proveedores. Los créditos y enlaces legales correspondientes se muestran en el propio mapa.\n\n· Iconos de interfaz: SF Symbols, © Apple Inc. Uso sujeto a la licencia de SF Symbols de Apple.\n\n· Iconos de banderas: Twemoji, originalmente © Twitter Inc. / X Corp. y mantenido actualmente por la comunidad en github.com/jdecked/twemoji. Distribuido bajo licencia CC-BY 4.0 (creativecommons.org/licenses/by/4.0). Los gráficos de las banderas no han sido modificados.\n\n· Almacenamiento y sincronización: SwiftData y CloudKit, © Apple Inc.\n\n· Procesamiento de pagos y entrega: App Store / StoreKit, © Apple Inc.\n\nTodos los demás componentes de la aplicación son de desarrollo propio y no incorporan librerías de terceros.\n\nFecha de última actualización: abril de 2026."
            )
        }
        .overlay {
            if isApplyingColors {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.4)
                            .tint(.white)
                        Text("Actualizando colores…")
                            .font(.palatino(.body, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.sheet))
                }
            }
        }
        .onAppear {
            pendingVisitedColor = colorTheme.visitedColor
            pendingWantToVisitColor = colorTheme.wantToVisitColor
            pendingBucketListColor = colorTheme.bucketListColor
        }
        .appColorScheme()
    }

    /// Re-ejecuta todas las syncs al App Group del widget. Útil cuando el
    /// widget muestra datos stale tras instalar la app, cambios de
    /// entitlement o problemas de sync. Da feedback visual con un checkmark
    /// verde durante 2s en la fila.
    private func retryWidgetSync() {
        let countries = fetchAllCountries()
        WidgetDataWriter.sync(countries: countries)
        WidgetDataWriter.syncCountingMode(countingMode.rawValue)
        WidgetCenter.shared.reloadAllTimelines()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        widgetSyncToast = "ok"
        // Limpia el feedback visual tras 2s para que el icono vuelva al chevron.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            widgetSyncToast = nil
        }
    }

    private func fetchAllCountries() -> [Country] {
        modelContext.fetchOrWarn(FetchDescriptor<Country>())
    }
    private func fetchAllTrips() -> [Trip] {
        modelContext.fetchOrWarn(FetchDescriptor<Trip>())
    }

    /// Borra todos los datos persistidos del usuario (cumplimiento App Store
    /// y GDPR Art. 17 — derecho al olvido). Limpia SwiftData, AppStorage,
    /// cualquier preferencia local y el estado del widget en App Group.
    /// CloudKit se sincroniza automáticamente por @Query y borra remoto.
    private func wipeAllData() async {
        await MainActor.run {
            isWiping = true
            // 1) SwiftData
            do {
                try modelContext.delete(model: Trip.self)
                try modelContext.delete(model: Country.self)
                try modelContext.delete(model: PersonalAwardModel.self)
                try modelContext.save()
            } catch {
                #if DEBUG
                print("⚠️ Wipe SwiftData error: \(error)")
                #endif
            }
            // 2) AppStorage / UserDefaults estándar
            let defaults = UserDefaults.standard
            let keysToWipe: [String] = [
                "username", "didShowOnboarding", "didShowLocationToast",
                "showBucketList", "showCountdown",
                "topTable", "multiContinentRaw", "multiHemisphereRaw",
                "appFontFamily", "favoriteAirport", "isRaskmapPro", "raskmapProPlanID",
                "raskmapProByCode", "mapQuadrantsData", "didInsertDefaultQuadrants",
                "earnedPassportAchievementsRaw", "liveActivityEnabled", "neverShowReview",
                "selectedPassport", "personalList1Title", "personalList1Content",
                "personalList2Title", "personalList2Content",
                "subjectiveCategoriesTable", "subjectiveCategoriesOrder",
                "color_visited", "color_wantToVisit", "color_bucketList", "color_lived",
                "widgetBgColorHex", "menuPosition", "countingMode",
                "tripRemindersEnabled"
            ]
            for k in keysToWipe { defaults.removeObject(forKey: k) }
            // 3) App Group del widget
            if let store = UserDefaults(suiteName: "group.com.jaime.raskmap") {
                for key in store.dictionaryRepresentation().keys {
                    store.removeObject(forKey: key)
                }
            }
            // 4) Snapshot del mapa de vuelo en disco (si existe)
            if let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.jaime.raskmap")?
                .appendingPathComponent("next_flight_map.png") {
                try? FileManager.default.removeItem(at: url)
            }
            // 5) Live Activities activas
            if #available(iOS 16.1, *) {
                Task { @MainActor in
                    for activity in Activity<RaskmapTripAttributes>.activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
            }
            // 6) Notificaciones locales
            TripNotifications.cancelAll()
            isWiping = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showWipeDoneToast = true }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run {
            withAnimation { showWipeDoneToast = false }
            dismiss()
        }
    }
}
