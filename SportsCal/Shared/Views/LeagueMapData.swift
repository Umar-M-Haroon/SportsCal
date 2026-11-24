//
//  LeagueMapData.swift
//  SportsCal
//
//  The data behind onboarding's league world map: where each league lives, the
//  starter packs, the region pre-picks and the dot-map land mask. Pure values so
//  the tables can be unit tested; `LeagueMapPage` draws them.
//

import CoreGraphics
import Foundation
import SportsCalModel

/// One league in a place's list.
struct LeagueMapEntry: Hashable, Identifiable {
    let league: Leagues
    /// When it's played ("Aug – May"), shown under the name.
    let season: String

    var id: Leagues { league }
    var sport: SportType { SportType(league: league) }
    var name: String { LeagueMap.name(league) }
}

/// A glowing spot on the map: a country or region and the leagues played there.
/// Worldwide has no coordinates; it opens from its own button.
struct LeagueMapHub: Hashable, Identifiable {
    let id: String
    let name: String
    let flag: String
    /// Longitude and latitude, or nil for Worldwide.
    let coordinate: (lon: Double, lat: Double)?
    /// Colours the spot. Nil means the app's accent (Worldwide).
    let sport: SportType?
    let leagues: [LeagueMapEntry]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Where the spot sits in map units (`LeagueMap.size`).
    var point: CGPoint? { coordinate.map { LeagueMap.project(lon: $0.lon, lat: $0.lat) } }

    /// Spot radius in map units: bigger for places with more going on.
    var radius: CGFloat { 4 + CGFloat(min(leagues.count, 13)) * 0.32 }

    func followedCount(in picked: some Collection<Leagues>) -> Int {
        leagues.filter { picked.contains($0.league) }.count
    }

    /// VoiceOver label: "England, 6 leagues, 2 followed".
    func accessibilityLabel(followed: Int) -> String {
        var label = "\(name), \(leagues.count) \(leagues.count == 1 ? "league" : "leagues")"
        if followed > 0 { label += ", \(followed) followed" }
        return label
    }
}

/// A league found by search, with the first place it's listed.
struct LeagueMapSearchMatch: Identifiable {
    let hub: LeagueMapHub
    let entry: LeagueMapEntry
    var id: Leagues { entry.league }
}

/// Spots close enough together that they need zooming into before they can be tapped.
struct LeagueMapCluster: Hashable, Identifiable {
    let id: String
    let hubIDs: Set<String>
    /// Where to centre the zoom, in map units.
    let centre: CGPoint

    /// Closest distance in map units between two of its spots, for working out how far
    /// to zoom so each gets a full-size target.
    var minimumSpacing: CGFloat {
        let points = LeagueMap.hubs.filter { hubIDs.contains($0.id) }.compactMap(\.point)
        var best = CGFloat.greatestFiniteMagnitude
        for (i, a) in points.enumerated() {
            for b in points[(i + 1)...] { best = min(best, hypot(a.x - b.x, a.y - b.y)) }
        }
        return best
    }

    /// Map scale (points per map unit) at which its spots sit `spacing` points apart.
    func scale(forSpacing spacing: CGFloat) -> CGFloat { spacing / minimumSpacing }
}

/// A one-tap bundle ("Top of Europe"). Each item names the hub it flashes.
struct LeagueMapPack: Hashable, Identifiable {
    let name: String
    let emoji: String
    let items: [(hub: String, league: Leagues)]

    var id: String { name }
    var leagues: [Leagues] { items.map(\.league) }
    var hubIDs: [String] { items.map(\.hub) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    func isOn(in picked: some Collection<Leagues>) -> Bool {
        leagues.allSatisfy { picked.contains($0) }
    }
}

/// What the map step has picked so far: teams (via search) and leagues, in the order
/// they were added, for the tray.
struct LeagueMapSelection: Equatable {
    var leagues: [Leagues] = []
    var teams: [Team] = []

    var isEmpty: Bool { leagues.isEmpty && teams.isEmpty }

    func contains(_ league: Leagues) -> Bool { leagues.contains(league) }

    mutating func add(_ league: Leagues) {
        if !leagues.contains(league) { leagues.append(league) }
    }

    mutating func remove(_ league: Leagues) {
        leagues.removeAll { $0 == league }
    }

    mutating func toggle(_ league: Leagues) {
        contains(league) ? remove(league) : add(league)
    }

    func containsTeam(_ team: Team) -> Bool {
        teams.contains { Self.key($0) == Self.key(team) }
    }

    mutating func add(team: Team, competitions: [Leagues]) {
        if !containsTeam(team) { teams.append(team) }
        competitions.forEach { add($0) }
    }

    mutating func remove(team: Team) {
        teams.removeAll { Self.key($0) == Self.key(team) }
    }

    private static func key(_ team: Team) -> String { team.idTeam ?? team.strTeam ?? "" }

    /// "Continue · 1 team, 8 leagues", or the nudge when nothing is picked.
    var continueTitle: String {
        guard !isEmpty else { return "Pick a League to Continue" }
        var parts: [String] = []
        if !teams.isEmpty { parts.append("\(teams.count) \(teams.count == 1 ? "team" : "teams")") }
        parts.append("\(leagues.count) \(leagues.count == 1 ? "league" : "leagues")")
        return "Continue · " + parts.joined(separator: ", ")
    }
}

enum LeagueMap {
    // MARK: Projection

    /// The map's own coordinate space, an equirectangular strip from 76°N to 58°S.
    static let size = CGSize(width: 360, height: 260)
    private static let latTop = 76.0, latBottom = -58.0

    static func project(lon: Double, lat: Double) -> CGPoint {
        CGPoint(x: (lon + 180) / 360 * size.width,
                y: (latTop - lat) / (latTop - latBottom) * size.height)
    }

    // MARK: Land mask

    /// Land longitude ranges per 5° latitude band (rough, it's a dot map).
    private static let bands: [(lat: Double, ranges: [(Double, Double)])] = [
        (72.5, [(-125, -70), (-70, -20), (15, 25), (60, 145)]),
        (67.5, [(-165, -140), (-140, -60), (-55, -30), (12, 30), (30, 180)]),
        (62.5, [(-165, -140), (-140, -65), (-50, -42), (-24, -14), (5, 30), (30, 180)]),
        (57.5, [(-160, -150), (-130, -60), (-7, -1), (8, 20), (22, 165)]),
        (52.5, [(-128, -56), (-10, 2), (2, 140), (155, 160)]),
        (47.5, [(-125, -53), (-5, 135), (140, 145)]),
        (42.5, [(-124, -70), (-9, 3), (8, 135), (139, 142)]),
        (37.5, [(-122, -76), (-9, -1), (12, 128), (132, 141)]),
        (32.5, [(-117, -80), (-10, 122), (130, 135)]),
        (27.5, [(-112, -97), (-82, -80), (-15, 57), (60, 122)]),
        (22.5, [(-106, -97), (-84, -75), (-17, 38), (40, 60), (68, 90), (92, 120)]),
        (17.5, [(-102, -88), (-16, 42), (43, 53), (73, 85), (95, 110), (120, 124)]),
        (12.5, [(-90, -83), (-72, -62), (-17, 45), (75, 80), (98, 108)]),
        (7.5, [(-80, -60), (-10, 48), (80, 82), (100, 104)]),
        (2.5, [(-80, -50), (9, 42), (95, 118)]),
        (-2.5, [(-80, -40), (10, 40), (100, 140)]),
        (-7.5, [(-79, -35), (12, 40), (105, 150)]),
        (-12.5, [(-77, -38), (13, 41), (45, 50), (130, 142)]),
        (-17.5, [(-72, -40), (12, 38), (44, 50), (122, 146)]),
        (-22.5, [(-70, -41), (14, 35), (44, 48), (114, 152)]),
        (-27.5, [(-70, -49), (15, 32), (114, 153)]),
        (-32.5, [(-72, -53), (18, 28), (116, 152)]),
        (-37.5, [(-73, -57), (140, 150), (175, 178)]),
        (-42.5, [(-74, -63), (145, 148), (170, 175)]),
        (-47.5, [(-75, -66), (167, 170)]),
        (-52.5, [(-74, -68)]),
    ]

    /// Every land dot, in map units: two rows per band, a dot every 2.5° of longitude.
    static let landDots: [CGPoint] = {
        var dots: [CGPoint] = []
        for band in bands {
            for lat in [band.lat + 1.25, band.lat - 1.25] {
                for (start, end) in band.ranges {
                    var lon = start
                    while lon <= end {
                        dots.append(project(lon: lon, lat: lat))
                        lon += 2.5
                    }
                }
            }
        }
        return dots
    }()

    // MARK: Places

    private static func e(_ league: Leagues, _ season: String) -> LeagueMapEntry {
        LeagueMapEntry(league: league, season: season)
    }

    static let hubs: [LeagueMapHub] = [
        LeagueMapHub(id: "US", name: "United States", flag: "🇺🇸", coordinate: (-98, 39), sport: .basketball, leagues: [
            e(.nfl, "Sep – Feb"), e(.nba, "Oct – Jun"), e(.mlb, "Mar – Oct"), e(.nhl, "Oct – Jun"),
            e(.MLS, "Feb – Dec"), e(.wnba, "May – Oct"), e(.ncaaf, "Aug – Jan"), e(.ncaaMBBTournament, "Nov – Apr"),
            e(.nascarCup, "Feb – Nov"), e(.indycar, "Mar – Sep"), e(.imsa, "Jan – Oct"),
            e(.pga, "Jan – Aug"), e(.kornFerry, "Jan – Oct"), e(.championsTour, "Jan – Nov"),
            e(.mlc, "Jun – Jul"),
        ]),
        LeagueMapHub(id: "CA", name: "Canada", flag: "🇨🇦", coordinate: (-80, 50), sport: .hockey, leagues: [
            e(.nhl, "Oct – Jun"), e(.MLS, "Feb – Dec"),
        ]),
        LeagueMapHub(id: "MX", name: "Mexico", flag: "🇲🇽", coordinate: (-101, 21), sport: .soccer, leagues: [
            e(.Liga_MX, "Jul – May"),
        ]),
        LeagueMapHub(id: "CAR", name: "Caribbean", flag: "🌴", coordinate: (-63, 14), sport: .cricket, leagues: [
            e(.cpl, "Aug – Sep"),
        ]),
        LeagueMapHub(id: "SA", name: "South America", flag: "🌎", coordinate: (-60, -25), sport: .soccer, leagues: [
            e(.Copa_America, "Summer 2028"),
        ]),
        LeagueMapHub(id: "GB", name: "England", flag: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", coordinate: (-2.5, 53), sport: .soccer, leagues: [
            e(.English_Premier_League, "Aug – May"), e(.English_League_Championship, "Aug – May"), e(.FA_Cup, "Nov – May"),
            e(.theHundred, "Aug"), e(.theHundredWomen, "Aug"), e(.countyChampionship, "Apr – Sep"),
        ]),
        LeagueMapHub(id: "NL", name: "Netherlands", flag: "🇳🇱", coordinate: (6, 56), sport: .soccer, leagues: [
            e(.Eredivisie, "Aug – May"),
        ]),
        LeagueMapHub(id: "FR", name: "France", flag: "🇫🇷", coordinate: (2, 46.5), sport: .soccer, leagues: [
            e(.Ligue_1, "Aug – May"), e(.Coupe_De_France, "Nov – May"),
        ]),
        LeagueMapHub(id: "ES", name: "Spain", flag: "🇪🇸", coordinate: (-4, 39.5), sport: .soccer, leagues: [
            e(.La_Liga, "Aug – May"), e(.Copa_del_Rey, "Oct – Apr"),
        ]),
        LeagueMapHub(id: "DE", name: "Germany", flag: "🇩🇪", coordinate: (11, 51), sport: .soccer, leagues: [
            e(.German_Bundesliga, "Aug – May"), e(.DFB_Pokal, "Aug – May"),
        ]),
        LeagueMapHub(id: "IT", name: "Italy", flag: "🇮🇹", coordinate: (13, 42), sport: .soccer, leagues: [
            e(.Serie_A, "Aug – May"),
        ]),
        LeagueMapHub(id: "EU", name: "Across Europe", flag: "🇪🇺", coordinate: (24, 48), sport: .soccer, leagues: [
            e(.UEFA_Champions_League, "Sep – May"), e(.UEFA_Europa_League, "Sep – May"),
            e(.UEFA_Conference_League, "Sep – May"), e(.UEFA_Nations_League, "Sep – Jun"), e(.dpWorld, "Nov – Nov"),
        ]),
        LeagueMapHub(id: "AE", name: "UAE", flag: "🇦🇪", coordinate: (55, 24), sport: .cricket, leagues: [
            e(.ilt20, "Jan – Feb"),
        ]),
        LeagueMapHub(id: "PK", name: "Pakistan", flag: "🇵🇰", coordinate: (69, 30), sport: .cricket, leagues: [
            e(.psl, "Feb – Mar"),
        ]),
        LeagueMapHub(id: "IN", name: "India", flag: "🇮🇳", coordinate: (79, 21), sport: .cricket, leagues: [
            e(.ipl, "Mar – May"),
        ]),
        LeagueMapHub(id: "ZA", name: "South Africa", flag: "🇿🇦", coordinate: (25, -29), sport: .cricket, leagues: [
            e(.sa20, "Jan – Feb"),
        ]),
        LeagueMapHub(id: "AU", name: "Australia", flag: "🇦🇺", coordinate: (136, -26), sport: .cricket, leagues: [
            e(.bigBash, "Dec – Jan"), e(.wbbl, "Oct – Nov"), e(.sheffieldShield, "Oct – Mar"), e(.A_League, "Oct – May"),
        ]),
    ]

    static let worldwide = LeagueMapHub(id: "WW", name: "Worldwide", flag: "🌐", coordinate: nil, sport: nil, leagues: [
        e(.FIFA_World_Cup, "Jun – Jul 2030"), e(.Womens_World_Cup, "Jun – Jul 2027"),
        e(.formula1, "Mar – Dec"), e(.wec, "Feb – Nov"),
        e(.atp, "All year"), e(.wta, "All year"), e(.livGolf, "Feb – Aug"), e(.lpga, "Jan – Nov"),
        e(.cricketTests, "All year"), e(.cricketODIs, "All year"), e(.cricketT20Is, "All year"),
        e(.womensCricketInternationals, "All year"),
    ])

    static var allHubs: [LeagueMapHub] { hubs + [worldwide] }

    static func hub(id: String) -> LeagueMapHub? { allHubs.first { $0.id == id } }

    /// Every place a league is listed (MLS is in the US and Canada).
    static func hubIDs(containing league: Leagues) -> [String] {
        allHubs.filter { $0.leagues.contains { $0.league == league } }.map(\.id)
    }

    /// Tight clusters of spots. From the whole map, a tap in one zooms in before opening
    /// anything, because at that size a thumb can't pick England from the Netherlands.
    static let clusters: [LeagueMapCluster] = [
        LeagueMapCluster(id: "europe", hubIDs: ["GB", "NL", "FR", "ES", "DE", "IT", "EU"], centre: project(lon: 7, lat: 48)),
        LeagueMapCluster(id: "southAsia", hubIDs: ["AE", "PK", "IN"], centre: project(lon: 68, lat: 25)),
    ]

    static func cluster(containing hubID: String) -> LeagueMapCluster? {
        clusters.first { $0.hubIDs.contains(hubID) }
    }

    // MARK: Packs

    static let packs: [LeagueMapPack] = [
        LeagueMapPack(name: "American big four", emoji: "🇺🇸",
                      items: [("US", .nfl), ("US", .nba), ("US", .mlb), ("US", .nhl)]),
        LeagueMapPack(name: "Top of Europe", emoji: "⚽️",
                      items: [("GB", .English_Premier_League), ("ES", .La_Liga), ("DE", .German_Bundesliga),
                              ("IT", .Serie_A), ("FR", .Ligue_1), ("EU", .UEFA_Champions_League)]),
        LeagueMapPack(name: "Cricket everywhere", emoji: "🏏",
                      items: [("WW", .cricketTests), ("WW", .cricketODIs), ("WW", .cricketT20Is),
                              ("IN", .ipl), ("AU", .bigBash)]),
        LeagueMapPack(name: "Motorsport", emoji: "🏁",
                      items: [("WW", .formula1), ("US", .indycar), ("US", .nascarCup)]),
        LeagueMapPack(name: "College game day", emoji: "🎓",
                      items: [("US", .ncaaf), ("US", .ncaaMBBTournament)]),
        LeagueMapPack(name: "Tennis & golf", emoji: "🎾",
                      items: [("WW", .atp), ("WW", .wta), ("US", .pga), ("EU", .dpWorld)]),
    ]

    // MARK: Region

    private static let caribbean: Set<String> = ["JM", "TT", "BB", "GY", "AG", "LC", "VC", "GD", "KN", "DM", "BS"]
    private static let southAmerica: Set<String> = ["BR", "AR", "CO", "CL", "UY", "PE", "EC", "PY", "BO", "VE"]
    private static let europe: Set<String> = ["PT", "BE", "AT", "CH", "SE", "NO", "DK", "FI", "PL", "CZ", "GR",
                                              "HR", "RS", "HU", "RO", "BG", "SK", "SI", "IS", "LU", "TR", "UA"]

    /// The spot that pulses for where the phone is set up.
    static func regionHubID(forRegion region: String?) -> String? {
        guard let code = region?.uppercased() else { return nil }
        switch code {
        case "US", "CA", "MX", "NL", "FR", "ES", "DE", "IT", "AE", "PK", "IN", "ZA", "AU": return code
        case "GB", "IE": return "GB"
        case "NZ": return "AU"
        case "LK", "BD", "AF": return "IN"
        default:
            if caribbean.contains(code) { return "CAR" }
            if southAmerica.contains(code) { return "SA" }
            if europe.contains(code) { return "EU" }
            return nil
        }
    }

    /// The first picks for a region, at league level, so the map never starts empty.
    /// Follows `OnboardingSportChoice.suggested(forRegion:)`: the big US leagues in the
    /// US, cricket across South Asia, cricket and soccer down under, soccer elsewhere.
    static func regionDefaults(forRegion region: String?) -> [Leagues] {
        let code = region?.uppercased() ?? ""
        switch code {
        case "US": return [.nfl, .nba]
        case "CA": return [.nhl, .nba]
        case "MX": return [.Liga_MX]
        case "GB", "IE": return [.English_Premier_League]
        case "DE": return [.German_Bundesliga]
        case "ES": return [.La_Liga]
        case "FR": return [.Ligue_1]
        case "IT": return [.Serie_A]
        case "NL": return [.Eredivisie]
        case "IN": return [.ipl]
        case "PK": return [.psl]
        case "LK", "BD", "AF": return [.cricketTests, .cricketODIs, .cricketT20Is]
        case "AU": return [.bigBash, .A_League]
        case "NZ": return [.cricketTests, .cricketODIs, .cricketT20Is, .A_League]
        case "ZA": return [.sa20, .English_Premier_League]
        case "AE": return [.ilt20]
        default:
            if caribbean.contains(code) { return [.cpl] }
            return [.English_Premier_League, .UEFA_Champions_League]
        }
    }

    // MARK: Names

    /// The name a fan would use, shorter than `leagueName` ("Premier League", not
    /// "English Premier League").
    static func name(_ league: Leagues) -> String {
        switch league {
        case .English_Premier_League: "Premier League"
        case .English_League_Championship: "Championship"
        case .German_Bundesliga: "Bundesliga"
        case .Coupe_De_France: "Coupe de France"
        case .Copa_del_Rey: "Copa del Rey"
        case .DFB_Pokal: "DFB-Pokal"
        case .Copa_America: "Copa América"
        case .UEFA_Champions_League: "Champions League"
        case .UEFA_Europa_League: "Europa League"
        case .UEFA_Conference_League: "Conference League"
        case .UEFA_Nations_League: "Nations League"
        case .Womens_World_Cup: "Women's World Cup"
        case .nascarCup: "NASCAR Cup"
        case .indycar: "IndyCar"
        case .imsa: "IMSA"
        case .wec: "World Endurance (WEC)"
        case .lpga: "LPGA"
        case .ipl: "IPL"
        case .bigBash: "Big Bash"
        case .wbbl: "WBBL"
        case .cpl: "Caribbean Premier League"
        case .cricketTests: "Test cricket"
        case .cricketODIs: "ODIs"
        case .womensCricketInternationals: "Women's internationals"
        default: league.leagueName
        }
    }

    // MARK: Search

    /// Leagues whose short or full name matches, once each, with the first place
    /// they're listed.
    static func leagues(matching query: String) -> [LeagueMapSearchMatch] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return [] }
        var seen: Set<Leagues> = []
        var results: [LeagueMapSearchMatch] = []
        for hub in allHubs {
            for entry in hub.leagues where !seen.contains(entry.league) {
                guard entry.name.localizedCaseInsensitiveContains(term)
                        || entry.league.leagueName.localizedCaseInsensitiveContains(term) else { continue }
                seen.insert(entry.league)
                results.append(LeagueMapSearchMatch(hub: hub, entry: entry))
            }
        }
        return results
    }

    /// Each team's competitions as seen in the schedule, own league first. The
    /// fallback for team search when the server's `/teams/competitions` isn't there.
    static func teamLeagues(from games: [Game]) -> [String: [Leagues]] {
        var result: [String: [Leagues]] = [:]
        for game in games {
            guard let league = game.idLeague.flatMap({ Int($0) }).flatMap(Leagues.init(rawValue:)) else { continue }
            for id in [game.idHomeTeam, game.idAwayTeam].compactMap({ $0 }) where !id.isEmpty {
                if !(result[id]?.contains(league) ?? false) { result[id, default: []].append(league) }
            }
        }
        return result.mapValues { leagues in
            leagues.sorted { l, r in
                let lc = l.isTeamCompetitionCupForMap, rc = r.isTeamCompetitionCupForMap
                if lc != rc { return !lc }
                return (l.competitionDisplayRank ?? .max) < (r.competitionDisplayRank ?? .max)
            }
        }
    }
}

private extension Leagues {
    /// `isTeamCompetitionCup` is internal to the model package; same rule here.
    var isTeamCompetitionCupForMap: Bool {
        switch self {
        case .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal,
             .UEFA_Champions_League, .UEFA_Europa_League, .UEFA_Conference_League,
             .UEFA_Nations_League, .FIFA_World_Cup, .Womens_World_Cup, .Copa_America:
            return true
        default:
            return false
        }
    }
}
