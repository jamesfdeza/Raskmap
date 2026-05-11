//
//  AchievementKind.swift
//  Raskmap
//
//  Enum maestro de logros (achievements) del medallero. Define todas
//  las categorías (especiales, trophy, continentales, regionales),
//  sus títulos, descripciones, sets de ISOs por región y prioridad
//  de display. Usado por LogrosSheet, MedalleroSheet y ProfileSheet.
//
//  Self-contained — sin dependencias de state de ContentView.
//
//  Extraído de ContentView.swift durante Fase D.
//

import SwiftUI

// MARK: - Logros
enum AchievementKind: CaseIterable {
    // Especiales
    case firstTrip, firstLayover, trips100, allWorld
    // Trophy
    case visitedAntarctica, todosLosContinentes
    // Oro – zona completada
    case europaCompleta, asiaCompleta, medioOrienteCompleto, africaCompleta, americaCompleta, oceaniaCompleta
    // Oro – grupos especiales
    case todaLaUE
    // Oro – hemisferios
    case ambosHemisferios
    // Plata – grupos especiales
    case todosEslavos, todosEscandinavos, todosBalcanicos, todosMicroestados
    // Bronce – al menos 1 país visitado en la región
    case visitedNortamerica, visitedCaribe, visitedSudamerica, visitedCentroamerica
    case visitedAfrica, visitedEuropa, visitedMedioOriente, visitedOceania, visitedAsia
    // Bronce – especiales
    case primerMicroestado
    // Plata – 5 viajes en la región
    case fiveEurope, fiveAsia, fiveAfrica, fiveMedioOriente, fiveOceania
    case fiveNortamerica, fiveCaribe, fiveSudamerica, fiveCentroamerica
    // Oro – pasaporte lleno
    case pasaporteEuropa, pasaporteAsia, pasaporteMedioOriente, pasaporteAfrica, pasaporteAmerica, pasaporteOceania

    // MARK: Sets de ISO por región (logros visitados/five)
    private static let _northAmerica: Set<String> = ["USA","MEX","CAN"]
    private static let _caribbean: Set<String> = [
        "ATG","BHS","BRB","CUB","DMA","DOM","GRD","HTI","JAM","KNA","LCA","VCT","TTO",
        "ABW","AIA","BMU","VGB","CYM","CUW","MSR","PRI","BLM","MAF","SXM","TCA","VIR"
    ]
    private static let _southAmerica: Set<String> = [
        "ARG","BOL","BRA","CHL","COL","ECU","GUY","PRY","PER","SUR","URY","VEN","FLK"
    ]
    private static let _centralAmerica: Set<String> = ["BLZ","CRI","SLV","GTM","HND","NIC","PAN"]
    private static let _europe: Set<String> = [
        "ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE",
        "DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA",
        "LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP",
        "SWE","CHE","UKR","GBR","VAT","KOS","ALD","FRO","GIB","GGY","IMN","JEY"
    ]
    private static let _asia: Set<String> = [
        "AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
        "TKM","UZB","VNM","HKG","MAC","IOT"
    ]
    private static let _middleEast: Set<String> = [
        "BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX",
        "QAT","SAU","SYR","TUR","ARE","YEM"
    ]
    private static let _africa: Set<String> = [
        "DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
        "SEN","SYC","SLE","SOM","ZAF","SSD","SDS","SDN","SWZ","TZA",
        "TGO","TUN","UGA","ZMB","ZWE","SAH","SHN"
    ]
    private static let _oceania: Set<String> = [
        "AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
        "SLB","TON","TUV","VUT","ASM","COK","PYF","GUM","NCL","NIU","NFK","MNP","PCN","WLF"
    ]
    private static let _antarctica: Set<String> = ["ATA"]

    // MARK: Sets de grupos especiales
    private static let _unionEuropea: Set<String> = [
        "AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA",
        "DEU","GRC","HUN","IRL","ITA","LVA","LTU","LUX","MLT","NLD",
        "POL","PRT","ROU","SVK","SVN","ESP","SWE"
    ]
    private static let _eslavos: Set<String> = [
        "RUS","UKR","BLR",                        // Eslavos orientales
        "POL","CZE","SVK",                         // Eslavos occidentales
        "SRB","HRV","SVN","BGR","MKD","BIH","MNE"  // Eslavos meridionales
    ]
    private static let _escandinavos: Set<String> = ["NOR","SWE","DNK","FIN","ISL"]
    private static let _balcanicos: Set<String> = [
        "ALB","BIH","BGR","HRV","GRC","MKD","MNE","ROU","SRB","SVN","KOS"
    ]
    private static let _microestados: Set<String> = ["AND","LIE","MCO","SMR","VAT","MLT"]

    // MARK: Sets de ISO por zona de Mi mapa (logros completados)
    private static let _zoneEuropa: Set<String> = [
        "ALB","AND","AUT","BLR","BEL","BIH","BGR","HRV","CYP","CZE",
        "DNK","EST","FIN","FRA","DEU","GRC","HUN","ISL","IRL","ITA",
        "LVA","LIE","LTU","LUX","MLT","MDA","MCO","MNE","NLD","MKD",
        "NOR","POL","PRT","ROU","RUS","SMR","SRB","SVK","SVN","ESP",
        "SWE","CHE","UKR","GBR","VAT","KOS","ALD","FRO","GIB","GGY","IMN","JEY"
    ]
    private static let _zoneAsia: Set<String> = [
        "AFG","ARM","AZE","BGD","BTN","BRN","KHM","CHN","GEO","IND",
        "IDN","JPN","KAZ","PRK","KOR","KGZ","LAO","MYS","MDV","MNG",
        "MMR","NPL","PAK","PHL","SGP","LKA","TWN","TJK","THA","TLS",
        "TKM","UZB","VNM","HKG","MAC","IOT"
    ]
    private static let _zoneMedioOriente: Set<String> = [
        "BHR","IRN","IRQ","ISR","JOR","KWT","LBN","OMN","PSE","PSX",
        "QAT","SAU","SYR","TUR","ARE","YEM"
    ]
    private static let _zoneAfrica: Set<String> = [
        "DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD",
        "COM","COD","COG","CIV","DJI","EGY","GNQ","ERI","ETH","GAB",
        "GMB","GHA","GIN","GNB","KEN","LSO","LBR","LBY","MDG","MWI",
        "MLI","MRT","MUS","MAR","MOZ","NAM","NER","NGA","RWA","STP",
        "SEN","SYC","SLE","SOM","ZAF","SSD","SDS","SDN","SWZ","TZA",
        "TGO","TUN","UGA","ZMB","ZWE","SAH","SHN"
    ]
    private static let _zoneAmerica: Set<String> = [
        "ATG","ARG","BHS","BRB","BLZ","BOL","BRA","CAN","CHL","COL",
        "CRI","CUB","DMA","DOM","ECU","SLV","GRD","GTM","GUY","HTI",
        "HND","JAM","MEX","NIC","PAN","PRY","PER","KNA","LCA","VCT",
        "SUR","TTO","USA","URY","VEN","ABW","AIA","BMU","VGB","CYM",
        "CUW","FLK","GRL","MSR","PRI","BLM","MAF","SPM","SXM","TCA","VIR"
    ]
    private static let _zoneOceania: Set<String> = [
        "AUS","FJI","KIR","MHL","FSM","NRU","NZL","PLW","PNG","WSM",
        "SLB","TON","TUV","VUT","ASM","COK","PYF","GUM","NCL","NIU",
        "NFK","MNP","PCN","WLF"
    ]

    // MARK: Hemisferio sur
    static let southernHemisphere: Set<String> = [
        // Sudamérica (centro claramente al sur del ecuador)
        "ARG","BOL","BRA","CHL","ECU","PER","PRY","URY","FLK",
        // África austral
        "AGO","BDI","BWA","COM","COD","COG","GAB","LSO","MDG","MOZ","MUS","MWI",
        "NAM","RWA","SWZ","SYC","TZA","ZAF","ZMB","ZWE",
        // Oceanía / Pacífico sur
        "AUS","FJI","NRU","NZL","PNG","SLB","TLS","TON","TUV","VUT","WSM",
        "ASM","COK","NCL","NIU","NFK","PCN","PYF","WLF",
        // Atlántico / Índico
        "IOT","SHN"
    ]

    // MARK: Multi-hemisphere adjustment
    // (iso, defaultHemisphere) — países que cruzan el ecuador
    static let multiHemisphereData: [(iso: String, defaultH: String, flag: String, name: String)] = [
        // Sudamérica
        ("ECU", "sur",   "🇪🇨", "Ecuador"),
        ("COL", "norte", "🇨🇴", "Colombia"),
        ("BRA", "sur",   "🇧🇷", "Brasil"),
        // África ecuatorial
        ("GAB", "norte", "🇬🇦", "Gabón"),
        ("COG", "sur",   "🇨🇬", "Congo"),
        ("COD", "sur",   "🇨🇩", "R. D. del Congo"),
        ("UGA", "norte", "🇺🇬", "Uganda"),
        ("KEN", "sur",   "🇰🇪", "Kenia"),
        ("SOM", "norte", "🇸🇴", "Somalia"),
        // Asia / Pacífico
        ("MDV", "norte", "🇲🇻", "Maldivas"),
        ("IDN", "sur",   "🇮🇩", "Indonesia"),
        ("KIR", "norte", "🇰🇮", "Kiribati"),
    ]

    static func adjustedHemispheres(assignments: [String: String]) -> (south: Set<String>, ambos: Set<String>) {
        var south = southernHemisphere
        var ambos = Set<String>()
        for entry in multiHemisphereData {
            let assignment = assignments[entry.iso] ?? entry.defaultH
            switch assignment {
            case "norte": south.remove(entry.iso)
            case "sur":   south.insert(entry.iso)
            case "ambos": south.remove(entry.iso); ambos.insert(entry.iso)
            default:      break
            }
        }
        return (south, ambos)
    }

    // MARK: Multi-continent adjustment
    // (iso, primaryZone, secondaryZone)
    private static let multiContinentData: [(String, String, String)] = [
        ("RUS", "europa",       "asia"),
        ("TUR", "medioOriente", "europa"),
        ("CYP", "europa",       "medioOriente"),
        ("AZE", "asia",         "europa"),
        ("GEO", "asia",         "europa"),
        ("KAZ", "asia",         "europa"),
        ("EGY", "africa",       "asia"),
    ]

    /// Returns the base set adjusted for multi-continent country preferences.
    static func adjustSet(_ base: Set<String>, forZone zoneName: String, assignments: [String: String]) -> Set<String> {
        var result = base
        for (iso, primary, secondary) in multiContinentData {
            let assignment = assignments[iso] ?? primary
            let inZone: Bool
            if assignment == "ambos" {
                inZone = (zoneName == primary || zoneName == secondary)
            } else {
                inZone = (assignment == zoneName)
            }
            if inZone { result.insert(iso) } else { result.remove(iso) }
        }
        return result
    }

    /// Geographic zone name for zone-completion achievements (nil = cultural/fixed group)
    var geographicZoneName: String? {
        switch self {
        case .europaCompleta:       return "europa"
        case .asiaCompleta:         return "asia"
        case .medioOrienteCompleto: return "medioOriente"
        case .africaCompleta:       return "africa"
        case .americaCompleta:      return "america"
        case .oceaniaCompleta:      return "oceania"
        default:                    return nil
        }
    }

    /// Geographic region name for visited/five-trip achievements
    var geographicRegionName: String? {
        switch self {
        case .visitedEuropa, .fiveEurope:                   return "europa"
        case .visitedAsia, .fiveAsia:                       return "asia"
        case .visitedMedioOriente, .fiveMedioOriente:       return "medioOriente"
        case .visitedAfrica, .fiveAfrica:                   return "africa"
        default:                                            return nil
        }
    }

    /// ExportZone rawValue key for passport-completion achievements (nil = other kinds)
    var passportZoneKey: String? {
        switch self {
        case .pasaporteEuropa:       return "Europa"
        case .pasaporteAsia:         return "Asia"
        case .pasaporteMedioOriente: return "M. Oriente"
        case .pasaporteAfrica:       return "África"
        case .pasaporteAmerica:      return "América"
        case .pasaporteOceania:      return "Oceanía"
        default:                     return nil
        }
    }

    /// Maps a `passportZoneKey` rawValue to the lowercase `zoneName` used in
    /// `multiContinentData`. Used for filtering pluricontinental countries
    /// out of the wrong zone in passport-completion checks.
    static func zoneName(forPassportKey key: String) -> String? {
        switch key {
        case "Europa":      return "europa"
        case "Asia":        return "asia"
        case "M. Oriente":  return "medioOriente"
        case "África":      return "africa"
        case "América":     return "america"
        case "Oceanía":     return "oceania"
        default:            return nil
        }
    }

    /// Antes filtraba ISOs pluricontinentales según asignación de zona en
    /// Ajustes. Ahora devuelve los ISOs sin filtrar: el usuario decide
    /// libremente en qué cuadrante meter cada país pluri y siempre cuenta
    /// donde lo pone, independientemente del continente asignado.
    static func filterCandidatesForZone(_ isos: [String], zoneName: String, assignments: [String: String], quadrantTitle: String? = nil) -> [String] {
        return isos
    }

    var zoneIsoCodes: Set<String> {
        switch self {
        case .europaCompleta:       return Self._zoneEuropa
        case .asiaCompleta:         return Self._zoneAsia
        case .medioOrienteCompleto: return Self._zoneMedioOriente
        case .africaCompleta:       return Self._zoneAfrica
        case .americaCompleta:      return Self._zoneAmerica
        case .oceaniaCompleta:      return Self._zoneOceania
        case .todaLaUE:             return Self._unionEuropea
        case .todosEslavos:         return Self._eslavos
        case .todosEscandinavos:    return Self._escandinavos
        case .todosBalcanicos:      return Self._balcanicos
        case .todosMicroestados:    return Self._microestados
        // passport achievements use candidateIsoCodes from mapQuadrantsData, not static sets
        case .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania: return []
        default:                    return []
        }
    }

    var regionIsoCodes: Set<String> {
        switch self {
        case .visitedNortamerica, .fiveNortamerica:       return Self._northAmerica
        case .visitedCaribe, .fiveCaribe:                 return Self._caribbean
        case .visitedSudamerica, .fiveSudamerica:         return Self._southAmerica
        case .visitedCentroamerica, .fiveCentroamerica:   return Self._centralAmerica
        case .visitedEuropa, .fiveEurope:                 return Self._europe
        case .visitedAsia:                                return Self._asia.union(Self._middleEast)
        case .fiveAsia:                                   return Self._asia
        case .visitedMedioOriente, .fiveMedioOriente:     return Self._middleEast
        case .visitedAfrica, .fiveAfrica:                 return Self._africa
        case .visitedOceania, .fiveOceania:               return Self._oceania
        case .visitedAntarctica:                          return Self._antarctica
        default:                                          return []
        }
    }

    var regionName: String {
        switch self {
        case .visitedEuropa, .fiveEurope:                 return "Europa"
        case .visitedAsia, .fiveAsia:                     return "Asia"
        case .visitedAfrica, .fiveAfrica:                 return "África"
        case .visitedMedioOriente, .fiveMedioOriente:     return "Medio Oriente"
        case .visitedOceania, .fiveOceania:               return "Oceanía"
        case .visitedNortamerica, .fiveNortamerica:       return "Norteamérica"
        case .visitedCaribe, .fiveCaribe:                 return "el Caribe"
        case .visitedSudamerica, .fiveSudamerica:         return "Sudamérica"
        case .visitedCentroamerica, .fiveCentroamerica:   return "Centroamérica"
        default:                                          return ""
        }
    }

    var title: String {
        switch self {
        case .firstTrip:            return "Tu primer viaje"
        case .firstLayover:         return "Primera escala"
        case .trips100:             return "100 viajes"
        case .allWorld:             return "Todo el mundo"
        case .visitedAntarctica:    return "He estado en Antártida"
        case .todosLosContinentes:  return "Todos los continentes"
        case .europaCompleta:       return "Europa completada"
        case .asiaCompleta:         return "Asia completada"
        case .medioOrienteCompleto: return "M. Oriente completado"
        case .africaCompleta:       return "África completada"
        case .americaCompleta:      return "América completada"
        case .oceaniaCompleta:      return "Oceanía completada"
        case .ambosHemisferios:     return "Ambos hemisferios"
        case .todaLaUE:             return "Toda la UE"
        case .todosEslavos:         return "Todos los eslavos"
        case .todosEscandinavos:    return "Todos los escandinavos"
        case .todosBalcanicos:      return "Todos los balcánicos"
        case .todosMicroestados:    return "Todos los microestados"
        case .visitedNortamerica:   return "He estado en Norteamérica"
        case .visitedCaribe:        return "He estado en el Caribe"
        case .visitedSudamerica:    return "He estado en Sudamérica"
        case .visitedCentroamerica: return "He estado en Centroamérica"
        case .visitedAfrica:        return "He estado en África"
        case .visitedEuropa:        return "He estado en Europa"
        case .visitedMedioOriente:  return "He estado en Medio Oriente"
        case .visitedOceania:       return "He estado en Oceanía"
        case .visitedAsia:          return "He estado en Asia"
        case .primerMicroestado:    return "Mi primer microestado"
        case .fiveEurope:           return "Cinco veces en Europa"
        case .fiveAsia:             return "Cinco veces en Asia"
        case .fiveAfrica:           return "Cinco veces en África"
        case .fiveMedioOriente:     return "Cinco veces en Medio Oriente"
        case .fiveOceania:          return "Cinco veces en Oceanía"
        case .fiveNortamerica:      return "Cinco veces en Norteamérica"
        case .fiveCaribe:           return "Cinco veces en el Caribe"
        case .fiveSudamerica:       return "Cinco veces en Sudamérica"
        case .fiveCentroamerica:    return "Cinco veces en Centroamérica"
        case .pasaporteEuropa:      return "Pasaporte Europa completo"
        case .pasaporteAsia:        return "Pasaporte Asia completo"
        case .pasaporteMedioOriente: return "Pasaporte M. Oriente completo"
        case .pasaporteAfrica:      return "Pasaporte África completo"
        case .pasaporteAmerica:     return "Pasaporte América completo"
        case .pasaporteOceania:     return "Pasaporte Oceanía completo"
        }
    }

    var medal: String {
        switch self {
        case .allWorld, .visitedAntarctica, .todosLosContinentes:
            return "🏆"
        case .trips100, .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta, .ambosHemisferios,
             .todaLaUE,
             .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania:
            return "🥇"
        case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
             .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica,
             .firstLayover,
             .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados:
            return "🥈"
        case .firstTrip, .visitedNortamerica, .visitedCaribe, .visitedSudamerica,
             .visitedCentroamerica, .visitedAfrica, .visitedEuropa, .visitedMedioOriente,
             .visitedOceania, .visitedAsia, .primerMicroestado:
            return "🥉"
        }
    }

    var medalOrder: Int {
        switch self {
        case .allWorld, .visitedAntarctica, .todosLosContinentes: return 0
        case .trips100, .europaCompleta, .asiaCompleta, .medioOrienteCompleto,
             .africaCompleta, .americaCompleta, .oceaniaCompleta, .ambosHemisferios,
             .todaLaUE,
             .pasaporteEuropa, .pasaporteAsia, .pasaporteMedioOriente,
             .pasaporteAfrica, .pasaporteAmerica, .pasaporteOceania: return 1
        case .fiveEurope, .fiveAsia, .fiveAfrica, .fiveMedioOriente, .fiveOceania,
             .fiveNortamerica, .fiveCaribe, .fiveSudamerica, .fiveCentroamerica,
             .firstLayover,
             .todosEslavos, .todosEscandinavos, .todosBalcanicos, .todosMicroestados: return 2
        case .firstTrip, .visitedNortamerica, .visitedCaribe, .visitedSudamerica,
             .visitedCentroamerica, .visitedAfrica, .visitedEuropa, .visitedMedioOriente,
             .visitedOceania, .visitedAsia, .primerMicroestado: return 3
        }
    }
}
