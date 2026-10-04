//
//  SoccerCompetitionService.swift
//  SportsCalServer
//
//  Serves `/soccer/competition/:leagueID` and `/soccer/player/:athleteID`: fetches
//  the ESPN pieces concurrently, builds the shared models, and caches them in Redis.
//  Each piece is optional, so a cup with no table still gets its scorers and a
//  player without an overview still gets a bio.
//

import Foundation
import Vapor
import SportsCalModel

enum SoccerCompetitionService {
    /// Tables move after every match; a quarter of an hour keeps a matchday current
    /// without refetching three ESPN endpoints per viewer.
    static let hubCacheSeconds: TimeInterval = 15 * 60
    /// Season lines and the last five only change on matchdays.
    static let playerCacheSeconds: TimeInterval = 6 * 60 * 60

    static func hub(req: Request, league: Leagues) async throws -> SoccerCompetitionHub? {
        let isDebug = req.application.environment == .development
        let cacheKey = (isDebug ? "debug-" : "") + "Soccer Competition-\(league.rawValue)"
        if let cached = try? await req.kv.getJSON(cacheKey, as: SoccerCompetitionHub.self) {
            return cached
        }

        let client = req.client
        async let standings = try? ESPNNetworking.getStandings(req: client, DecodeType: StandingsResponse.self, league: league)
        async let statistics = try? ESPNNetworking.getLeagueStatistics(req: client, league: league)
        async let season = seasonEvents(client: client, league: league)

        let hub = SoccerCompetitionBuilder.build(
            leagueID: league.rawValue,
            standings: await standings,
            season: await season,
            statistics: await statistics
        )
        guard !hub.isEmpty else { return nil }
        try? await req.kv.setJSON(cacheKey, value: hub, ttl: hubCacheSeconds)
        return hub
    }

    /// The season's matches for form. A calendar-year board covers a split season
    /// from August; before the summer it holds only the second half of the season,
    /// so last year's board joins it.
    private static func seasonEvents(client: some Client, league: Leagues) async -> [Event] {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        var events = (try? await Integrator.getESPNScoreboard(for: league, client, dates: year))?.events ?? []
        if month < 7, let earlier = try? await Integrator.getESPNScoreboard(for: league, client, dates: year - 1) {
            events += earlier.events
        }
        return events
    }

    static func player(req: Request, athleteID: String) async throws -> SoccerPlayerProfile? {
        let isDebug = req.application.environment == .development
        let cacheKey = (isDebug ? "debug-" : "") + "Soccer Player-\(athleteID)"
        if let cached = try? await req.kv.getJSON(cacheKey, as: SoccerPlayerProfile.self) {
            return cached
        }

        let client = req.client
        async let bio = try? ESPNNetworking.getSoccerAthlete(req: client, athleteID: athleteID)
        async let overview = try? ESPNNetworking.getSoccerAthleteOverview(req: client, athleteID: athleteID)
        guard let profile = SoccerPlayerBuilder.build(athleteID: athleteID, bio: await bio, overview: await overview) else {
            return nil
        }
        try? await req.kv.setJSON(cacheKey, value: profile, ttl: playerCacheSeconds)
        return profile
    }
}
