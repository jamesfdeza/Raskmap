//
//  ModelContext+Fetch.swift
//  Raskmap
//
//  Helpers de fetch que loguean errores en lugar de silenciarlos con `try?`.
//  Evita perder datos silenciosamente en flujos destructivos.
//

import Foundation
import SwiftData

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
            return nil
        }
    }
}
