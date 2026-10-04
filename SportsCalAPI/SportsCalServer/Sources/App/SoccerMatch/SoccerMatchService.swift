//
//  SoccerMatchService.swift
//  SportsCalServer
//
//  Serves `/soccer/match/:eventID`: finds the ESPN event behind an app game id,
//  fetches its summary, builds a `SoccerMatchDetail`, and caches it in Redis
//  for as long as the match state allows.
//
//  App soccer games carry either an ESPN id or a TheSportsDB id. ESPN ids are
//  used as-is; TSDB ids go through the `ESPN-Event-Map` the live job maintains,
//  and failing that (an older game the job never saw) through ESPN's scoreboard
//  for the game's day, matched on team names.
//

import Foundation
import Vapor
import SportsCalModel

enum SoccerMatchService {
    /// What the app tells us about the game, used only when the id isn't mapped.
    struct Lookup {
        var leagueSlug: String?
        /// Kickoff day as yyyyMMdd (UTC).
        var day: Int?
        var homeName: String?
        var awayName: String?
    }

    static func detail(req: Request, eventID: String, lookup: Lookup) async throws -> SoccerMatchDetail? {
        await detail(app: req.application, eventID: eventID, lookup: lookup)
    }

    /// The same, outside a request — the alert job reads matches through this, so it
    /// shares the cache (and the single in-flight fetch) with app requests.
    static func detail(app: Application, eventID: String, lookup: Lookup) async -> SoccerMatchDetail? {
        let isDebug = app.environment == .development
        let prefix = isDebug ? "debug-" : ""
        let cacheKey = prefix + "Soccer Match-\(eventID)"
        let missKey = prefix + "Soccer Match Miss-\(eventID)"
        if let cached = try? await app.kv.getJSON(cacheKey, as: SoccerMatchDetail.self) {
            return cached
        }
        // A match ESPN doesn't carry would otherwise re-scan two scoreboards on every open.
        if (try? await app.kv.exists(missKey)) == true { return nil }

        return await SoccerMatchFetches.shared.run(eventID: eventID) {
            let slug = lookup.leagueSlug ?? "all"
            var built: (detail: SoccerMatchDetail, summary: SoccerSummaryResponse)?
            do {
                switch await resolveESPNEvent(app: app, eventID: eventID, lookup: lookup, isDebug: isDebug) {
                case .mapped(let espnID, let mappedSlug):
                    built = try await fetchAndBuild(app: app, eventID: eventID, espnID: espnID, slug: mappedSlug)
                case .idShape:
                    built = try await fetchAndBuild(app: app, eventID: eventID, espnID: eventID, slug: slug)
                    // An older TheSportsDB id can share a six-digit ESPN id's shape and
                    // land on an unrelated match; trust it only when the teams agree.
                    if let candidate = built, !teamsMatch(candidate.detail, lookup) {
                        built = nil
                        if let found = await findOnScoreboard(app: app, lookup: lookup) {
                            built = try await fetchAndBuild(app: app, eventID: eventID, espnID: found, slug: slug)
                        }
                    }
                case .scoreboard:
                    if let found = await findOnScoreboard(app: app, lookup: lookup) {
                        built = try await fetchAndBuild(app: app, eventID: eventID, espnID: found, slug: slug)
                    }
                }
            } catch {
                // ESPN failed: try again next time rather than remembering a miss.
                app.logger.warning("Soccer match fetch failed for \(eventID): \(error)")
                return nil
            }
            guard let built else {
                try? await app.kv.setString(missKey, value: "1", ttl: missCacheSeconds)
                return nil
            }
            try? await app.kv.setJSON(
                cacheKey, value: built.detail,
                ttl: TimeInterval(cacheSeconds(state: built.summary.matchState, completed: built.summary.matchCompleted))
            )
            return built.detail
        }
    }

    static let missCacheSeconds: TimeInterval = 10 * 60

    /// Nil when ESPN has nothing worth showing for the event; throws when the fetch fails.
    private static func fetchAndBuild(
        app: Application, eventID: String, espnID: String, slug: String
    ) async throws -> (detail: SoccerMatchDetail, summary: SoccerSummaryResponse)? {
        let summary = try await ESPNNetworking.getSoccerSummary(req: app.client, leagueSlug: slug, eventId: espnID)
        guard let detail = SoccerMatchBuilder.build(from: summary, eventID: eventID) else { return nil }
        return (detail, summary)
    }

    /// Whether a built match is the game the app asked about. Without names to check
    /// against (the World Cup route) it's taken on trust.
    static func teamsMatch(_ detail: SoccerMatchDetail, _ lookup: Lookup) -> Bool {
        guard let home = lookup.homeName, let away = lookup.awayName else { return true }
        let matcher = ESPNFetchJob()
        return matcher.looselySameTeam(matcher.looseTeamKey(home), matcher.looseTeamKey(detail.home.teamName))
            && matcher.looselySameTeam(matcher.looseTeamKey(away), matcher.looseTeamKey(detail.away.teamName))
    }

    /// Live matches refresh every 30s. Before kickoff lineups can appear at any time,
    /// so 2 minutes. A finished match only changes if ESPN corrects it; a postponed or
    /// abandoned one ("post" but not completed) may be rescheduled, so 10 minutes.
    static func cacheSeconds(state: String?, completed: Bool? = nil) -> Int {
        switch state {
        case "in": return 30
        case "post": return completed == false ? 10 * 60 : 60 * 60 * 24
        default: return 120
        }
    }

    // MARK: Resolving the ESPN event

    private enum Resolution {
        /// The live job's TheSportsDB → ESPN map knew it.
        case mapped(espnID: String, slug: String)
        /// The id looks like ESPN's; to be confirmed against the team names.
        case idShape
        /// Find it on ESPN's scoreboard by league, day and teams.
        case scoreboard
    }

    private static func resolveESPNEvent(
        app: Application, eventID: String, lookup: Lookup, isDebug: Bool
    ) async -> Resolution {
        let mapKey = RedisEndpoint.ESPN.espnEventMap.getValue(isDebug: isDebug)
        let eventMap = (try? await app.kv.getJSON(mapKey.rawValue, as: [String: ESPNEventMapping].self)) ?? [:]
        if let mapping = eventMap[eventID], mapping.sport == "soccer" {
            return .mapped(espnID: mapping.espnEventID, slug: mapping.league)
        }
        // ESPN's summary resolves an event by id under any soccer slug.
        return isLikelyESPNID(eventID) ? .idShape : .scoreboard
    }

    /// ESPN soccer ids are six digits (older fixtures, internationals) or nine
    /// starting "40"; TheSportsDB's are seven.
    static func isLikelyESPNID(_ id: String) -> Bool {
        guard id.allSatisfy(\.isNumber) else { return false }
        return id.count == 6 || (id.count == 9 && id.hasPrefix("40"))
    }

    /// Scans the league's ESPN scoreboard for the game's day and the day before (ESPN
    /// buckets by US Eastern date, so a late-UTC kickoff can sit on the earlier one).
    private static func findOnScoreboard(app: Application, lookup: Lookup) async -> String? {
        guard let slug = lookup.leagueSlug, let league = Leagues(slug: slug), let day = lookup.day,
              let homeName = lookup.homeName, let awayName = lookup.awayName else { return nil }
        let matcher = ESPNFetchJob()
        let home = matcher.looseTeamKey(homeName)
        let away = matcher.looseTeamKey(awayName)
        for date in [day, previousDay(day)].compactMap({ $0 }) {
            guard let board = try? await Integrator.getESPNScoreboard(for: league, app.client, dates: date) else { continue }
            for event in board.events {
                let competitors = event.competitions?.first?.competitors ?? []
                guard let espnHome = competitors.first(where: { $0.homeAway == "home" })?.team,
                      let espnAway = competitors.first(where: { $0.homeAway == "away" })?.team else { continue }
                if matcher.looselySameTeam(home, matcher.looseTeamKey(espnHome.displayName)),
                   matcher.looselySameTeam(away, matcher.looseTeamKey(espnAway.displayName)) {
                    return event.id
                }
            }
        }
        return nil
    }

    private static func previousDay(_ yyyymmdd: Int) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: yyyymmdd / 10000, month: yyyymmdd / 100 % 100, day: yyyymmdd % 100)
        guard let date = calendar.date(from: components),
              let previous = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        let p = calendar.dateComponents([.year, .month, .day], from: previous)
        return (p.year ?? 0) * 10000 + (p.month ?? 0) * 100 + (p.day ?? 0)
    }
}

/// In-flight soccer match fetches, by app event id, so a popular match going stale
/// costs one ESPN request rather than one per viewer.
actor SoccerMatchFetches {
    static let shared = SoccerMatchFetches()
    private var inFlight: [String: Task<SoccerMatchDetail?, Never>] = [:]

    func run(eventID: String, fetch: @escaping @Sendable () async -> SoccerMatchDetail?) async -> SoccerMatchDetail? {
        if let running = inFlight[eventID] { return await running.value }
        let task = Task { await fetch() }
        inFlight[eventID] = task
        let result = await task.value
        inFlight[eventID] = nil
        return result
    }
}
