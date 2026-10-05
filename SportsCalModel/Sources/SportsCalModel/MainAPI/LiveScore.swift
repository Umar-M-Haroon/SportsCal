//
//  LiveScore.swift
//  
//
//  Created by Umar Haroon on 10/22/22.
//

import Foundation
public enum Leagues: Int, Codable, CaseIterable, Equatable {
    case English_Premier_League = 4328
    case English_League_Championship = 4329
    case German_Bundesliga = 4331
    case Serie_A = 4332
    case Ligue_1 = 4334
    case La_Liga = 4335
    case Eredivisie = 4337
    case MLS = 4346
    case Liga_MX = 4350
    case A_League = 4356
    case FIFA_World_Cup = 4429
    case UEFA_Champions_League = 4480
    case UEFA_Europa_League = 4481
    case FA_Cup = 4482
    case Copa_del_Rey = 4483
    case Coupe_De_France = 4484
    case DFB_Pokal = 4485
    case UEFA_Nations_League = 4490
    case Copa_America = 4499
    case UEFA_Conference_League = 5071
    case Womens_World_Cup = 4565
    
    case nfl = 4391
    case nba = 4387
    case nhl = 4380
    case mlb = 4424

    case pga = 4425
    // Golf tours beyond the PGA TOUR are ESPN-only, so they carry ESPN's own league IDs
    // (TheSportsDB has no entry to key them by).
    case championsTour = 1105
    case lpga = 1107
    case livGolf = 1109
    case kornFerry = 7001
    case dpWorld = 7002
    case atp = 4464
    case wta = 4517

    case formula1 = 4370
    /// NASCAR Cup Series. Keyed by TheSportsDB's ID, but sourced entirely from NASCAR's own
    /// feeds (`cf.nascar.com`), which carry far more than ESPN or TheSportsDB: every lap,
    /// stage, caution and pit stop. Off by default; see `isHiddenByDefault`.
    case nascarCup = 4393

    case ncaaMBBTournament = 100
    case wnba = 101
    /// FBS college football. ESPN-only, and rides in the football bucket next to the NFL
    /// the way the WNBA rides with the NBA — but on the wire it is split out into its own
    /// `ncaaf` key (see `LiveScore`'s Codable) so app versions that predate it never see it.
    case ncaaf = 102

    /// Soccer is the default here: the enum is mostly soccer leagues, so this is defined
    /// by exclusion.
    ///
    /// Both of these are called once per game inside filter closures that run over the
    /// whole schedule. They used to build an array literal and scan it linearly on every
    /// call; a `switch` decides it without allocating.
    public var isSoccer: Bool {
        switch self {
        case .nfl, .nba, .nhl, .mlb, .pga, .atp, .wta, .formula1, .nascarCup, .ncaaMBBTournament, .wnba, .ncaaf,
             .championsTour, .lpga, .livGolf, .kornFerry, .dpWorld:
            return false
        default:
            return true
        }
    }

    /// Leagues that start out hidden until the user turns them on in Settings. Seeded
    /// into `hiddenCompetitions` once per league, so turning one on sticks.
    public var isHiddenByDefault: Bool {
        self == .A_League || self == .nascarCup
    }

    public var isBasketball: Bool {
        switch self {
        case .nba, .ncaaMBBTournament, .wnba: return true
        default: return false
        }
    }

    public var isFootball: Bool {
        switch self {
        case .nfl, .ncaaf: return true
        default: return false
        }
    }

    public var isGolf: Bool {
        switch self {
        case .pga, .championsTour, .lpga, .livGolf, .kornFerry, .dpWorld: return true
        default: return false
        }
    }

    public var isTennis: Bool {
        return [Leagues.atp, Leagues.wta].contains(self)
    }

    public var isRacing: Bool {
        switch self {
        case .formula1, .nascarCup: return true
        default: return false
        }
    }

    /// Racing series other than Formula 1. App versions that predate them render every
    /// racing game as an F1 weekend, so on the wire they travel under their own
    /// `motorsport` key (see `LiveScore`'s Codable) and flat `[Game]` routes leave them
    /// out unless the request sends `motorsport=1`.
    public var isMotorsportSeries: Bool {
        isRacing && self != .formula1
    }

    /// Sport bucket used to namespace ESPN team IDs in the cross-sport ID map,
    /// preventing collisions where ESPN reuses the same numeric ID across sports.
    public var sportBucket: String {
        if isBasketball { return "nba" }
        if self == .nfl { return "nfl" }
        // College IDs overlap the NFL's 1–34, so they get a bucket of their own.
        if self == .ncaaf { return "ncaaf" }
        if self == .nhl { return "nhl" }
        if self == .mlb { return "mlb" }
        if isGolf { return "golf" }
        if isTennis { return "tennis" }
        if isRacing { return "racing" }
        return "soccer"
    }
    
    public init?(slug: String) {
        switch slug {
        case "uefa.champions":
            self = .UEFA_Champions_League
        case "uefa.europa":
            self = .UEFA_Europa_League
        case "uefa.europa.conf":
            self = .UEFA_Conference_League
        case "eng.1":
            self = .English_Premier_League
        case "eng.fa":
            self = .FA_Cup
        case "esp.1":
            self = .La_Liga
        case "esp.copa_del_rey":
            self = .Copa_del_Rey
        case "ger.1":
            self = .German_Bundesliga
        case "usa.1":
            self = .MLS
        case "ita.1":
            self = .Serie_A
        case "fra.1":
            self = .Ligue_1
        case "fra.coupe_de_france":
            self = .Coupe_De_France
        case "eng.2":
            self = .English_League_Championship
        case "ned.1":
            self = .Eredivisie
        case "ger.dfb_pokal":
            self = .DFB_Pokal
        case "mex.1":
            self = .Liga_MX
        case "aus.1":
            self = .A_League
        case "nba":
            self = .nba
        case "nhl":
            self = .nhl
        case "nfl":
            self = .nfl
        case "mlb":
            self = .mlb
        case "fifa.world":
            self = .FIFA_World_Cup
        case "uefa.nations":
            self = .UEFA_Nations_League
        case "conmebol.america":
            self = .Copa_America
        case "fifa.wwc":
            self = .Womens_World_Cup
        case "pga":
            self = .pga
        case "champions-tour":
            self = .championsTour
        case "lpga":
            self = .lpga
        case "liv":
            self = .livGolf
        case "ntw":
            self = .kornFerry
        case "eur":
            self = .dpWorld
        case "atp":
            self = .atp
        case "wta":
            self = .wta
        case "f1":
            self = .formula1
        case "mens-college-basketball":
            self = .ncaaMBBTournament
        case "wnba":
            self = .wnba
        case "college-football":
            self = .ncaaf
        default:
            return nil
        }
    }
    
    public var espnSlug: String? {
        switch self {
        case .UEFA_Champions_League:
            return "uefa.champions"
        case .UEFA_Europa_League:
            return "uefa.europa"
        case .UEFA_Conference_League:
            return "uefa.europa.conf"
        case .English_Premier_League:
            return "eng.1"
        case .FA_Cup:
            return "eng.fa"
        case .La_Liga:
            return "esp.1"
        case .Copa_del_Rey:
            return "esp.copa_del_rey"
        case .German_Bundesliga:
            return "ger.1"
        case .MLS:
            return "usa.1"
        case .Serie_A:
            return "ita.1"
        case .Ligue_1:
            return "fra.1"
        case .Coupe_De_France:
            return "fra.coupe_de_france"
        case .English_League_Championship:
            return "eng.2"
        case .Eredivisie:
            return "ned.1"
        case .DFB_Pokal:
            return "ger.dfb_pokal"
        case .Liga_MX:
            return "mex.1"
        case .A_League:
            return "aus.1"
        case .nba:
            return "nba"
        case .nhl:
            return "nhl"
        case .nfl:
            return "nfl"
        case .mlb:
            return "mlb"
        case .FIFA_World_Cup:
            return "fifa.world"
        case .UEFA_Nations_League:
            return "uefa.nations"
        case .Copa_America:
            return "conmebol.america"
        case .Womens_World_Cup:
            return "fifa.wwc"
        case .pga:
            return "pga"
        case .championsTour:
            return "champions-tour"
        case .lpga:
            return "lpga"
        case .livGolf:
            return "liv"
        case .kornFerry:
            return "ntw"
        case .dpWorld:
            return "eur"
        case .atp:
            return "atp"
        case .wta:
            return "wta"
        case .formula1:
            return "f1"
        case .ncaaMBBTournament:
            return "mens-college-basketball"
        case .wnba:
            return "wnba"
        case .ncaaf:
            return "college-football"
        default:
            return nil
        }
    }
    
    public var leagueName: String {
        switch self {
        case .English_Premier_League:
            return "English Premier League"
        case .English_League_Championship:
            return "English Championship"
        case .German_Bundesliga:
            return "Bundesliga"
        case .Serie_A:
            return "Serie A"
        case .Ligue_1:
            return "Ligue 1"
        case .La_Liga:
            return "La Liga"
        case .Eredivisie:
            return "Eredivisie"
        case .MLS:
            return "MLS"
        case .Liga_MX:
            return "Liga MX"
        case .A_League:
            return "A-League"
        case .FIFA_World_Cup:
            return "FIFA World Cup"
        case .UEFA_Champions_League:
            return "UEFA Champions League"
        case .UEFA_Europa_League:
            return "UEFA Europa League"
        case .FA_Cup:
            return "FA Cup"
        case .Copa_del_Rey:
            return "Copa Del Rey"
        case .Coupe_De_France:
            return "Coupe De France"
        case .DFB_Pokal:
            return "DFB Pokal"
        case .UEFA_Nations_League:
            return "UEFA Nations League"
        case .Copa_America:
            return "Copa America"
        case .UEFA_Conference_League:
            return "UEFA Conference League"
        case .nfl:
            return "NFL"
        case .mlb:
            return "MLB"
        case .nhl:
            return "NHL"
        case .nba:
            return "NBA"
        case .Womens_World_Cup:
            return "FIFA Women's World Cup"
        case .pga:
            return "PGA Tour"
        case .championsTour:
            return "PGA Tour Champions"
        case .lpga:
            return "LPGA Tour"
        case .livGolf:
            return "LIV Golf"
        case .kornFerry:
            return "Korn Ferry Tour"
        case .dpWorld:
            return "DP World Tour"
        case .atp:
            return "ATP Tour"
        case .wta:
            return "WTA Tour"
        case .formula1:
            return "Formula 1"
        case .nascarCup:
            return "NASCAR Cup Series"
        case .ncaaMBBTournament:
            return "March Madness"
        case .wnba:
            return "WNBA"
        case .ncaaf:
            return "College Football"
        }
    }

    public var sport: String {
        switch self {
        case .English_Premier_League, .English_League_Championship, .German_Bundesliga, .Serie_A, .Ligue_1, .La_Liga, .Eredivisie, .MLS, .Liga_MX, .A_League, .FIFA_World_Cup, .UEFA_Champions_League, .UEFA_Europa_League, .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal, .UEFA_Nations_League, .Copa_America, .UEFA_Conference_League, .Womens_World_Cup:
            return "soccer"
        case .nfl, .ncaaf:
            return "football"
        case .nba, .ncaaMBBTournament, .wnba:
            return "basketball"
        case .nhl:
            return "hockey"
        case .mlb:
            return "baseball"
        case .pga, .championsTour, .lpga, .livGolf, .kornFerry, .dpWorld:
            return "golf"
        case .atp, .wta:
            return "tennis"
        case .formula1, .nascarCup:
            return "racing"
        }
    }

    /// ESPN CDN logo URL for this league (light mode)
    public var logoURL: URL? {
        if let direct = directLogoURL { return URL(string: direct) }
        guard let id = espnLogoID else { return nil }
        return URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500/\(id).png")
    }

    /// ESPN CDN logo URL for this league (dark mode)
    public var darkLogoURL: URL? {
        if let direct = directDarkLogoURL { return URL(string: direct) }
        guard let id = espnLogoID else { return nil }
        return URL(string: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/\(id).png")
    }

    /// Direct logo URLs for non-soccer leagues
    private var directLogoURL: String? {
        switch self {
        case .nba: return "https://a.espncdn.com/i/teamlogos/leagues/500/nba.png"
        case .ncaaMBBTournament: return "https://a.espncdn.com/i/teamlogos/ncaa/500/2.png"
        case .wnba: return "https://a.espncdn.com/i/teamlogos/leagues/500/wnba.png"
        case .ncaaf: return "https://a.espncdn.com/redesign/assets/img/icons/ESPN-icon-football-college.png"
        default: return nil
        }
    }

    private var directDarkLogoURL: String? {
        switch self {
        case .nba: return "https://a.espncdn.com/i/teamlogos/leagues/500-dark/nba.png"
        case .ncaaMBBTournament: return "https://a.espncdn.com/i/teamlogos/ncaa/500/2.png"
        case .wnba: return "https://a.espncdn.com/i/teamlogos/leagues/500-dark/wnba.png"
        case .ncaaf: return "https://a.espncdn.com/redesign/assets/img/icons/ESPN-icon-football-college.png"
        default: return nil
        }
    }

    /// ESPN internal league ID used for logo URLs (only soccer leagues)
    private var espnLogoID: String? {
        switch self {
        case .English_Premier_League: return "23"
        case .English_League_Championship: return "24"
        case .German_Bundesliga: return "10"
        case .Serie_A: return "12"
        case .Ligue_1: return "9"
        case .La_Liga: return "15"
        case .Eredivisie: return "11"
        case .MLS: return "19"
        case .Liga_MX: return "22"
        case .A_League: return "1308"
        case .FIFA_World_Cup: return "4"
        case .UEFA_Champions_League: return "2"
        case .UEFA_Europa_League: return "2310"
        case .FA_Cup: return "40"
        case .Copa_del_Rey: return "80"
        case .Coupe_De_France: return "182"
        case .DFB_Pokal: return "2061"
        case .UEFA_Nations_League: return "2395"
        case .Copa_America: return "83"
        case .UEFA_Conference_League: return "20296"
        case .Womens_World_Cup: return "60"
        case .nfl, .nba, .nhl, .mlb, .pga, .atp, .wta, .formula1, .nascarCup, .ncaaMBBTournament, .wnba, .ncaaf,
             .championsTour, .lpga, .livGolf, .kornFerry, .dpWorld: return nil
        }
    }

    /// Whether this league uses single-year season format (e.g., "2025") instead of "2024-2025"
    public var usesSingleYearSeason: Bool {
        switch self {
        case .atp, .wta, .pga, .formula1, .nascarCup, .championsTour, .lpga, .livGolf, .kornFerry, .dpWorld:
            return true
        default:
            return false
        }
    }

    /// Whether TheSportsDB labels this league's seasons with a single year ("2026")
    /// instead of a split year ("2025-2026"). MLB and NFL are single-year there even
    /// though they are not individual sports — distinct from `usesSingleYearSeason`,
    /// which also gates whole-year ESPN scoreboard fetches.
    public var sportsDBSingleYearSeason: Bool {
        switch self {
        case .atp, .wta, .pga, .formula1, .nascarCup, .mlb, .nfl,
             .championsTour, .lpga, .livGolf, .kornFerry, .dpWorld:
            return true
        default:
            return false
        }
    }
}
public struct LiveScore: Equatable {
    public init(nba: LiveEvent? = nil, mlb: LiveEvent? = nil, soccer: LiveEvent? = nil, nfl: LiveEvent? = nil, nhl: LiveEvent? = nil, golf: LiveEvent? = nil, tennis: LiveEvent? = nil, racing: LiveEvent? = nil, f1Standings: F1Standings? = nil, worldCup: WorldCupEnrichment? = nil) {
        self.nba = nba
        self.mlb = mlb
        self.soccer = soccer
        self.nfl = nfl
        self.nhl = nhl
        self.golf = golf
        self.tennis = tennis
        self.racing = racing
        self.f1Standings = f1Standings
        self.worldCup = worldCup
    }

    public var nba: LiveEvent?
    public var mlb: LiveEvent?
    public var soccer: LiveEvent?
    public var nfl: LiveEvent?
    public var nhl: LiveEvent?
    public var golf: LiveEvent?
    public var tennis: LiveEvent?
    public var racing: LiveEvent?
    public var f1Standings: F1Standings?
    public var worldCup: WorldCupEnrichment?

    public func event(for sport: SportType) -> LiveEvent? {
        switch sport {
        case .basketball: return nba
        case .mlb:        return mlb
        case .soccer:     return soccer
        case .nfl:        return nfl
        case .hockey:     return nhl
        case .golf:       return golf
        case .tennis:     return tennis
        case .racing:     return racing
        }
    }

    /// Merges two LiveScore objects, combining events per sport
    public func merging(with other: LiveScore?) -> LiveScore {
        guard let other else { return self }
        return LiveScore(
            nba: LiveEvent.merging(self.nba, other.nba),
            mlb: LiveEvent.merging(self.mlb, other.mlb),
            soccer: LiveEvent.merging(self.soccer, other.soccer),
            nfl: LiveEvent.merging(self.nfl, other.nfl),
            nhl: LiveEvent.merging(self.nhl, other.nhl),
            golf: LiveEvent.merging(self.golf, other.golf),
            tennis: LiveEvent.merging(self.tennis, other.tennis),
            racing: LiveEvent.merging(self.racing, other.racing),
            f1Standings: self.f1Standings ?? other.f1Standings,
            worldCup: self.worldCup ?? other.worldCup
        )
    }

    mutating public func removeNonStarting() {
        nba?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        mlb?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        soccer?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        nfl?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        nhl?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        golf?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        tennis?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
        racing?.events.removeAll(where: { event in
            event.hasDoneStatus
        })
    }
    /// Removes games still flagged as in-progress whose scheduled start was more than
    /// `staleAfter` seconds before `now`. Handles the case where ESPN stopped returning a
    /// game before we fetched its final state, leaving the cache pinned to a mid-game
    /// snapshot. Matches the 8-hour "could still be live" heuristic used elsewhere.
    @discardableResult
    mutating public func removeStaleLiveGames(now: Date = Date(), staleAfter: TimeInterval = 8 * 60 * 60) -> Int {
        let cutoff = now.addingTimeInterval(-staleAfter)
        var removed = 0
        func prune(_ event: inout LiveEvent?) {
            guard event != nil else { return }
            let before = event!.events.count
            event!.events.removeAll { game in
                guard !game.hasDoneStatus else { return false }
                guard let gameDate = game.isoDate ?? game.getDate(dateFormatter: DateFormatter(), isoFormatter: ISO8601DateFormatter()) else { return false }
                return gameDate < cutoff
            }
            removed += before - event!.events.count
        }
        prune(&nba)
        prune(&mlb)
        prune(&soccer)
        prune(&nfl)
        prune(&nhl)
        prune(&golf)
        prune(&tennis)
        prune(&racing)
        return removed
    }

    mutating public func removeOtherInfo() {
        soccer?.events.removeAll(where: { event in
            guard let idLeague = event.idLeague,
                  let leagueID = Int(idLeague) else { return true }
            return !Leagues.allCases.map({$0.rawValue}).contains(leagueID)
        })
        tennis?.events.removeAll(where: { event in
            guard let idLeague = event.idLeague,
                  let leagueID = Int(idLeague) else { return true }
            return !Leagues.allCases.map({$0.rawValue}).contains(leagueID)
        })
    }
}

// MARK: - Codable

/// College football lives in the `nfl` bucket in memory — the same place everything
/// football-shaped is handled, so live merges, push-to-start and Live Activities need no
/// special case — but travels under its own `ncaaf` key.
///
/// App versions that predate college football read the `nfl` bucket with no league
/// filter: sharing the key would put ~950 college games a season into their NFL
/// schedule. Splitting on encode means they never see one; folding on decode means
/// everything that knows about it (this server, Redis round-trips, current clients)
/// still sees one football bucket.
///
/// Racing series other than F1 (NASCAR, …) get the same treatment under `motorsport`:
/// app versions that predate them render every game in `racing` as a Formula 1 weekend.
extension LiveScore: Codable {
    enum CodingKeys: String, CodingKey {
        case nba, mlb, soccer, nfl, ncaaf, nhl, golf, tennis, racing, motorsport, f1Standings, worldCup
    }

    /// Lenient per sport: a bucket that fails outright (not an object, no `events`)
    /// reads as nil without touching the other sports; within a bucket, malformed games
    /// are skipped (`LiveEvent`); a malformed `f1Standings`/`worldCup` reads as nil.
    /// Every recovery is batched into one `ModelDecodeDiagnostics` report per decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        (nba, mlb, soccer, nfl, nhl, golf, tennis, racing, f1Standings, worldCup) = ModelDecodeDiagnostics.batching("LiveScore") {
            (
                container.decodeLenient(LiveEvent.self, forKey: .nba),
                container.decodeLenient(LiveEvent.self, forKey: .mlb),
                container.decodeLenient(LiveEvent.self, forKey: .soccer),
                LiveEvent.merging(
                    container.decodeLenient(LiveEvent.self, forKey: .nfl),
                    container.decodeLenient(LiveEvent.self, forKey: .ncaaf)
                ),
                container.decodeLenient(LiveEvent.self, forKey: .nhl),
                container.decodeLenient(LiveEvent.self, forKey: .golf),
                container.decodeLenient(LiveEvent.self, forKey: .tennis),
                LiveEvent.merging(
                    container.decodeLenient(LiveEvent.self, forKey: .racing),
                    container.decodeLenient(LiveEvent.self, forKey: .motorsport)
                ),
                container.decodeLenient(F1Standings.self, forKey: .f1Standings),
                container.decodeLenient(WorldCupEnrichment.self, forKey: .worldCup)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(nba, forKey: .nba)
        try container.encodeIfPresent(mlb, forKey: .mlb)
        try container.encodeIfPresent(soccer, forKey: .soccer)
        if let nfl {
            let college = nfl.events.filter(\.isCollegeFootball)
            if college.isEmpty {
                try container.encode(nfl, forKey: .nfl)
            } else {
                // A bucket that held only college games still goes out as an empty `nfl`:
                // nil and empty read differently to a delta merge.
                try container.encode(LiveEvent(events: nfl.events.filter { !$0.isCollegeFootball }), forKey: .nfl)
                try container.encode(LiveEvent(events: college), forKey: .ncaaf)
            }
        }
        try container.encodeIfPresent(nhl, forKey: .nhl)
        try container.encodeIfPresent(golf, forKey: .golf)
        try container.encodeIfPresent(tennis, forKey: .tennis)
        if let racing {
            let series = racing.events.filter(\.isMotorsportSeries)
            if series.isEmpty {
                try container.encode(racing, forKey: .racing)
            } else {
                // As with `nfl` above: a racing bucket that held only other series still
                // goes out as an empty `racing`, because nil and empty differ to a delta merge.
                try container.encode(LiveEvent(events: racing.events.filter { !$0.isMotorsportSeries }), forKey: .racing)
                try container.encode(LiveEvent(events: series), forKey: .motorsport)
            }
        }
        try container.encodeIfPresent(f1Standings, forKey: .f1Standings)
        try container.encodeIfPresent(worldCup, forKey: .worldCup)
    }
}

// MARK: - Per-sport slices

/// The schedule split the way it travels: one slice per top-level JSON key, each with its
/// own ETag on `/schedules/sports/:key`, so an app downloads only the sports it shows and
/// a change in one sport doesn't invalidate the others.
public extension LiveScore {
    enum WireKey: String, CaseIterable, Codable, Sendable {
        case nba, mlb, soccer, nfl, ncaaf, nhl, golf, tennis, racing, motorsport
        /// Top-level enrichment (F1 standings, World Cup).
        case meta

        /// The JSON members this slice carries.
        public var members: [String] {
            self == .meta ? ["f1Standings", "worldCup"] : [rawValue]
        }
    }

    /// The slices that make up `sport`. College football and racing series beyond F1
    /// are their own slices, fetched only when the user has them on.
    static func wireKeys(for sport: SportType, college: Bool, motorsport: Bool) -> [WireKey] {
        switch sport {
        case .basketball: [.nba]
        case .mlb: [.mlb]
        case .soccer: [.soccer]
        case .nfl: college ? [.nfl, .ncaaf] : [.nfl]
        case .hockey: [.nhl]
        case .golf: [.golf]
        case .tennis: [.tennis]
        case .racing: motorsport ? [.racing, .motorsport] : [.racing]
        }
    }

    /// The part of this schedule that travels under `key`.
    func slice(_ key: WireKey) -> LiveScore {
        func only(_ event: LiveEvent?, _ keep: (Game) -> Bool) -> LiveEvent? {
            event.map { LiveEvent(events: $0.events.filter(keep)) }
        }
        switch key {
        case .nba: return LiveScore(nba: nba)
        case .mlb: return LiveScore(mlb: mlb)
        case .soccer: return LiveScore(soccer: soccer)
        case .nfl: return LiveScore(nfl: only(nfl) { !$0.isCollegeFootball })
        case .ncaaf: return LiveScore(nfl: only(nfl) { $0.isCollegeFootball })
        case .nhl: return LiveScore(nhl: nhl)
        case .golf: return LiveScore(golf: golf)
        case .tennis: return LiveScore(tennis: tennis)
        case .racing: return LiveScore(racing: only(racing) { !$0.isMotorsportSeries })
        case .motorsport: return LiveScore(racing: only(racing) { $0.isMotorsportSeries })
        case .meta: return LiveScore(f1Standings: f1Standings, worldCup: worldCup)
        }
    }

    /// One schedule from slices: games concatenated per bucket, enrichment from
    /// whichever slice carries it.
    static func combining(_ parts: [LiveScore]) -> LiveScore {
        parts.reduce(into: LiveScore()) { result, part in
            result = LiveScore(
                nba: LiveEvent.merging(result.nba, part.nba),
                mlb: LiveEvent.merging(result.mlb, part.mlb),
                soccer: LiveEvent.merging(result.soccer, part.soccer),
                nfl: LiveEvent.merging(result.nfl, part.nfl),
                nhl: LiveEvent.merging(result.nhl, part.nhl),
                golf: LiveEvent.merging(result.golf, part.golf),
                tennis: LiveEvent.merging(result.tennis, part.tennis),
                racing: LiveEvent.merging(result.racing, part.racing),
                f1Standings: result.f1Standings ?? part.f1Standings,
                worldCup: result.worldCup ?? part.worldCup
            )
        }
    }
}
