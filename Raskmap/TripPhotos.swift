//
//  TripPhotos.swift
//  Raskmap
//
//  Helpers para manejar las fotos de un Trip:
//   · Encode/decode del `[Data]` ↔ `Trip.photosData` (binary plist sin
//     base64 overhead, mucho más compacto que JSON).
//   · Resize de UIImage a un max width para no inflar el storage de
//     CloudKit (cada foto ~300-500KB tras resize en lugar de 3-5MB raw).
//   · Cap por trip — limit hard a 5 fotos.
//

import Foundation
import SwiftUI
import UIKit
import PhotosUI

extension Trip {
    /// Máximo de fotos por viaje. Mantener bajo para no saturar la fila
    /// de SwiftData ni el sync de CloudKit.
    static let maxPhotosPerTrip: Int = 5

    /// Tags decodificados desde `tagsRaw` (JSON array). Get / set
    /// transparente — vacío = nil para no inflar el storage de trips sin tags.
    var tags: [String] {
        get {
            guard let raw = tagsRaw,
                  let data = raw.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if cleaned.isEmpty {
                tagsRaw = nil
                return
            }
            if let data = try? JSONEncoder().encode(cleaned),
               let str = String(data: data, encoding: .utf8) {
                tagsRaw = str
            }
        }
    }

    /// Lista de fotos (JPEG `Data`) decodificadas desde `photosData`.
    /// Get / set transparente: el setter encoda como binary plist y
    /// escribe en `photosData`.
    var photos: [Data] {
        get {
            guard let raw = photosData, !raw.isEmpty else { return [] }
            let decoder = PropertyListDecoder()
            return (try? decoder.decode([Data].self, from: raw)) ?? []
        }
        set {
            if newValue.isEmpty {
                photosData = nil
                return
            }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            photosData = try? encoder.encode(newValue)
        }
    }

    /// Versión UIImage del array, perezosa. Útil para grids/scroll horizontal.
    var photoImages: [UIImage] {
        photos.compactMap { UIImage(data: $0) }
    }
}

enum TripPhotoProcessor {
    /// Tamaño máximo para resize (ancho/alto). Las fotos del Photos library
    /// suelen venir 4000+px → las bajamos a 1600 para que el JPEG quede
    /// alrededor de 300-500KB sin perder mucha calidad visual.
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.7

    /// Procesa un PHPickerItem → JPEG Data resized. Devuelve nil si la
    /// carga o el resize falla (foto borrada, formato no-imagen, etc.).
    static func processPickerItem(_ item: PhotosPickerItem) async -> Data? {
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: raw) else { return nil }
        return resizeAndJPEG(ui)
    }

    /// Resize a `maxDimension` manteniendo aspect ratio + re-encode JPEG.
    /// Si la imagen ya es más pequeña que max, solo re-encoda (sigue siendo
    /// útil para normalizar formato).
    static func resizeAndJPEG(_ image: UIImage) -> Data? {
        let size = image.size
        let scale: CGFloat = {
            let maxSide = max(size.width, size.height)
            return maxSide > maxDimension ? maxDimension / maxSide : 1.0
        }()
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }
}
