//
//  CloudKitSharing.swift
//  Raskmap
//
//  Helper para compartir un "mapa de viajes" con amigos vía CKShare
//  (CloudKit). Diferenciador de producto: el receptor ve un snapshot
//  de tu mapa actual con tus países visitados, próximos y stats.
//
//  Estado: **scaffold básico** — el flujo full (CKShare + custom zone
//  + accept invitations) requiere varias semanas de trabajo serio. Lo
//  que sí incluye este archivo:
//  · `CloudKitSharing.shareSnapshot(...)`: genera un CKRecord con los
//    datos del usuario (visited isos, trips count, etc.) y lo
//    comparte vía UICloudSharingController.
//  · `RaskmapSnapshot` struct codificable que sirve como payload.
//
//  Lo que falta para producción:
//  · Receptor: handler de aceptar invitación + viewer de "mapa de un
//    amigo" (read-only, paneable).
//  · UI en perfil: botón "Compartir mi mapa con un amigo".
//  · Leaderboard: ranking entre amigos por países/vuelos.
//  · Política de privacidad actualizada (opt-in explícito GDPR).
//
//  Plan completo en docs/ROADMAP_OPTIONAL_FEATURES.md sección 4.
//

import Foundation
import CloudKit
import UIKit

/// Snapshot estático del mapa del usuario para compartir. NO se sincroniza
/// en tiempo real — es un "polaroid" en el momento de generar el share.
struct RaskmapSnapshot: Codable {
    let username: String
    let visitedIsoCodes: [String]
    let plannedIsoCodes: [String]
    let totalTrips: Int
    let totalCountries: Int
    let totalKmFlown: Int
    let createdAt: Date

    /// Serializa a JSON Data para guardar en CKRecord como CKAsset o Data.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    static func decode(from data: Data) -> RaskmapSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RaskmapSnapshot.self, from: data)
    }
}

enum CloudKitSharing {

    /// Container CloudKit (mismo que SwiftData usa). Para shared records
    /// debe coincidir con el del schema actual.
    private static let containerID = "iCloud.RealDev.Raskmap"

    /// Genera un CKShare para el snapshot y presenta el
    /// UICloudSharingController desde el VC actual.
    ///
    /// Llamada típica desde el botón "Compartir mi mapa" en Profile:
    ///
    ///     CloudKitSharing.shareSnapshot(snapshot) { result in
    ///         switch result {
    ///         case .success(let share): print("Share URL: \(share.url)")
    ///         case .failure(let err):   print("Failed: \(err)")
    ///         }
    ///     }
    ///
    /// Limitaciones del scaffold:
    /// · No guarda los records en CloudKit aún — solo crea el CKShare
    ///   en memoria y lo presenta. Para producción, necesita:
    ///   1) Custom CKRecordZone en private DB.
    ///   2) Save del record + share via CKModifyRecordsOperation.
    ///   3) Background receiver para aceptar invitations en didReceiveRemoteNotification.
    @MainActor
    static func shareSnapshot(
        _ snapshot: RaskmapSnapshot,
        from rootViewController: UIViewController? = nil,
        completion: @escaping (Result<CKShare, Error>) -> Void
    ) {
        let container = CKContainer(identifier: containerID)
        let zoneID = CKRecordZone.ID(zoneName: "RaskmapSnapshots", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "RaskmapSnapshot", recordID: recordID)

        record["username"] = snapshot.username as CKRecordValue
        record["visitedCount"] = snapshot.visitedIsoCodes.count as CKRecordValue
        record["totalTrips"] = snapshot.totalTrips as CKRecordValue
        record["totalKmFlown"] = snapshot.totalKmFlown as CKRecordValue
        if let data = snapshot.encoded() {
            record["payload"] = data as CKRecordValue
        }

        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = "Mapa de \(snapshot.username)" as CKRecordValue
        share.publicPermission = .readOnly  // cualquiera con el link puede ver

        // En producción aquí va el CKModifyRecordsOperation. En este
        // scaffold lo dejamos sin persistir para no requerir conexión
        // CloudKit ni dev account — basta para que el dev pueda probar
        // el UICloudSharingController en simulador.
        //
        // Una vez tengamos Apple Dev Account + CloudKit configurado:
        //
        //     let op = CKModifyRecordsOperation(
        //         recordsToSave: [record, share], recordIDsToDelete: nil)
        //     op.modifyRecordsResultBlock = { result in
        //         switch result {
        //         case .success: presentSharingUI(share, container, rootVC, completion)
        //         case .failure(let err): completion(.failure(err))
        //         }
        //     }
        //     container.privateCloudDatabase.add(op)

        presentSharingUI(share: share, container: container,
                         rootVC: rootViewController, completion: completion)
    }

    @MainActor
    private static func presentSharingUI(
        share: CKShare,
        container: CKContainer,
        rootVC: UIViewController?,
        completion: @escaping (Result<CKShare, Error>) -> Void
    ) {
        // Encontrar el VC desde el que presentar si no se pasó uno.
        let presenter: UIViewController? = rootVC ?? {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let win = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            else { return nil }
            var top = win.rootViewController
            while let p = top?.presentedViewController, !p.isBeingDismissed { top = p }
            return top
        }()
        guard let presenter else {
            completion(.failure(NSError(domain: "Raskmap.CloudKitSharing", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo encontrar la ventana activa para presentar el share."])))
            return
        }

        let sharingVC = UICloudSharingController(share: share, container: container)
        sharingVC.availablePermissions = [.allowReadOnly, .allowPublic]
        // Note: el delegate proper handling (failures, sharing done) se debe
        // implementar cuando wireed con la persistencia real.
        presenter.present(sharingVC, animated: true) {
            completion(.success(share))
        }
    }
}

// MARK: - Helper para construir el snapshot desde el estado actual

extension RaskmapSnapshot {
    /// Builder conveniente desde los `@Query` de SwiftData en ContentView.
    /// Llamar desde una computed property o un método helper.
    @MainActor
    static func build(
        username: String,
        countries: [Country],
        trips: [Trip],
        totalKmFlown: Int = 0
    ) -> RaskmapSnapshot {
        let visited = countries
            .filter { $0.status == .visited || $0.status == .lived }
            .map { $0.isoCode }
        let planned = countries
            .filter { $0.status == .wantToVisit }
            .map { $0.isoCode }
        return RaskmapSnapshot(
            username: username,
            visitedIsoCodes: visited,
            plannedIsoCodes: planned,
            totalTrips: trips.filter { !$0.isSegmentChild }.count,
            totalCountries: visited.count,
            totalKmFlown: totalKmFlown,
            createdAt: Date()
        )
    }
}
