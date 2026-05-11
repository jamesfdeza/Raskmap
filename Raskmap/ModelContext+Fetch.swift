//
//  ModelContext+Fetch.swift
//  Raskmap
//
//  Helpers de fetch/save que loguean errores en lugar de silenciarlos con
//  `try?`. Evita perder datos silenciosamente en flujos destructivos —
//  un save que falla (CloudKit conflict, quota excedida, schema mismatch,
//  BD corrupta) ahora deja huella en logs en lugar de desaparecer.
//

import Foundation
import SwiftData
import os

/// Logger compartido para errores de SwiftData. En producción, accesible vía
/// Console.app + filtrado `subsystem:RealDev.Raskmap category:swiftdata`.
nonisolated let swiftDataLogger = Logger(subsystem: "RealDev.Raskmap", category: "swiftdata")

extension ModelContext {
    /// Ejecuta un fetch devolviendo el resultado o un fallback. En DEBUG loguea el error.
    func fetchOrWarn<T>(_ descriptor: FetchDescriptor<T>,
                        fallback: [T] = [],
                        file: StaticString = #file,
                        line: UInt = #line) -> [T] {
        do { return try fetch(descriptor) }
        catch {
            #if DEBUG
            print("⚠️ SwiftData fetch failed [\(file):\(line)]: \(error)")
            #endif
            swiftDataLogger.error("fetch failed [\("\(file)"):\(line)]: \(error.localizedDescription)")
            return fallback
        }
    }

    /// Variante que devuelve sólo el primer resultado (o `nil`).
    func fetchFirstOrWarn<T>(_ descriptor: FetchDescriptor<T>,
                             file: StaticString = #file,
                             line: UInt = #line) -> T? {
        do { return try fetch(descriptor).first }
        catch {
            #if DEBUG
            print("⚠️ SwiftData fetch failed [\(file):\(line)]: \(error)")
            #endif
            swiftDataLogger.error("fetch failed [\("\(file)"):\(line)]: \(error.localizedDescription)")
            return nil
        }
    }

    /// Save con logging — reemplaza el patrón `try? modelContext.save()` que
    /// silenciaba cualquier fallo (CloudKit, quota, conflict). Loguea via
    /// `os.Logger` (visible en Console.app) y en DEBUG imprime también.
    /// Devuelve `true` si tuvo éxito, `false` si falló.
    @discardableResult
    func saveOrWarn(file: StaticString = #file, line: UInt = #line) -> Bool {
        do {
            try save()
            return true
        } catch {
            #if DEBUG
            print("⚠️ SwiftData save failed [\(file):\(line)]: \(error)")
            #endif
            swiftDataLogger.error("save failed [\("\(file)"):\(line)]: \(error.localizedDescription)")
            return false
        }
    }
}
