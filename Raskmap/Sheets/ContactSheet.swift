//
//  ContactSheet.swift
//  Raskmap
//
//  Sheet de Contacto y wrapper UIViewControllerRepresentable para
//  MFMailComposeViewController. Self-contained — solo necesita un
//  `username: String` como input.
//
//  Extraídos de ContentView.swift durante Fase D.
//

import SwiftUI
import UIKit
import MessageUI

// MARK: - Contacto
struct MailComposerView: UIViewControllerRepresentable {
    let toRecipients: [String]
    let subject: String
    let body: String
    @Binding var isPresented: Bool
    var onFinish: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(toRecipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.isPresented = false
            parent.onFinish()
        }
    }
}

struct ContactSheet: View {
    let username: String
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var showMailComposer = false
    @FocusState private var editorFocused: Bool

    private let maxChars = 600
    private let accent = BrandColor.accent
    private var subject: String { "Solicitud de \(username.isEmpty ? "usuario" : username)" }
    private var trimmed: String { messageText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Header con icono + texto
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(accent.opacity(0.12)).frame(width: 44, height: 44)
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Escríbenos")
                                .font(.custom("Satoshi-Bold", size: 18))
                            Text("Cuéntanos qué falta o qué falla. Leemos cada mensaje.")
                                .font(.palatino(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    // Recipient pill (read-only) — destinatario visible
                    HStack(spacing: 10) {
                        Text("PARA")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)
                        Text("raskmap_soporte@icloud.com")
                            .font(.custom("Satoshi-Medium", size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Subject pill — asunto pre-rellenado
                    HStack(spacing: 10) {
                        Text("ASUNTO")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(subject)
                            .font(.custom("Satoshi-Medium", size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Editor del mensaje — body
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MENSAJE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(editorFocused ? accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                )
                            if messageText.isEmpty {
                                Text("Hola, me gustaría reportar…\n\n· Bug encontrado:\n· Aeropuerto/aerolínea que falta:\n· Sugerencia:")
                                    .font(.palatino(.body))
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $messageText)
                                .font(.palatino(.body))
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .focused($editorFocused)
                                .frame(minHeight: 200)
                                .onChange(of: messageText) { _, new in
                                    if new.count > maxChars { messageText = String(new.prefix(maxChars)) }
                                }
                        }
                        HStack {
                            Spacer()
                            Text("\(messageText.count)/\(maxChars)")
                                .font(.custom("Satoshi-Medium", size: 11))
                                .foregroundStyle(messageText.count >= maxChars ? .red : .secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)

                    // Botón Enviar
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            showMailComposer = true
                        } else {
                            // Encoding tight para mailto: query — `&`, `=`, `?`, `#` y `+`
                            // se reservan como separadores y rompen el parser del cliente
                            // de correo si aparecen sin codificar dentro del subject/body.
                            var allowed = CharacterSet.urlQueryAllowed
                            allowed.remove(charactersIn: "&=?#+")
                            let s = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                            let b = messageText.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                            if let url = URL(string: "mailto:raskmap_soporte@icloud.com?subject=\(s)&body=\(b)") {
                                UIApplication.shared.open(url)
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                            Text("Enviar mensaje").font(.custom("Satoshi-Bold", size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(trimmed.isEmpty ? Color(.systemGray4) : accent,
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(trimmed.isEmpty)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 24)
                }
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Contacto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }.font(.palatino(.body))
                }
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposerView(
                    toRecipients: ["raskmap_soporte@icloud.com"],
                    subject: subject,
                    body: messageText,
                    isPresented: $showMailComposer,
                    onFinish: { dismiss() }
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .appColorScheme()
    }
}
