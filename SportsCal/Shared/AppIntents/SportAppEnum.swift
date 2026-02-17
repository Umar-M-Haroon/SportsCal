//
//  SportAppEnum.swift
//  SportsCal
//
//  App-level sport enum for Siri Shortcuts and Focus Filters.
//

import AppIntents
import SportsCalModel

enum SportAppEnum: String, AppEnum {
    case basketball
    case soccer
    case hockey
    case mlb
    case nfl
    case golf
    case tennis
    case racing

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Sport"
    }

    static var caseDisplayRepresentations: [SportAppEnum: DisplayRepresentation] {
        [
            .basketball: "Basketball",
            .soccer: "Soccer",
            .hockey: "Hockey",
            .mlb: "Baseball",
            .nfl: "Football",
            .golf: "Golf",
            .tennis: "Tennis",
            .racing: "Formula 1"
        ]
    }

    var sportType: SportType {
        switch self {
        case .basketball: return .basketball
        case .soccer: return .soccer
        case .hockey: return .hockey
        case .mlb: return .mlb
        case .nfl: return .nfl
        case .golf: return .golf
        case .tennis: return .tennis
        case .racing: return .racing
        }
    }

    init(sportType: SportType) {
        switch sportType {
        case .basketball: self = .basketball
        case .soccer: self = .soccer
        case .hockey: self = .hockey
        case .mlb: self = .mlb
        case .nfl: self = .nfl
        case .golf: self = .golf
        case .tennis: self = .tennis
        case .racing: self = .racing
        }
    }
}
