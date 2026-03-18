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

        // Fetch all three data sources concurrently (3 requests total)
        async let circuitsTask = JolpicaNetworking.getCircuits(client: client, season: currentYear)
        async let driverStandingsTask = JolpicaNetworking.getDriverStandings(client: client, season: currentYear)
        async let constructorStandingsTask = JolpicaNetworking.getConstructorStandings(client: client, season: currentYear)
        async let circuitImagesTask = OpenF1Networking.getCircuitImages(client: client, year: currentYear)

        let circuits = await circuitsTask
        let driverStandings = await driverStandingsTask
        let constructorStandings = await constructorStandingsTask
        let circuitImages = await circuitImagesTask

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
        try await redis.set(circuitsKey, toJSON: enrichedCircuits)
        try await redis.set(standingsKey, toJSON: standings)
        try await redis.set(lastUpdateKey, toJSON: Date())

        // Also update the main schedule to attach circuit info + standings
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        if var schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self) {
            schedule.f1Standings = standings
            if var racingEvents = schedule.racing?.events, !enrichedCircuits.isEmpty {
                for i in racingEvents.indices {
                    let game = racingEvents[i]
                    if let circuitInfo = findCircuitForGame(game, circuits: enrichedCircuits) {
                        racingEvents[i] = gameWithCircuitInfo(game, circuitInfo: circuitInfo)
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
            "constructorStandings": "\(constructorStandings.count)"
        ])
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

    /// Creates a new Game with circuit info attached.
    private func gameWithCircuitInfo(_ game: Game, circuitInfo: F1CircuitInfo) -> Game {
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
            circuitInfo: circuitInfo
        )
    }
}
