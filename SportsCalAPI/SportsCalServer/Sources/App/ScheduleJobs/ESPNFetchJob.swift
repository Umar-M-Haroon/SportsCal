//
//  File.swift
//  
//
//  Created by Umar Haroon on 2/23/23.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging
import VaporAPNS
import APNSCore

struct ESPNFetchJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-fetch")
    
    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development

        // Only fetch live scores if there are games happening or starting soon
        let shouldFetchLive = await Integrator.hasLiveOrUpcomingGames(
            redis: context.application.redis,
            isDebug: isDebug
        )

        if !shouldFetchLive {
            Self.logger.info("No live or upcoming games — skipping ESPN live score fetch")
            return
        }

        let soccerScoreboards = try await context.application.redis.get( RedisEndpoint.ESPN.latestSoccerScoreboards.getValue(isDebug: isDebug), asJSON: [Leagues: Scoreboard].self)

        let soccerEvents = soccerScoreboards?.compactMap({ (league, scoreboard) in
            LiveEvent(events: scoreboard, league: league)
        }).reduce(into: LiveEvent(events: [])) { partialResult, next in
            partialResult.events += next.events
        }

        let tennisScoreboards = try await context.application.redis.get( RedisEndpoint.ESPN.latestTennisScoreboards.getValue(isDebug: isDebug), asJSON: [Leagues: Scoreboard].self)

        let tennisEvents = tennisScoreboards?.compactMap({ (league, scoreboard) in
            LiveEvent(events: scoreboard, league: league)
        }).reduce(into: LiveEvent(events: [])) { partialResult, next in
            partialResult.events += next.events
        }

        Self.logger.info("Fetching ESPN live scores")
        let espnResult = await Integrator.getESPNLiveScore(context.application.client)
        let latestLiveResult = try await context.application.redis.get(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug), asJSON: LiveScore.self)

        // Load ESPN-ID → TheSportsDB-ID mapping for team ID translation
        let mappingKey: RedisKey = isDebug ? "debug-ESPN-ID-Map" : "ESPN-ID-Map"
        let espnToTSDB = try await context.application.redis.get(mappingKey, asJSON: [String: String].self) ?? [:]

        var newResult = latestLiveResult.map({ score in
            return LiveScore(nba: returnUpdatedEvents(events: [], espnEvents: espnResult.nba?.events ?? []),
                             mlb: returnUpdatedEvents(events:  [], espnEvents: espnResult.mlb?.events ?? []),
                             soccer: returnUpdatedEvents(events: [], espnEvents: soccerEvents?.events ?? []),
                             nfl: returnUpdatedEvents(events: [], espnEvents: espnResult.nfl?.events ?? []),
                             nhl: returnUpdatedEvents(events: [], espnEvents: espnResult.nhl?.events ?? []),
                             golf: returnUpdatedEvents(events: [], espnEvents: espnResult.golf?.events ?? []),
                             tennis: returnUpdatedEvents(events: [], espnEvents: tennisEvents?.events ?? []),
                             racing: returnUpdatedEvents(events: [], espnEvents: espnResult.racing?.events ?? []))
        })
        if newResult == nil {
            newResult = espnResult
        }

        // Translate ESPN team IDs to TheSportsDB IDs in all live games
        if !espnToTSDB.isEmpty {
            newResult = newResult.map { translateTeamIDs(in: $0, using: espnToTSDB) }
        }

        // Detect newly started games and send push-to-start notifications
        if let newResult {
            await sendPushToStartForNewGames(
                newResult: newResult,
                previousResult: latestLiveResult,
                context: context,
                isDebug: isDebug
            )
        }

        try await context.application.redis.setex(RedisEndpoint.ESPN.latestFullLiveInfo.getValue(isDebug: isDebug), toJSON: newResult, expirationInSeconds: 60 * 30)
        try await context.application.redis.set(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug), toJSON: newResult)
    }

    /// Detects newly started games and sends push-to-start APNS notifications
    /// to users who have those teams as favorites.
    private func sendPushToStartForNewGames(
        newResult: LiveScore,
        previousResult: LiveScore?,
        context: Queues.QueueContext,
        isDebug: Bool
    ) async {
        // Collect all current live games
        let allNewGames = collectAllGames(from: newResult)
        let allPreviousGames = collectAllGames(from: previousResult)

        // Find games that are newly "in progress" (status == "in")
        let previousIDs = Set(allPreviousGames.filter { !$0.hasDoneStatus && $0.strStatus == "in" }.compactMap(\.idEvent))
        let newlyStarted = allNewGames.filter { game in
            guard let eventID = game.idEvent,
                  game.strStatus == "in",
                  !previousIDs.contains(eventID) else { return false }
            return true
        }

        guard !newlyStarted.isEmpty else { return }
        Self.logger.info("Detected \(newlyStarted.count) newly started games for push-to-start")

        // Scan all PushToStart-* registrations
        let keyPattern = isDebug ? "debug-PushToStart-*" : "PushToStart-*"
        guard let registrationKeys = try? await context.application.redis.send(command: "keys", with: [keyPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .map({ RedisKey($0) }),
              !registrationKeys.isEmpty else { return }

        let apnsClient = await context.application.apns.client
        let keyPrefix = isDebug ? "debug-PushToStart-" : "PushToStart-"

        let newlyStartedIDs = Set(newlyStarted.compactMap(\.idEvent))

        for registrationKey in registrationKeys {
            guard let favorites = try? await context.application.redis.get(registrationKey, asJSON: [String].self) else { continue }

            let favoritesSet = Set(favorites)
            let token = String(registrationKey.rawValue.dropFirst(keyPrefix.count))

            for game in newlyStarted {
                let homeTeam = game.strHomeTeam
                let awayTeam = game.strAwayTeam
                guard favoritesSet.contains(homeTeam) || favoritesSet.contains(awayTeam),
                      game.idEvent != nil else { continue }

                try? await sendPushToStartNotification(
                    game: game, token: token, context: context, apnsClient: apnsClient, isDebug: isDebug
                )
            }
        }

        // Also check event-based auto-follow registrations
        let eventsKeyPattern = isDebug ? "debug-PushToStartEvents-*" : "PushToStartEvents-*"
        let eventsKeyPrefix = isDebug ? "debug-PushToStartEvents-" : "PushToStartEvents-"
        if let eventRegistrationKeys = try? await context.application.redis.send(command: "keys", with: [eventsKeyPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .map({ RedisKey($0) }),
           !eventRegistrationKeys.isEmpty {

            for registrationKey in eventRegistrationKeys {
                guard let eventIDs = try? await context.application.redis.get(registrationKey, asJSON: [String].self) else { continue }

                let token = String(registrationKey.rawValue.dropFirst(eventsKeyPrefix.count))
                let matchingIDs = Set(eventIDs).intersection(newlyStartedIDs)

                for game in newlyStarted {
                    guard let eventID = game.idEvent,
                          matchingIDs.contains(eventID) else { continue }

                    try? await sendPushToStartNotification(
                        game: game, token: token, context: context, apnsClient: apnsClient, isDebug: isDebug
                    )
                }
            }
        }
    }

    /// Sends a push-to-start APNS notification for a specific game to a specific token.
    /// Deduplicates using SentPushToStart Redis keys.
    private func sendPushToStartNotification(
        game: Game,
        token: String,
        context: Queues.QueueContext,
        apnsClient: some APNSClientProtocol,
        isDebug: Bool
    ) async throws {
        guard let eventID = game.idEvent else { return }
        let homeTeam = game.strHomeTeam
        let awayTeam = game.strAwayTeam

        // Check if we already sent this notification
        let sentKey = RedisEndpoint.sentPushToStart(token, eventID).getValue(isDebug: isDebug)
        let alreadySentCount = try? await context.application.redis.exists(sentKey)
        guard alreadySentCount == 0 || alreadySentCount == nil else { return }

        // Mark as sent (TTL 8 hours)
        try? await context.application.redis.setex(sentKey, to: "1", expirationInSeconds: 60 * 60 * 8).get()

        let attributes = LiveSportAttributes(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            eventID: eventID
        )
        let contentState = ContentState(
            homeScore: Int(game.intHomeScore ?? "") ?? 0,
            awayScore: Int(game.intAwayScore ?? "") ?? 0,
            status: game.strStatus,
            progress: game.strProgress
        )

        do {
            let notification = APNSStartLiveActivityNotification(
                expiration: .immediately,
                priority: .immediately,
                appID: "com.KomodoLLC.SportsCal",
                contentState: contentState,
                timestamp: Int(Date().timeIntervalSince1970),
                attributes: attributes,
                attributesType: "LiveSportActivityAttributes",
                alert: APNSAlertNotificationContent(
                    title: .raw("\(homeTeam) vs \(awayTeam)"),
                    body: .raw("Game is starting now!")
                )
            )
            try await apnsClient.sendStartLiveActivityNotification(notification, deviceToken: token)
            Self.logger.info("Sent push-to-start for \(homeTeam) vs \(awayTeam) to token \(token.prefix(8))...")
        } catch {
            Self.logger.error("Failed to send push-to-start for event \(eventID): \(error)")
        }
    }

    /// Collects all games from all sports in a LiveScore
    private func collectAllGames(from liveScore: LiveScore?) -> [Game] {
        guard let liveScore else { return [] }
        var games: [Game] = []
        games.append(contentsOf: liveScore.nba?.events ?? [])
        games.append(contentsOf: liveScore.mlb?.events ?? [])
        games.append(contentsOf: liveScore.soccer?.events ?? [])
        games.append(contentsOf: liveScore.nfl?.events ?? [])
        games.append(contentsOf: liveScore.nhl?.events ?? [])
        games.append(contentsOf: liveScore.golf?.events ?? [])
        games.append(contentsOf: liveScore.tennis?.events ?? [])
        games.append(contentsOf: liveScore.racing?.events ?? [])
        return games
    }

    /// Translates ESPN team IDs to TheSportsDB IDs in all games within a LiveScore
    private func translateTeamIDs(in liveScore: LiveScore, using mapping: [String: String]) -> LiveScore {
        func translateEvents(_ events: [Game]) -> [Game] {
            events.map { game in
                let homeID = game.idHomeTeam.flatMap { mapping[$0] } ?? game.idHomeTeam
                let awayID = game.idAwayTeam.flatMap { mapping[$0] } ?? game.idAwayTeam
                guard homeID != game.idHomeTeam || awayID != game.idAwayTeam else { return game }
                return Game(idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: nil, idLeague: game.idLeague, strLeague: nil, idHomeTeam: homeID, idAwayTeam: awayID, strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam, strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge, intHomeScore: game.intHomeScore, intAwayScore: game.intAwayScore, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: game.strStatus, strProgress: game.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: game.strTimestamp, lastPlay: game.lastPlay, isCompleted: game.isCompleted, isoDate: game.isoDate)
            }
        }

        return LiveScore(
            nba: liveScore.nba.map { LiveEvent(events: translateEvents($0.events)) },
            mlb: liveScore.mlb.map { LiveEvent(events: translateEvents($0.events)) },
            soccer: liveScore.soccer.map { LiveEvent(events: translateEvents($0.events)) },
            nfl: liveScore.nfl.map { LiveEvent(events: translateEvents($0.events)) },
            nhl: liveScore.nhl.map { LiveEvent(events: translateEvents($0.events)) },
            golf: liveScore.golf.map { LiveEvent(events: translateEvents($0.events)) },
            tennis: liveScore.tennis.map { LiveEvent(events: translateEvents($0.events)) },
            racing: liveScore.racing.map { LiveEvent(events: translateEvents($0.events)) }
        )
    }
    
    func returnUpdatedEvents(events: [Game], espnEvents: [Game]) -> LiveEvent {
        let newEvents: [Game] = espnEvents.compactMap { event in
            if let foundEvent = events.first(where: {$0.strHomeTeam == event.strHomeTeam && $0.strAwayTeam == event.strAwayTeam}) {
                // Only include essential fields - strSport/strLeague are computed from idLeague
                // Deprecated fields removed: strPlayer, idPlayer, intEventScore, intEventScoreTotal, strEventTime, dateEvent, updated
                return Game(idLiveScore: foundEvent.idLiveScore, idEvent: foundEvent.idEvent, strSport: nil, idLeague: foundEvent.idLeague, strLeague: nil, idHomeTeam: foundEvent.idHomeTeam, idAwayTeam: foundEvent.idAwayTeam, strHomeTeam: foundEvent.strHomeTeam, strAwayTeam: foundEvent.strAwayTeam, strHomeTeamBadge: foundEvent.strHomeTeamBadge, strAwayTeamBadge: foundEvent.strAwayTeamBadge, intHomeScore: event.intHomeScore, intAwayScore: event.intAwayScore, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: event.strStatus, strProgress: event.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: foundEvent.strTimestamp, isCompleted: event.isCompleted, isoDate: Game.getDate(timestamp: foundEvent.strTimestamp))
            } else {
                return event
            }
        }
        if newEvents.isEmpty {
            return LiveEvent(events: espnEvents)
        }

        return LiveEvent(events: newEvents)
    }
}
extension Game {
    func getDate() -> Date? {
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        DateFormatters.backupISOFormatter.timeZone = .init(secondsFromGMT: 0)
        guard let timestamp = strTimestamp else { return nil }
        if let date = DateFormatters.isoFormatter.date(from: timestamp) {
            return date
        }
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }
    static func getDate(timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        DateFormatters.backupISOFormatter.timeZone = .init(secondsFromGMT: 0)
        if let date = DateFormatters.isoFormatter.date(from: timestamp) {
            return date
        }
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }
}
