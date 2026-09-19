//
//  EventTier.swift
//  SportsCalModel
//
//  How important a golf tournament or tennis event is to its tour, and the per-sport
//  "coverage" preference that decides which tiers a user sees. One tennis week can put
//  hundreds of 250-level and qualifying matches on the board; this is what lets a casual
//  fan keep the slams without the rest, while a hardcore fan still opts into everything.
//

import Foundation

/// Importance of an individual-sport event within its tour. Ordered, so `>=` reads as
/// "at least this big".
public enum EventTier: Int, Comparable, Sendable {
    /// Regular tour stop — ATP/WTA 250 & 500, a standard PGA TOUR event.
    case tour
    /// ATP/WTA 1000s, the season finals, the Olympics; THE PLAYERS and PGA TOUR
    /// signature events, playoffs and team cups.
    case premier
    /// Tennis Grand Slams; golf's four majors.
    case major

    public static func < (lhs: EventTier, rhs: EventTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Which tiers a user wants for a sport. Stored per sport (`coverageTennis`, `coverageGolf`).
public enum EventCoverage: String, CaseIterable, Codable, Sendable {
    /// Grand Slams / majors, plus the semifinals and finals of premier events.
    case majors
    /// Premier events and up. The default: something most weeks, without the 250s.
    case bigEvents
    /// Every event and round, qualifying included.
    case everything

    public static let `default`: EventCoverage = .bigEvents

    /// Sports the preference applies to. Team sports have no tiers.
    public static let sports: [SportType] = [.tennis, .golf]

    /// UserDefaults / app-group / iCloud key for `sport`'s coverage.
    public static func storageKey(for sport: SportType) -> String {
        switch sport {
        case .golf: return "coverageGolf"
        default:    return "coverageTennis"
        }
    }

    /// Reads `sport`'s coverage from `defaults`, falling back to the default for an
    /// unset or unrecognised value. Team sports always get `.everything`.
    public static func stored(for sport: SportType, in defaults: UserDefaults?) -> EventCoverage {
        guard sports.contains(sport) else { return .everything }
        return defaults?.string(forKey: storageKey(for: sport)).flatMap(EventCoverage.init(rawValue:)) ?? .default
    }

    public func displayName(for sport: SportType) -> String {
        switch self {
        case .majors:     return sport == .tennis ? "Grand Slams" : "Majors"
        case .bigEvents:  return "Big Events"
        case .everything: return "Everything"
        }
    }

    public func summary(for sport: SportType) -> String {
        switch (self, sport) {
        case (.majors, .tennis):     return "The four Grand Slams, plus 1000-level semifinals and finals"
        case (.majors, _):           return "The four majors"
        case (.bigEvents, .tennis):  return "Grand Slams, 1000s, the Finals and the Olympics"
        case (.bigEvents, _):        return "Majors, THE PLAYERS and signature events"
        case (.everything, .tennis): return "Every tournament, including 250s, 500s and qualifying"
        case (.everything, _):       return "Every tournament"
        }
    }
}

extension Game {
    /// The name tiers are matched against: the tournament for a tennis match, the event
    /// itself (carried in `strHomeTeam`) for a golf tournament row.
    private var tierMatchName: String? {
        if let tournamentName, !tournamentName.isEmpty { return tournamentName }
        guard let sport = sportType else { return nil }
        switch sport {
        case .golf:   return strHomeTeam
        // A tennis match's teams are its players, so without a tournament there's
        // nothing to classify.
        case .tennis: return isTennisMatch ? nil : strHomeTeam
        default:      return nil
        }
    }

    /// This event's tier, or nil for team sports and for tennis rows that don't say
    /// which tournament they belong to (those are never hidden by coverage).
    public var eventTier: EventTier? {
        guard let sport = sportType, EventCoverage.sports.contains(sport),
              let name = tierMatchName else { return nil }
        let league = idLeague.flatMap { Int($0) }.flatMap { Leagues(rawValue: $0) }
        let normalized = name.lowercased()
        switch sport {
        case .golf:   return EventTierTable.golfTier(normalized, tour: league)
        case .tennis: return EventTierTable.tennisTier(normalized, tours: tennisTours)
        default:      return nil
        }
    }

    /// Tennis qualifying ("Qualifying 1st Round", "Qualifying Final").
    public var isQualifyingRound: Bool {
        round?.lowercased().contains("qualif") == true
    }

    /// Tennis semifinal or final — the matches worth surfacing from an event the user
    /// otherwise isn't following.
    public var isLateRound: Bool {
        guard let round = round?.lowercased(), !isQualifyingRound else { return false }
        // "Quarterfinal" has no space before "final", so the suffix check doesn't catch it.
        return round.contains("semifinal") || round == "final" || round.hasSuffix(" final")
    }

    /// Whether this game passes `coverage`. `isFavorite` (a followed player or team) always
    /// passes. Team sports and unclassifiable rows always pass.
    public func passesCoverage(_ coverage: EventCoverage, isFavorite: Bool = false) -> Bool {
        if coverage == .everything || isFavorite { return true }
        guard let tier = eventTier else { return true }
        switch coverage {
        case .everything:
            return true
        case .bigEvents:
            return tier >= .premier && !isQualifyingRound
        case .majors:
            if isQualifyingRound { return false }
            return tier == .major || (tier == .premier && isLateRound)
        }
    }
}

/// Name → tier tables. Names are ESPN's (`event.name` for tennis, the calendar label for
/// golf), which carry sponsors and change year to year — so these match on the stable
/// core of the name rather than the whole string. Anything unmatched is `.tour`.
enum EventTierTable {
    static func tennisTier(_ name: String, tours: Set<Leagues>) -> EventTier {
        if tennisMajors.contains(where: name.contains) { return .major }
        if tennisPremier.contains(where: name.contains) { return .premier }
        // WTA 1000s that share a name with the same week's ATP 500.
        if tours.contains(.wta), wtaOnlyPremier.contains(where: name.contains) { return .premier }
        // Monte-Carlo is a men's-only 1000.
        if tours.contains(.atp), atpOnlyPremier.contains(where: name.contains) { return .premier }
        return .tour
    }

    /// Each golf tour has its own majors, so the tour decides which table to read.
    /// An unknown tour is treated as the PGA TOUR, which is where a name with no league
    /// on it almost certainly came from.
    static func golfTier(_ name: String, tour: Leagues?) -> EventTier {
        switch tour {
        case .lpga:
            if lpgaMajors.contains(where: name.contains) { return .major }
            if name.contains("solheim cup") || name.contains("cme group tour championship") { return .premier }
            return .tour
        case .championsTour:
            // The senior majors, which carry the parent tour's names ("Senior PGA
            // Championship"), so they can't share the PGA table.
            if seniorMajors.contains(where: name.contains) { return .major }
            return .tour
        case .dpWorld:
            // No majors of its own — the four it plays for are the men's majors, which
            // ESPN files under the PGA board.
            if dpWorldPremier.contains(where: name.contains) { return .premier }
            return .tour
        case .livGolf:
            // A flat season of 54-hole events; only the team championship stands out.
            if name.contains("team championship") { return .premier }
            return .tour
        case .kornFerry:
            // A development tour: never "big events" on its own merits.
            return .tour
        default:
            if name.contains("masters")
                || name.contains("pga championship")
                || name.contains("u.s. open") || name.contains("us open")
                || name == "the open" || name.hasPrefix("the open championship") || name == "open championship" {
                return .major
            }
            if golfPremier.contains(where: name.contains) { return .premier }
            return .tour
        }
    }

    private static let tennisMajors = [
        "australian open", "roland garros", "roland-garros", "french open", "wimbledon", "us open",
    ]

    private static let tennisPremier = [
        "indian wells", "bnp paribas open",
        "miami open",
        "madrid open", "mutua madrid",
        "internazionali bnl", "italian open",
        "national bank open", "canadian open", "omnium banque nationale",
        "cincinnati open", "western & southern",
        "shanghai masters",
        "paris masters",
        "atp finals", "wta finals",
        "olympic",
    ]

    private static let wtaOnlyPremier = [
        "qatar totalenergies open", "dubai duty free", "china open", "wuhan open",
    ]

    private static let atpOnlyPremier = [
        "monte-carlo", "monte carlo",
    ]

    // Not a bare "women's open": that also matches "CPKC Women's Open", a regular stop.
    private static let lpgaMajors = [
        "chevron championship", "u.s. women's open", "us women's open",
        "women's pga championship", "evian championship",
        "aig women's open", "women's british open",
    ]

    private static let seniorMajors = [
        "senior pga championship", "u.s. senior open", "us senior open",
        "senior players championship", "senior open championship", "tradition",
    ]

    private static let dpWorldPremier = [
        "bmw pga championship", "dp world tour championship", "genesis scottish open", "ryder cup",
    ]

    private static let golfPremier = [
        "the players", "the sentry", "pebble beach", "genesis invitational", "arnold palmer invitational",
        "rbc heritage", "truist championship", "cadillac championship", "memorial tournament",
        "travelers championship", "fedex st. jude", "bmw championship", "tour championship",
        "presidents cup", "ryder cup",
    ]
}
