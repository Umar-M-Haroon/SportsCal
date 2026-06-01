//
//  F1EnrichmentJob.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 3/5/26.
//

import Foundation
import Queues
import SportsCalModel
import Logging

/// Fetches F1 enrichment data (standings, circuits, circuit images) from Jolpica + OpenF1.
/// Runs every 6 hours. Data is cached in Redis and attached to F1 games during schedule builds.
struct F1EnrichmentJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.f1-enrichment")

    // Persist-guards: a failed source returns an empty collection (the fetchers are
    // non-throwing), so guard writes to avoid clobbering last-known-good Redis data.
    static func shouldPersistCircuits(_ circuits: [String: F1CircuitInfo]) -> Bool {
        !circuits.isEmpty
    }
    static func shouldPersistStandings(_ standings: F1Standings) -> Bool {
        !standings.driverStandings.isEmpty || !standings.constructorStandings.isEmpty
    }

    func run(context: QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let client = context.application.client
        let redis = context.application.redis
        let currentYear = Calendar.current.component(.year, from: Date())

        // Check if enrichment is stale (> 6 hours)
        let lastUpdateKey = RedisEndpoint.ESPN.f1EnrichmentLastUpdate.getValue(isDebug: isDebug)
        if let lastUpdate = try? await redis.get(lastUpdateKey, asJSON: Date.self) {
            let hoursSince = Date().timeIntervalSince(lastUpdate) / 3600
            if hoursSince < 6 {
                Self.logger.info("F1 enrichment still fresh, skipping", metadata: [
                    "hoursSinceUpdate": "\(String(format: "%.1f", hoursSince))"
                ])
                return
            }
        }

        Self.logger.info("Fetching F1 enrichment data")

        // Fetch all four data sources concurrently
        async let circuitsTask = JolpicaNetworking.getCircuits(client: client, season: currentYear)
        async let driverStandingsTask = JolpicaNetworking.getDriverStandings(client: client, season: currentYear)
        async let constructorStandingsTask = JolpicaNetworking.getConstructorStandings(client: client, season: currentYear)
        async let circuitImagesTask = OpenF1Networking.getCircuitImages(client: client, year: currentYear)
        async let sessionsTask = OpenF1Networking.getRaceSessions(client: client, year: currentYear)

        let circuits = await circuitsTask
        let driverStandings = await driverStandingsTask
        let constructorStandings = await constructorStandingsTask
        let circuitImages = await circuitImagesTask
        let sessions = await sessionsTask

        // Fetch telemetry for the most recent completed Race session. That's the one
        // users are most likely to dig into; older races keep the existing standings
        // view without per-lap detail to keep payload and API calls bounded.
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recentRaceTiming: F1RaceTiming? = await {
            for session in sessions where session.session_name == "Race" {
                guard let dateEnd = session.date_end,
                      let end = iso.date(from: dateEnd) ?? ISO8601DateFormatter().date(from: dateEnd),
                      end < now else { continue }
                return await OpenF1Networking.getRaceTiming(client: client, session: session)
            }
            return nil
        }()

        // Store circuits (with images merged in)
        var enrichedCircuits = circuits
        for (meetingName, imageURL) in circuitImages {
            // Try to match OpenF1 meeting names to Jolpica race names
            // OpenF1: "Australian Grand Prix", Jolpica: "Australian Grand Prix"
            if let matchingKey = enrichedCircuits.keys.first(where: { raceNameMatches($0, meetingName) }) {
                var info = enrichedCircuits[matchingKey]!
                enrichedCircuits[matchingKey] = F1CircuitInfo(
                    circuitName: info.circuitName,
                    locality: info.locality,
                    country: info.country,
                    circuitImageURL: imageURL,
                    latitude: info.latitude,
                    longitude: info.longitude
                )
            }
        }

        // Store standings
        let standings = F1Standings(
            driverStandings: driverStandings,
            constructorStandings: constructorStandings
        )

        // Save to Redis
        let circuitsKey = RedisEndpoint.ESPN.f1Circuits.getValue(isDebug: isDebug)
        let standingsKey = RedisEndpoint.ESPN.f1Standings.getValue(isDebug: isDebug)
        let raceTimingKey = RedisEndpoint.ESPN.f1RaceTiming.getValue(isDebug: isDebug)
        var wrotePrimary = false
        if Self.shouldPersistCircuits(enrichedCircuits) {
            try await redis.set(circuitsKey, toJSON: enrichedCircuits)
            wrotePrimary = true
        }
        if Self.shouldPersistStandings(standings) {
            try await redis.set(standingsKey, toJSON: standings)
            wrotePrimary = true
        }
        if let recentRaceTiming {
            try await redis.set(raceTimingKey, toJSON: recentRaceTiming)
        }
        // Only stamp lastUpdate when core data was actually refreshed, so a degraded run
        // (a source down → empty) retries next tick instead of being silenced for 6h.
        if wrotePrimary {
            try await redis.set(lastUpdateKey, toJSON: Date())
        }

        // Also update the main schedule to attach circuit info + standings
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        if var schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self) {
            if Self.shouldPersistStandings(standings) {
                schedule.f1Standings = standings
            }
            if var racingEvents = schedule.racing?.events {
                for i in racingEvents.indices {
                    let game = racingEvents[i]
                    let circuitInfo = enrichedCircuits.isEmpty ? nil : findCircuitForGame(game, circuits: enrichedCircuits)
                    let timingForGame = recentRaceTiming.flatMap { timing in
                        raceTimingMatchesGame(timing: timing, game: game, sessions: sessions) ? timing : nil
                    }
                    if circuitInfo != nil || timingForGame != nil {
                        racingEvents[i] = gameWithEnrichment(
                            game,
                            circuitInfo: circuitInfo ?? game.circuitInfo,
                            raceTiming: timingForGame ?? game.raceTiming
                        )
                    }
                }
                schedule.racing = LiveEvent(events: racingEvents)
            }
            try await redis.set(scheduleKey, toJSON: schedule)
            Self.logger.info("F1 enrichment applied to schedule")
        }

        Self.logger.info("F1 enrichment complete", metadata: [
            "circuits": "\(enrichedCircuits.count)",
            "circuitImages": "\(enrichedCircuits.values.filter { $0.circuitImageURL != nil }.count)",
            "driverStandings": "\(driverStandings.count)",
            "constructorStandings": "\(constructorStandings.count)",
            "raceTimingDrivers": "\(recentRaceTiming?.drivers.count ?? 0)"
        ])
    }

    /// Matches a telemetry session to a schedule Game by comparing session country/location
    /// against the race name. Sessions list includes country_name and location — use both.
    private func raceTimingMatchesGame(timing: F1RaceTiming, game: Game, sessions: [OpenF1Networking.Session]) -> Bool {
        guard let session = sessions.first(where: { $0.session_key == timing.sessionKey }) else { return false }
        let raceName = game.strHomeTeam.lowercased()
        let venue = game.venueName?.lowercased() ?? ""
        if let country = session.country_name?.lowercased(), raceName.contains(country) || venue.contains(country) {
            return true
        }
        if let location = session.location?.lowercased(), raceName.contains(location) || venue.contains(location) {
            return true
        }
        if let circuit = session.circuit_short_name?.lowercased(), venue.contains(circuit) {
            return true
        }
        return false
    }

    /// Fuzzy-matches race names between Jolpica and OpenF1.
    /// Handles minor differences like "Grand Prix" capitalization or "Emilia Romagna" vs "Emilia-Romagna".
    private func raceNameMatches(_ name1: String, _ name2: String) -> Bool {
        let normalize = { (s: String) -> String in
            s.lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        return normalize(name1) == normalize(name2)
    }

    /// Finds matching circuit info for a game by comparing race name with circuit map keys.
    private func findCircuitForGame(_ game: Game, circuits: [String: F1CircuitInfo]) -> F1CircuitInfo? {
        let raceName = game.strHomeTeam.lowercased().replacingOccurrences(of: "-", with: " ")
        for (key, info) in circuits {
            let normalized = key.lowercased().replacingOccurrences(of: "-", with: " ")
            if raceName.contains(normalized) || normalized.contains(raceName) {
                return info
            }
            // Also try matching by locality/country in the venue name
            if let venue = game.venueName?.lowercased() {
                if venue.contains(info.locality.lowercased()) || venue.contains(info.country.lowercased()) {
                    return info
                }
            }
        }
        return nil
    }

    /// Creates a new Game with circuit info and/or race timing attached.
    private func gameWithEnrichment(_ game: Game, circuitInfo: F1CircuitInfo?, raceTiming: F1RaceTiming?) -> Game {
        Game(
            idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: game.strSport,
            idLeague: game.idLeague, strLeague: game.strLeague,
            idHomeTeam: game.idHomeTeam, idAwayTeam: game.idAwayTeam,
            strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam,
            strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge,
            intHomeScore: game.intHomeScore, intAwayScore: game.intAwayScore,
            strStatus: game.strStatus, strProgress: game.strProgress,
            strTimestamp: game.strTimestamp,
            lastPlay: game.lastPlay,
            homeLinescores: game.homeLinescores, awayLinescores: game.awayLinescores,
            homeLeaders: game.homeLeaders, awayLeaders: game.awayLeaders,
            isCompleted: game.isCompleted, isoDate: game.isoDate,
            leaderboardEntries: game.leaderboardEntries,
            sessions: game.sessions,
            venueName: game.venueName,
            homeTeamColor: game.homeTeamColor, awayTeamColor: game.awayTeamColor,
            homeRecord: game.homeRecord, awayRecord: game.awayRecord,
            circuitInfo: circuitInfo,
            golfCourseInfo: game.golfCourseInfo,
            legDisplay: game.legDisplay, aggregateScore: game.aggregateScore,
            homeSeed: game.homeSeed, awaySeed: game.awaySeed,
            tournamentName: game.tournamentName,
            homeInjuries: game.homeInjuries, awayInjuries: game.awayInjuries,
            raceTiming: raceTiming,
            playoff: game.playoff
        )
    }
}
