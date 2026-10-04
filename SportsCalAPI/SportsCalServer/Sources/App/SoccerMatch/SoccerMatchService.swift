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
        let isDebug = req.application.environment == .development
        let cacheKey = (isDebug ? "debug-" : "") + "Soccer Match-\(eventID)"
        if let cached = try? await req.kv.getJSON(cacheKey, as: SoccerMatchDetail.self) {
            return cached
        }

        let app = req.application
        return await SoccerMatchFetches.shared.run(eventID: eventID) {
            guard let (espnID, slug) = await resolveESPNEvent(app: app, eventID: eventID, lookup: lookup, isDebug: isDebug) else {
                return nil
            }
            do {
                let summary = try await ESPNNetworking.getSoccerSummary(req: app.client, leagueSlug: slug, eventId: espnID)
                guard let detail = SoccerMatchBuilder.build(from: summary, eventID: eventID) else { return nil }
                try? await app.kv.setJSON(
                    cacheKey, value: detail,
                    ttl: TimeInterval(cacheSeconds(state: summary.matchState))
                )
                return detail
            } catch {
                app.logger.warning("Soccer match fetch failed for \(eventID) → ESPN \(espnID): \(error)")
                return nil
            }
        }
    }

    /// Live matches refresh every 30s. Before kickoff lineups can appear at any time,
    /// so 2 minutes. A finished match only changes if ESPN corrects it.
    static func cacheSeconds(state: String?) -> Int {
        switch state {
        case "in": return 30
        case "post": return 60 * 60 * 24
        default: return 120
        }
    }

    // MARK: Resolving the ESPN event

    private static func resolveESPNEvent(
        app: Application, eventID: String, lookup: Lookup, isDebug: Bool
    ) async -> (espnID: String, slug: String)? {
        let mapKey = RedisEndpoint.ESPN.espnEventMap.getValue(isDebug: isDebug)
        let eventMap = (try? await app.kv.getJSON(mapKey.rawValue, as: [String: ESPNEventMapping].self)) ?? [:]
        if let mapping = eventMap[eventID], mapping.sport == "soccer" {
            return (mapping.espnEventID, mapping.league)
        }
        // ESPN's summary resolves an event by id under any soccer slug.
        let slug = lookup.leagueSlug ?? "all"
        if isLikelyESPNID(eventID) {
            return (eventID, slug)
        }
        guard let found = await findOnScoreboard(app: app, lookup: lookup) else { return nil }
        return (found, slug)
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
