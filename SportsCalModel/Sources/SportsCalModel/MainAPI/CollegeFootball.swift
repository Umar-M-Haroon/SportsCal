//
//  CollegeFootball.swift
//  SportsCalModel
//
//  FBS college football: conferences, AP ranks, and the selection that decides how
//  much of a 60-game Saturday a user sees — and how it's sectioned.
//

import Foundation

/// An FBS conference, plus `.fcs` for the lower-division opponents FBS teams schedule.
/// The raw value is what travels on `Game.homeConference` / `awayConference` and in the
/// `cfbSel` query parameter, so it must stay stable.
public enum CollegeConference: String, CaseIterable, Codable, Sendable {
    case sec, bigTen, big12, acc, pac12, american, mountainWest, sunBelt, mac, cusa, independent
    case fcs

    /// The FBS conferences, in display order: Power Four first, then the Group of Five.
    public static let fbs: [CollegeConference] = allCases.filter { $0 != .fcs }

    public static let power: Set<CollegeConference> = [.sec, .bigTen, .big12, .acc]

    /// ESPN conference group IDs (`team.conferenceId` on the scoreboard), checked against
    /// ESPN's groups API in October 2026.
    private static let byESPNID: [String: CollegeConference] = [
        "1": .acc, "4": .big12, "5": .bigTen, "8": .sec, "9": .pac12, "12": .cusa,
        "15": .mac, "17": .mountainWest, "18": .independent, "37": .sunBelt, "151": .american,
    ]

    /// Every FBS team's opponent is on the board too, so an ID outside the FBS table is an
    /// FCS conference — they're lumped together.
    public init?(espnID: String) {
        guard !espnID.isEmpty else { return nil }
        self = Self.byESPNID[espnID] ?? .fcs
    }

    public var isPower: Bool { Self.power.contains(self) }

    public var displayName: String {
        switch self {
        case .sec:          return "SEC"
        case .bigTen:       return "Big Ten"
        case .big12:        return "Big 12"
        case .acc:          return "ACC"
        case .pac12:        return "Pac-12"
        case .american:     return "American"
        case .mountainWest: return "Mountain West"
        case .sunBelt:      return "Sun Belt"
        case .mac:          return "MAC"
        case .cusa:         return "Conference USA"
        case .independent:  return "Independents"
        case .fcs:          return "FCS"
        }
    }
}

public extension Leagues {
    /// Prefix on college team IDs. They stay ESPN IDs — college has no TheSportsDB side —
    /// but ESPN numbers each sport separately, and the WNBA's ESPN IDs also go untranslated
    /// (5 is both the Indiana Fever and UAB), so following one would follow the other.
    static let collegeTeamIDPrefix = "ncaaf-"

    /// The `idHomeTeam`/`idAwayTeam` a game from this league carries for an ESPN team ID.
    func teamID(espnID: String) -> String {
        self == .ncaaf ? Self.collegeTeamIDPrefix + espnID : espnID
    }

    /// The ESPN team ID behind a college team ID (`ncaaf-57` → `57`), or nil for any other ID.
    static func collegeESPNTeamID(_ teamID: String) -> String? {
        guard teamID.hasPrefix(collegeTeamIDPrefix) else { return nil }
        return String(teamID.dropFirst(collegeTeamIDPrefix.count))
    }
}

public extension Game {
    /// Seeds and AP ranks run 1...25; ESPN's `99` ("unranked") and anything else outside
    /// that range is noise.
    static func sanitizedSeed(_ value: Int) -> Int? {
        (1...25).contains(value) ? value : nil
    }

    var isCollegeFootball: Bool {
        idLeague == "\(Leagues.ncaaf.rawValue)"
    }

    /// Both teams' conferences, home first. Unknown values (a newer server) drop out.
    var collegeConferences: [CollegeConference] {
        [homeConference, awayConference].compactMap { $0.flatMap(CollegeConference.init(rawValue:)) }
    }

    /// Either side is in the AP Top 25.
    var hasRankedTeam: Bool {
        homeSeed != nil || awaySeed != nil
    }

    /// A College Football Playoff game, title game included.
    var isCollegeFootballPlayoff: Bool {
        guard let title = playoff?.seriesTitle?.lowercased() else { return false }
        return title.contains("college football playoff") || title.contains("national championship")
    }

    /// Worth keeping fresh without anyone asking: the Playoff, a ranked team, or a Power
    /// Four program. The server spends its per-game ESPN budget on these first.
    var isFeaturedCollegeGame: Bool {
        isCollegeFootballPlayoff || hasRankedTeam || collegeConferences.contains(where: \.isPower)
    }
}

/// A heading inside the football section. A game sits under the first one it matches,
/// in this order, so a ranked Big 12 game reads as Top 25 rather than appearing twice.
public enum FootballSection: Hashable, Comparable, Sendable {
    case nfl
    case playoff
    case top25
    case conference(CollegeConference)
    /// A followed team's game that none of the picked sections claims.
    case college

    public var title: String {
        switch self {
        case .nfl:                 return "NFL"
        case .playoff:             return "College Football Playoff"
        case .top25:               return "Top 25"
        case .conference(let c):   return c.displayName
        case .college:             return "College Football"
        }
    }

    private var order: Int {
        switch self {
        case .nfl:                 return 0
        case .playoff:             return 1
        case .top25:               return 2
        case .conference(let c):   return 3 + (CollegeConference.allCases.firstIndex(of: c) ?? 0)
        case .college:             return 100
        }
    }

    public static func < (lhs: FootballSection, rhs: FootballSection) -> Bool { lhs.order < rhs.order }
}

/// Which college games a user wants: the AP Top 25 and/or any set of conferences. Teams
/// the user follows show regardless, so an empty selection means "only my teams".
///
/// Stored as a comma-separated string ("top25,sec,big12") — in UserDefaults, iCloud, the
/// watch context and the `cfbSel` query parameter alike.
public struct CollegeFootballSelection: Equatable, Hashable, Sendable, RawRepresentable, Codable {
    public var top25: Bool
    public var conferences: Set<CollegeConference>

    public init(top25: Bool = false, conferences: Set<CollegeConference> = []) {
        self.top25 = top25
        self.conferences = conferences
    }

    /// The dozen or so games a week most fans care about.
    public static let `default` = CollegeFootballSelection(top25: true)
    public static let powerFour = CollegeFootballSelection(top25: true, conferences: CollegeConference.power)
    public static let allFBS = CollegeFootballSelection(top25: true, conferences: Set(CollegeConference.fbs))
    public static let followedOnly = CollegeFootballSelection()

    public static let storageKey = "cfbSelection"

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        top25 = parts.contains("top25")
        conferences = Set(parts.compactMap(CollegeConference.init(rawValue:)))
    }

    public var rawValue: String {
        ((top25 ? ["top25"] : []) + CollegeConference.allCases.filter(conferences.contains).map(\.rawValue))
            .joined(separator: ",")
    }

    /// Reads the stored selection, falling back to the default when unset.
    public static func stored(in defaults: UserDefaults?) -> CollegeFootballSelection {
        defaults?.string(forKey: storageKey).flatMap(CollegeFootballSelection.init(rawValue:)) ?? .default
    }

    public var isAllFBS: Bool { Set(CollegeConference.fbs).isSubset(of: conferences) }
    public var isFollowedOnly: Bool { !top25 && conferences.isEmpty }

    /// "Top 25, SEC, Big 12" / "All FBS" / "Teams I Follow".
    public var summary: String {
        if isAllFBS { return "All FBS" }
        if isFollowedOnly { return "Teams I Follow" }
        var names = top25 ? ["Top 25"] : []
        if conferences == CollegeConference.power {
            names.append("Power 4")
        } else {
            names += CollegeConference.allCases.filter(conferences.contains).map(\.displayName)
        }
        return names.joined(separator: ", ")
    }

    /// The section a college game belongs under, or nil when the selection doesn't
    /// include it. Followed teams land in `.college` when nothing else claims them.
    public func section(for game: Game, isFavorite: Bool = false) -> FootballSection? {
        guard game.isCollegeFootball else { return .nfl }
        let conferences = game.collegeConferences.filter(self.conferences.contains)
        let picked = top25 && game.hasRankedTeam || !conferences.isEmpty
        if game.isCollegeFootballPlayoff, top25 || picked { return .playoff }
        if top25, game.hasRankedTeam { return .top25 }
        if let first = conferences.min(by: { FootballSection.conference($0) < .conference($1) }) {
            return .conference(first)
        }
        return isFavorite ? .college : nil
    }

    /// Whether this selection shows `game`. Games from any other league always pass.
    public func admits(_ game: Game, isFavorite: Bool = false) -> Bool {
        section(for: game, isFavorite: isFavorite) != nil
    }
}

/// Which football a user wants. The NFL and college share the football bucket and the
/// football section, but are switched on separately, and college has its own selection.
/// One rule for the app, its widgets and the watch, so they never disagree.
public struct FootballPreference: Equatable, Sendable {
    public var showNFL: Bool
    public var showCollege: Bool
    public var college: CollegeFootballSelection

    public init(showNFL: Bool, showCollege: Bool, college: CollegeFootballSelection = .default) {
        self.showNFL = showNFL
        self.showCollege = showCollege
        self.college = college
    }

    /// Reads the app-group mirror the app writes (`shouldShowNFL`, `shouldShowCFB`,
    /// `cfbSelection`).
    public init(defaults: UserDefaults?) {
        self.init(
            showNFL: defaults?.bool(forKey: "shouldShowNFL") ?? false,
            showCollege: defaults?.bool(forKey: "shouldShowCFB") ?? false,
            college: CollegeFootballSelection.stored(in: defaults)
        )
    }

    /// Whether the football section should exist at all.
    public var isOn: Bool { showNFL || showCollege }

    /// Whether `game` from the football bucket should show. `isFavorite` is only evaluated
    /// for a college game the selection would drop, since the favorite lookup is the
    /// costly part.
    public func admits(_ game: Game, isFavorite: () -> Bool) -> Bool {
        guard game.isCollegeFootball else { return showNFL }
        guard showCollege else { return false }
        return college.admits(game) || college.admits(game, isFavorite: isFavorite())
    }

    /// Splits football games into headed groups — NFL first, then the Playoff, Top 25 and
    /// each picked conference — dropping any group left empty. Order within a group is
    /// kept. Games the preference wouldn't admit are dropped.
    public func sections(_ games: [Game], isFavorite: (Game) -> Bool) -> [(section: FootballSection, games: [Game])] {
        var grouped: [FootballSection: [Game]] = [:]
        for game in games {
            let section: FootballSection?
            if !game.isCollegeFootball {
                section = showNFL ? .nfl : nil
            } else if showCollege {
                section = college.section(for: game) ?? college.section(for: game, isFavorite: isFavorite(game))
            } else {
                section = nil
            }
            if let section { grouped[section, default: []].append(game) }
        }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }
}
