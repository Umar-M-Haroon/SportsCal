//
//  File.swift
//  
//
//  Created by Umar Haroon on 2/28/23.
//

import Foundation
import Vapor
import SportsCalModel
import Logging

class ESPNNetworking {
    private static let logger = Logger(label: "com.sportscal.espn")

    // Per-league cool-down to avoid hammering ESPN on 429/5xx or transport failures.
    // Single-process, in-memory — cleared on restart (which is fine: we'd recheck anyway).
    private static let cooldownQueue = DispatchQueue(label: "com.sportscal.espn.cooldown")
    private static var cooldownUntil: [Leagues: Date] = [:]
    private static let cooldownInterval: TimeInterval = 5 * 60

    // Global cool-down: any ESPN endpoint returning 429 trips this, halting all
    // ESPN traffic across sports/leagues for the Retry-After window. 429 is the
    // explicit rate-limit signal — 5xx stays per-league because it's typically
    // per-endpoint flakiness rather than a quota issue.
    private static var globalCooldownUntil: Date?
    private static let defaultGlobalCooldown: TimeInterval = 60

    private static func cooledDownUntil(_ league: Leagues) -> Date? {
        cooldownQueue.sync {
            guard let until = cooldownUntil[league], until > Date() else {
                if cooldownUntil[league] != nil { cooldownUntil[league] = nil }
                return nil
            }
            return until
        }
    }

    private static func markCooldown(_ league: Leagues, reason: String) {
        let until = Date().addingTimeInterval(cooldownInterval)
        cooldownQueue.sync { cooldownUntil[league] = until }
        logger.warning("ESPN league cooled down", metadata: [
            "league": "\(league)",
            "until":  "\(until)",
            "reason": "\(reason)"
        ])
    }

    private static func currentGlobalCooldown() -> Date? {
        cooldownQueue.sync {
            guard let until = globalCooldownUntil, until > Date() else {
                if globalCooldownUntil != nil { globalCooldownUntil = nil }
                return nil
            }
            return until
        }
    }

    private static func markGlobalCooldown(reason: String, duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        cooldownQueue.sync {
            // Extend only — never shorten an existing cooldown.
            if let existing = globalCooldownUntil, existing > until { return }
            globalCooldownUntil = until
        }
        logger.warning("ESPN global cooldown set", metadata: [
            "until":    "\(until)",
            "reason":   "\(reason)",
            "duration": "\(Int(duration))s"
        ])
    }

    /// Parses the `Retry-After` header (integer seconds form) into a clamped duration.
    /// Returns nil if absent or unparseable; HTTP-date form is ignored (we don't see it from ESPN).
    private static func retryAfterSeconds(from headers: HTTPHeaders) -> Int? {
        guard let raw = headers.first(name: "Retry-After") else { return nil }
        guard let seconds = Int(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return max(30, min(600, seconds))
    }

    /// Wraps `req.get` with the global 429 circuit breaker. All ESPN HTTP calls route
    /// through this so a rate-limit response on any endpoint halts all ESPN traffic for
    /// the cool-down window, rather than each endpoint independently hammering.
    ///
    /// Also retries once on transport-level errors (HTTP/2 stream reset, remote connection
    /// closed). ESPN's edge periodically tears down HTTP/2 connections with in-flight
    /// streams; retrying after a short delay lands on a fresh connection ~all of the time.
    /// Does not retry once a response has arrived — 429/5xx paths are handled below.
    private static func performGet(
        _ req: some Client,
        _ uri: URI,
        beforeSend: (inout ClientRequest) throws -> Void = { _ in }
    ) async throws -> ClientResponse {
        if let until = currentGlobalCooldown() {
            throw NetworkError.cooledDown(until: until)
        }
        let response: ClientResponse
        do {
            response = try await req.get(uri, beforeSend: beforeSend)
        } catch {
            logger.debug("ESPN GET transport error — retrying once", metadata: [
                "uri":   "\(uri)",
                "error": "\(error)"
            ])
            try await Task.sleep(nanoseconds: 200_000_000)
            if let until = currentGlobalCooldown() {
                // A concurrent request may have tripped the breaker during our sleep.
                throw NetworkError.cooledDown(until: until)
            }
            response = try await req.get(uri, beforeSend: beforeSend)
        }
        if response.status.code == 429 {
            let duration = TimeInterval(retryAfterSeconds(from: response.headers) ?? Int(defaultGlobalCooldown))
            markGlobalCooldown(reason: "http 429", duration: duration)
            throw NetworkError.cooledDown(until: Date().addingTimeInterval(duration))
        }
        return response
    }

    @available(*, deprecated, message: "use league lookup")
    static func getScoreboard<Output: Decodable>(req: some Client, DecodeType: Output.Type, scoreType: SportType) async throws -> Output {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/"
        guard let sport = decodeSportToPath(sport: scoreType) else { throw NetworkError.invalidLeague }
        let scoreboard = "/scoreboard"
        let fullString = urlString + sport + scoreboard
        do {
            let response = try await performGet(req, URI(string: fullString)) { req in
                try req.query.encode(["limit" : 500])
            }
            return try response.content.decode(DecodeType.self)
        } catch {
            logger.error("ESPN scoreboard fetch failed", metadata: [
                "sport": "\(scoreType)",
                "url": "\(fullString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    static func getScoreboard<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues, dates: Int? = nil) async throws -> Output {
        if let until = cooledDownUntil(league) {
            throw NetworkError.cooledDown(until: until)
        }
        if let espnSlug = league.espnSlug {
            let urlString = "https://site.api.espn.com/apis/site/v2/sports"
            let scoreboard = "scoreboard"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, scoreboard].joined(separator: "/")
            do {
                var uri = URI(string: fullString)
                uri.query = "limit=500"
                if let dates {
                    uri.query! += "&dates=\(dates)"
                } else if league.usesSingleYearSeason {
                    let year = Calendar.current.component(.year, from: Date())
                    uri.query! += "&dates=\(year)"
                }
                let response = try await performGet(req, uri)
                if response.status.code >= 500 {
                    markCooldown(league, reason: "http \(response.status.code)")
                    throw NetworkError.cooledDown(until: Date().addingTimeInterval(cooldownInterval))
                }
                return try response.content.decode(DecodeType.self)
            } catch let error as NetworkError {
                throw error
            } catch {
                markCooldown(league, reason: "\(error)")
                logger.error("ESPN scoreboard fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    static func getTeam<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues) async throws -> Output {
        if let espnSlug = league.espnSlug {
            let urlString = "https://site.api.espn.com/apis/site/v2/sports"
            let scoreboard = "teams"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, scoreboard].joined(separator: "/")
            do {
                let response = try await performGet(req, URI(string: fullString)) { req in
                    try req.query.encode(["limit" : 500])
                }
                return try response.content.decode(DecodeType.self)
            } catch {
                logger.error("ESPN team fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    static func getStandings<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues) async throws -> Output {
        if let espnSlug = league.espnSlug {
            let urlString = "https://site.api.espn.com/apis/v2/sports"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, "standings"].joined(separator: "/")
            do {
                let response = try await performGet(req, URI(string: fullString))
                return try response.content.decode(DecodeType.self)
            } catch {
                logger.error("ESPN standings fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    // MARK: - Leaders (Stat Leaders per Category)

    static func getLeaders<Output: Decodable>(req: some Client, DecodeType: Output.Type, league: Leagues) async throws -> Output {
        if let espnSlug = league.espnSlug {
            let urlString = "https://site.api.espn.com/apis/site/v2/sports"
            let sport = league.sport
            let fullString = [urlString, sport, espnSlug, "leaders"].joined(separator: "/")
            do {
                let response = try await performGet(req, URI(string: fullString))
                return try response.content.decode(DecodeType.self)
            } catch {
                logger.error("ESPN leaders fetch failed", metadata: [
                    "league": "\(league)",
                    "url": "\(fullString)",
                    "error": "\(error)"
                ])
                throw error
            }
        }
        throw NetworkError.invalidLeague
    }

    // MARK: - Roster (team squad)

    /// Fetches a team's roster from ESPN, e.g.
    /// site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams/{id}/roster
    static func getRoster(req: some Client, league: Leagues, teamID: String) async throws -> RosterResponse {
        guard let espnSlug = league.espnSlug else { throw NetworkError.invalidLeague }
        let urlString = "https://site.api.espn.com/apis/site/v2/sports"
        let sport = league.sport
        let fullString = [urlString, sport, espnSlug, "teams", teamID, "roster"].joined(separator: "/")
        do {
            let response = try await performGet(req, URI(string: fullString))
            return try response.content.decode(RosterResponse.self)
        } catch {
            logger.error("ESPN roster fetch failed", metadata: [
                "league": "\(league)",
                "teamID": "\(teamID)",
                "url": "\(fullString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    /// Tolerant decode of the ESPN roster endpoint. Soccer returns `athletes` either as a
    /// flat list of athletes or as position-grouped buckets (`{ position, items: [...] }`),
    /// so each element decodes both shapes and `flatAthletes` flattens them.
    struct RosterResponse: Decodable {
        let team: RosterTeam?
        let athletes: [RosterGroupOrAthlete]?

        struct RosterTeam: Decodable {
            let id: String?
            let displayName: String?
            let logos: [RosterLogo]?
            struct RosterLogo: Decodable { let href: String? }
        }

        struct RosterGroupOrAthlete: Decodable {
            // group fields
            let position: String?
            let items: [RosterAthlete]?
            // flat-athlete fields (present when this element IS an athlete)
            let id: String?
            let displayName: String?
            let fullName: String?
            let jersey: String?
            let age: Int?
            let headshot: RosterHeadshot?
            let position2: RosterPosition?

            enum CodingKeys: String, CodingKey {
                case position, items, id, displayName, fullName, jersey, age, headshot
                case position2 = "positionRef" // unused alias; real position obj decoded below
            }

            // ESPN athlete `position` is an object; the group `position` is a string. Decode
            // manually so both coexist without clashing.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: DynamicKey.self)
                self.items = try? c.decode([RosterAthlete].self, forKey: DynamicKey("items"))
                self.id = try? c.decode(String.self, forKey: DynamicKey("id"))
                self.displayName = try? c.decode(String.self, forKey: DynamicKey("displayName"))
                self.fullName = try? c.decode(String.self, forKey: DynamicKey("fullName"))
                self.jersey = try? c.decode(String.self, forKey: DynamicKey("jersey"))
                self.age = try? c.decode(Int.self, forKey: DynamicKey("age"))
                self.headshot = try? c.decode(RosterHeadshot.self, forKey: DynamicKey("headshot"))
                // position may be a String (group label) or an object (athlete position)
                if let str = try? c.decode(String.self, forKey: DynamicKey("position")) {
                    self.position = str
                    self.position2 = nil
                } else {
                    self.position = nil
                    self.position2 = try? c.decode(RosterPosition.self, forKey: DynamicKey("position"))
                }
            }
        }

        struct RosterAthlete: Decodable {
            let id: String?
            let displayName: String?
            let fullName: String?
            let jersey: String?
            let age: Int?
            let headshot: RosterHeadshot?
            let position: RosterPosition?
        }

        struct RosterHeadshot: Decodable { let href: String? }
        struct RosterPosition: Decodable { let abbreviation: String?; let name: String? }

        private struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ s: String) { stringValue = s }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        /// Flattens grouped or flat athletes into a single ordered list of squad players.
        var flatAthletes: [WorldCupSquadPlayer] {
            guard let athletes else { return [] }
            var out: [WorldCupSquadPlayer] = []
            for element in athletes {
                if let items = element.items, !items.isEmpty {
                    for a in items {
                        out.append(WorldCupSquadPlayer(
                            name: a.displayName ?? a.fullName ?? "Unknown",
                            position: a.position?.abbreviation ?? a.position?.name ?? element.position,
                            jersey: a.jersey,
                            headshotURL: a.headshot?.href,
                            age: a.age
                        ))
                    }
                } else if (element.displayName ?? element.fullName) != nil {
                    out.append(WorldCupSquadPlayer(
                        name: element.displayName ?? element.fullName ?? "Unknown",
                        position: element.position2?.abbreviation ?? element.position2?.name,
                        jersey: element.jersey,
                        headshotURL: element.headshot?.href,
                        age: element.age
                    ))
                }
            }
            return out
        }
    }

    // MARK: - F1 Core Data (Constructors + Timing)

    /// Minimal struct for decoding the ESPN core API competitor response (vehicle field only)
    private struct CoreCompetitor: Decodable {
        var vehicle: Vehicle?
        struct Vehicle: Decodable {
            var manufacturer: String?
        }
    }

    /// Minimal struct for decoding competitor statistics from the ESPN core API
    private struct CoreStatistics: Decodable {
        var splits: Splits?
        struct Splits: Decodable {
            var categories: [Category]?
        }
        struct Category: Decodable {
            var stats: [Stat]?
        }
        struct Stat: Decodable {
            var name: String?
            var displayValue: String?
        }

        /// Returns the display value for a stat by name (e.g. "behindTime", "totalTime")
        func statValue(named name: String) -> String? {
            for category in splits?.categories ?? [] {
                for stat in category.stats ?? [] {
                    if stat.name == name { return stat.displayValue }
                }
            }
            return nil
        }
    }

    /// Fetches constructor (vehicle manufacturer) names for F1 competitors from the ESPN core API.
    /// Returns a dictionary mapping competitor ID → manufacturer name (e.g. "McLaren", "Red Bull").
    /// Falls back to an empty dictionary on failure.
    static func getF1ConstructorMap(req: some Client, scoreboard: Scoreboard) async -> [String: String] {
        // Find the first Race competition that has competitors
        var targetEvent: Event?
        var targetCompetition: Competition?
        for event in scoreboard.events {
            guard let competitions = event.competitions else { continue }
            for competition in competitions {
                if competition.type?.abbreviation == "Race",
                   let competitors = competition.competitors, !competitors.isEmpty {
                    targetEvent = event
                    targetCompetition = competition
                    break
                }
            }
            if targetCompetition != nil { break }
        }

        // If no Race found, try the first competition with competitors (e.g. qualifying)
        if targetCompetition == nil {
            for event in scoreboard.events {
                if let competition = event.competitions?.first(where: { ($0.competitors?.isEmpty == false) }) {
                    targetEvent = event
                    targetCompetition = competition
                    break
                }
            }
        }

        guard let event = targetEvent, let competition = targetCompetition,
              let competitors = competition.competitors else {
            return [:]
        }

        var constructorMap: [String: String] = [:]
        for competitor in competitors {
            let urlString = "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/\(event.id)/competitions/\(competition.id)/competitors/\(competitor.id)?lang=en&region=us"
            do {
                let response = try await performGet(req, URI(string: urlString))
                let coreCompetitor = try response.content.decode(CoreCompetitor.self)
                if let manufacturer = coreCompetitor.vehicle?.manufacturer, !manufacturer.isEmpty {
                    constructorMap[competitor.id] = manufacturer
                }
            } catch {
                logger.warning("Failed to fetch F1 constructor for competitor \(competitor.id)", metadata: [
                    "error": "\(error)"
                ])
            }
        }

        logger.info("F1 constructor map fetched", metadata: [
            "count": "\(constructorMap.count)",
            "total": "\(competitors.count)"
        ])
        return constructorMap
    }

    /// Fetches timing/gap data for all completed F1 sessions from the ESPN core API statistics endpoint.
    /// Returns `[competitionId: [competitorId: gapString]]`.
    /// P1 gets totalTime (e.g. "1:42:06.304"), P2+ gets behindTime (e.g. "+0.895").
    static func getF1TimingMap(req: some Client, scoreboards: [Scoreboard]) async -> [String: [String: String]] {
        // Collect completed and in-progress competitions with their event IDs
        var work: [(eventId: String, competitionId: String, competitors: [Competitor])] = []
        for scoreboard in scoreboards {
            for event in scoreboard.events {
                for competition in event.competitions ?? [] {
                    let isCompleted = competition.status?.type.completed ?? false
                    let isInProgress = competition.status?.type.state == "in"
                    guard (isCompleted || isInProgress), let competitors = competition.competitors, !competitors.isEmpty else { continue }
                    work.append((eventId: event.id, competitionId: competition.id, competitors: competitors))
                }
            }
        }

        guard !work.isEmpty else { return [:] }
        logger.info("Fetching F1 timing data", metadata: [
            "competitions": "\(work.count)",
            "totalRequests": "\(work.reduce(0) { $0 + $1.competitors.count })"
        ])

        var timingMap: [String: [String: String]] = [:]

        for item in work {
            // Fetch all competitors for this competition concurrently
            var competitionTiming: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { group in
                for competitor in item.competitors {
                    group.addTask {
                        let urlString = "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/\(item.eventId)/competitions/\(item.competitionId)/competitors/\(competitor.id)/statistics?lang=en&region=us"
                        do {
                            let response = try await performGet(req, URI(string: urlString))
                            let stats = try response.content.decode(CoreStatistics.self)
                            // P1 shows total time, P2+ show gap behind leader
                            if let behind = stats.statValue(named: "behindTime"), behind != "+0.000" {
                                return (competitor.id, behind)
                            } else if let total = stats.statValue(named: "totalTime") {
                                return (competitor.id, total)
                            }
                            // Fallback: check for laps behind or status (DNF/DNS/+N Laps)
                            if let lapsDown = stats.statValue(named: "lapsDown"), !lapsDown.isEmpty, lapsDown != "0" {
                                return (competitor.id, "+\(lapsDown) Lap\(lapsDown == "1" ? "" : "s")")
                            }
                            if let status = stats.statValue(named: "status"), !status.isEmpty,
                               status != "Running" && status != "Active" {
                                return (competitor.id, status) // e.g. "DNF", "DNS", "Retired"
                            }
                            return (competitor.id, nil)
                        } catch {
                            return (competitor.id, nil)
                        }
                    }
                }
                for await (competitorId, gap) in group {
                    if let gap {
                        competitionTiming[competitorId] = gap
                    }
                }
            }
            if !competitionTiming.isEmpty {
                timingMap[item.competitionId] = competitionTiming
            }
        }

        logger.info("F1 timing map fetched", metadata: [
            "competitions": "\(timingMap.count)"
        ])
        return timingMap
    }

    // MARK: - Play-by-Play Summary (NBA / NFL / NHL / MLB)

    /// Fetches the full play-by-play array from ESPN's per-event summary endpoint.
    /// Returns only the fields we consume (`plays[]`) — the full summary has many more.
    static func getPlayByPlaySummary(
        req: some Client,
        sport: String,
        league: String,
        eventId: String
    ) async throws -> ESPNSummaryResponse {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/summary?event=\(eventId)"
        do {
            let response = try await performGet(req, URI(string: urlString))
            return try response.content.decode(ESPNSummaryResponse.self)
        } catch {
            logger.error("ESPN play-by-play summary fetch failed", metadata: [
                "sport": "\(sport)",
                "league": "\(league)",
                "eventId": "\(eventId)",
                "url": "\(urlString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    // MARK: - Soccer Summary (per-event box score: team stats, lineups, key events)

    /// Fetches ESPN's per-event soccer summary, decoding only the box-score slice
    /// (`boxscore.teams`, `rosters`, `keyEvents`) consumed by `WorldCupBoxScoreBuilder`.
    static func getSoccerSummary(req: some Client, league: Leagues, eventId: String) async throws -> SoccerSummaryResponse {
        guard let espnSlug = league.espnSlug else { throw NetworkError.invalidLeague }
        let sport = league.sport
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(espnSlug)/summary?event=\(eventId)"
        do {
            let response = try await performGet(req, URI(string: urlString))
            return try response.content.decode(SoccerSummaryResponse.self)
        } catch {
            logger.error("ESPN soccer summary fetch failed", metadata: [
                "league": "\(league)",
                "eventId": "\(eventId)",
                "url": "\(urlString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    // MARK: - Golf Summary (per-event detail with hole-by-hole data)

    /// Fetches detailed golf tournament summary including course info, hole-by-hole scores, and round stats.
    static func getGolfSummary(req: some Client, eventId: String) async throws -> GolfSummaryResponse {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/golf/pga/summary?event=\(eventId)"
        do {
            let response = try await performGet(req, URI(string: urlString))
            return try response.content.decode(GolfSummaryResponse.self)
        } catch {
            logger.error("ESPN golf summary fetch failed", metadata: [
                "eventId": "\(eventId)",
                "url": "\(urlString)",
                "error": "\(error)"
            ])
            throw error
        }
    }

    // MARK: - Golf Summary Response Models

    struct GolfSummaryResponse: Codable {
        var courses: [GolfSummaryCourse]?
        var rounds: [GolfSummaryRound]?
    }

    struct GolfSummaryCourse: Codable {
        var name: String?
        var par: Int?
        var holes: [GolfSummaryCourseHole]?
    }

    struct GolfSummaryCourseHole: Codable {
        var number: Int
        var par: Int
        var yardage: Int?
    }

    struct GolfSummaryRound: Codable {
        var number: Int?
        var displayName: String?
        var competitors: [GolfSummaryCompetitor]?
    }

    struct GolfSummaryCompetitor: Codable {
        var id: String?
        var athlete: GolfSummaryAthlete?
        var score: String?
        var status: GolfSummaryCompetitorStatus?
        var linescores: [GolfSummaryLinescore]?
        var statistics: [GolfSummaryStatCategory]?
    }

    struct GolfSummaryAthlete: Codable {
        var id: String?
        var displayName: String?
    }

    struct GolfSummaryCompetitorStatus: Codable {
        var period: Int?
        var displayValue: String?
        var thru: Int?
    }

    struct GolfSummaryLinescore: Codable {
        var period: Int?   // hole number
        var value: Int?    // strokes on this hole
    }

    struct GolfSummaryStatCategory: Codable {
        var name: String?
        var displayName: String?
        var stats: [GolfSummaryStat]?
    }

    struct GolfSummaryStat: Codable {
        var name: String?
        var displayName: String?
        var value: Double?
        var displayValue: String?
    }

    static func decodeSportToPath(sport: SportType) -> String? {
        switch sport {
        case .basketball:
            return "basketball/nba"
        case .hockey:
            return "hockey/nhl"
        case .mlb:
            return "baseball/mlb"
        case .nfl:
            return "football/nfl"
        case .golf:
            return "golf/pga"
        case .tennis:
            return nil
        case .racing:
            return "racing/f1"
        default:
            return nil
        }
    }
}


