//
//  CountingMode.swift
//  Raskmap
//
//  Define los tres modos de conteo de territorios y las listas oficiales.
//

import Foundation

enum CountingMode: String, CaseIterable {
    case un        = "un"          // 193 miembros ONU
    case unPlus    = "unPlus"      // 195: ONU + 2 observadores
    case all       = "all"         // 244: todos los territorios

    var label: String {
        switch self {
        case .un:     return "ONU"
        case .unPlus: return "ONU + obs."
        case .all:    return "Todos"
        }
    }

    var denominator: Int {
        switch self {
        case .un:     return 193
        case .unPlus: return 195
        case .all:    return 244
        }
    }

    /// Devuelve true si el isoCode cuenta en este modo
    func counts(_ isoCode: String) -> Bool {
        switch self {
        case .all:     return true
        case .un:      return CountingMode.unMembers.contains(isoCode)
        case .unPlus:  return CountingMode.unMembers.contains(isoCode)
                           || CountingMode.unObservers.contains(isoCode)
        }
    }

    // MARK: - Listas oficiales

    /// 193 Estados Miembros de la ONU (ISO A3)
    static let unMembers: Set<String> = [
        "AFG","ALB","DZA","AND","AGO","ATG","ARG","ARM","AUS","AUT",
        "AZE","BHS","BHR","BGD","BRB","BLR","BEL","BLZ","BEN","BTN",
        "BOL","BIH","BWA","BRA","BRN","BGR","BFA","BDI","CPV","KHM",
        "CMR","CAN","CAF","TCD","CHL","CHN","COL","COM","COD","COG",
        "CRI","CIV","HRV","CUB","CYP","CZE","DNK","DJI","DMA","DOM",
        "ECU","EGY","SLV","GNQ","ERI","EST","SWZ","ETH","FJI","FIN",
        "FRA","GAB","GMB","GEO","DEU","GHA","GRC","GRD","GTM","GIN",
        "GNB","GUY","HTI","HND","HUN","ISL","IND","IDN","IRN","IRQ",
        "IRL","ISR","ITA","JAM","JPN","JOR","KAZ","KEN","KIR","PRK",
        "KOR","KWT","KGZ","LAO","LVA","LBN","LSO","LBR","LBY","LIE",
        "LTU","LUX","MDG","MWI","MYS","MDV","MLI","MLT","MHL","MRT",
        "MUS","MEX","FSM","MDA","MCO","MNG","MNE","MAR","MOZ","MMR",
        "NAM","NRU","NPL","NLD","NZL","NIC","NER","NGA","MKD","NOR",
        "OMN","PAK","PLW","PAN","PNG","PRY","PER","PHL","POL","PRT",
        "QAT","ROU","RUS","RWA","KNA","LCA","VCT","WSM","SMR","STP",
        "SAU","SEN","SRB","SYC","SLE","SGP","SVK","SVN","SLB","SOM",
        "ZAF","SSD","ESP","LKA","SDN","SUR","SWE","CHE","SYR","TJK",
        "TZA","THA","TLS","TGO","TON","TTO","TUN","TUR","TKM","TUV",
        "UGA","UKR","ARE","GBR","USA","URY","UZB","VUT","VEN","VNM",
        "YEM","ZMB","ZWE"
    ]

    /// 2 Estados Observadores de la ONU (Vaticano y Palestina)
    static let unObservers: Set<String> = ["VAT", "PSE"]
}
