import Vapor
import SportsCalModel
import VaporAPNS
import APNSCore
import RediStack


func routes(_ app: Application) throws {
    // Register API version middleware globally
    app.middleware.use(APIVersionMiddleware())

    // MARK: - Admin Routes
    // Admin dashboard endpoints for monitoring and management
    try app.register(collection: AdminController())

    // MARK: - Versioned Routes (v2025)
    // Use versioned routes for new clients. Legacy routes remain for backward compatibility.
    let v2025 = app.grouped("v2025")
    registerAPIRoutes(on: v2025, app: app)

    // MARK: - Legacy Routes (unversioned)
    // Keep for backward compatibility with older app versions
    registerAPIRoutes(on: app, app: app)
}

/// Registers all API routes on a given route builder.
/// This allows the same routes to be registered under both versioned and legacy paths.
private func registerAPIRoutes(on routes: RoutesBuilder, app: Application) {
    //MARK: - Schedules
    routes.get("schedules") { req async throws -> String in
        let schedule = try await req.application.redis.get(RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: req.application.environment == .development), asJSON: LiveScore.self)
        guard let schedule = schedule else { throw NetworkError.invalidData }
        return encodeResult(res: schedule)
    }

    //MARK: - Sport
    routes.get("sport", ":sport") { req in
        let sport = SportType(rawValue: req.parameters.get("sport")!)
        let schedule = try await req.application.redis.get(RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: req.application.environment == .development), asJSON: LiveScore.self)
        let result: LiveEvent?
        switch sport {
        case .basketball:
            guard let nba = schedule?.nba else { throw Abort(.badRequest) }
            result = nba
        case .soccer:
            guard let soccer = schedule?.soccer else { throw Abort(.badRequest) }
            result = soccer
        case .hockey:
            guard let nhl = schedule?.nhl else { throw Abort(.badRequest) }
            result = nhl
        case .mlb:
            guard let mlb = schedule?.mlb else { throw Abort(.badRequest) }
            result = mlb
        case .nfl:
            guard let nfl = schedule?.nfl else { throw Abort(.badRequest) }
            result = nfl
        case .golf:
            guard let golf = schedule?.golf else { throw Abort(.badRequest) }
            result = golf
        case .tennis:
            guard let tennis = schedule?.tennis else { throw Abort(.badRequest) }
            result = tennis
        case .racing:
            guard let racing = schedule?.racing else { throw Abort(.badRequest) }
            result = racing
        case .none:
            throw Abort(.badRequest)
        }
        if let res = result {
            return encodeResult(res: res)
        } else {
            throw Abort(.badRequest)
        }
    }

    //MARK: - Teams
    routes.get("teams") { req async throws -> String in
        let teams = try await req.redis.get(RedisEndpoint.teams.getValue(isDebug: req.application.environment == .development), asJSON: [Team].self) ?? []
        return encodeResult(res: teams)
    }

    //MARK: - Live Websocket
    routes.webSocket("ws") { req, ws async in
        let isDebug = req.application.environment == .development
        var lastSentHash: Int? = nil

        while !ws.isClosed {
            do {
                // Check if there are live or upcoming games before pushing data
                let hasGames = await Integrator.hasLiveOrUpcomingGames(
                    redis: req.application.redis,
                    isDebug: isDebug
                )

                if hasGames {
                    let result = try await req.application.redis.get(
                        RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug),
                        asJSON: LiveScore.self
                    )
                    let stringResult = encodeResult(res: result)

                    // Only send if data actually changed (avoids redundant 1MB+ pushes)
                    let currentHash = stringResult.hashValue
                    if currentHash != lastSentHash {
                        try await ws.send(stringResult)
                        lastSentHash = currentHash
                    }

                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5s when live
                } else {
                    // No live games — sleep longer and send lightweight heartbeat
                    lastSentHash = nil
                    try await ws.send("{}")
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 60s when idle
                }
            } catch {
                req.logger.error("WebSocket live score push failed", metadata: ["error": "\(error)"])
                break
            }
        }
    }

    //MARK: - all-live-games
    routes.get("all-live-games") { req async throws -> String in
        let liveScore = try await req.application.redis.get(RedisEndpoint.ESPN.latestFullLiveInfo.getValue(isDebug: req.application.environment == .development), asJSON: LiveScore.self)
        return encodeResult(res: liveScore)
    }

    //MARK: DEBUG
    if app.environment == .development {
        //MARK: - livedebug websocket
        routes.webSocket("livedebug") { req, ws async in
            while !ws.isClosed {
                do {
                    var directory = req.application.directory.workingDirectory
                    directory.append("/LiveTest.json")
                    let fileURL = URL(fileURLWithPath: directory)
                    var jsonScore = try JSONDecoder().decode(LiveScore.self, from: Data(contentsOf: fileURL))
                    
                    
                    let newEvents: [Game] = jsonScore.soccer?.events
                        .compactMap({ game -> Game in
                            let newHomeScore = "\(Int.random(in: 1...5))"
                            let newAwayScore = "\(Int.random(in: 1...5))"
                            // Only include essential fields - strSport/strLeague are computed from idLeague
                            return Game(idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: nil, idLeague: game.idLeague, strLeague: nil, idHomeTeam: game.idHomeTeam, idAwayTeam: game.idAwayTeam, strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam, strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge, intHomeScore: newHomeScore, intAwayScore: newAwayScore, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: game.strStatus, strProgress: game.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: game.strTimestamp, isoDate: nil)

                        }) ?? []
                    jsonScore.soccer?.events = newEvents
                    try await Task.sleep(nanoseconds: 5000000000)
                    let stringResult = encodeResult(res: jsonScore)
                    try await ws.send(stringResult)
                } catch {
                    req.logger.error("Debug WebSocket live score push failed", metadata: ["error": "\(error)"])
                }
            }
        }

        //MARK: - live-debug
        routes.get("live-debug") { req async throws in
            var directory = req.application.directory.workingDirectory
            directory.append("/MockLive.json")
            let fileURL = URL(fileURLWithPath: directory)
            let jsonScore = try JSONDecoder().decode(LiveScore.self, from: Data(contentsOf: fileURL))
            let stringResult = encodeResult(res: jsonScore)
            return stringResult
        }

        //MARK: - Debug Push-to-Start Trigger
        routes.post("debug", "trigger-push-to-start") { req async throws -> String in
            struct DebugTriggerRequest: Content {
                var eventID: String
                var homeTeam: String
                var awayTeam: String
            }

            let body = try req.content.decode(DebugTriggerRequest.self)
            let isDebug = req.application.environment == .development
            let keyPrefix = isDebug ? "debug-PushToStart-" : "PushToStart-"
            let keyPattern = "\(keyPrefix)*"
            let apnsConfigured = req.application.storage[APNSConfiguredKey.self] ?? false

            // Build diagnostic trace
            var trace: [String] = []
            trace.append("env=\(req.application.environment.name)")
            trace.append("keyPattern=\(keyPattern)")
            trace.append("apnsConfigured=\(apnsConfigured)")
            trace.append("triggerEventID=\(body.eventID)")
            trace.append("triggerHome=\(body.homeTeam)")
            trace.append("triggerAway=\(body.awayTeam)")

            // Step 1: Find registration keys
            let allKeys = (try? await req.application.redis.send(command: "keys", with: [keyPattern.convertedToRESPValue()])
                .array?
                .compactMap({ $0.string })) ?? []
            trace.append("allKeysMatching=\(allKeys.count): \(allKeys)")

            let registrationKeys = allKeys
                .filter({ !$0.contains("Events-") && !$0.contains("SentPush") })
                .map({ RedisKey($0) })
            trace.append("registrationKeys=\(registrationKeys.count): \(registrationKeys.map(\.rawValue))")

            guard !registrationKeys.isEmpty else {
                let traceStr = trace.joined(separator: "\n")
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let result: [String: Any] = ["notified": 0, "tokens": [] as [String], "reason": "no_registrations", "trace": traceStr]
                let data = try JSONSerialization.data(withJSONObject: result)
                return String(data: data, encoding: .utf8)!
            }

            guard apnsConfigured else {
                let traceStr = trace.joined(separator: "\n")
                let result: [String: Any] = ["notified": 0, "tokens": [] as [String], "reason": "apns_not_configured", "trace": traceStr]
                let data = try JSONSerialization.data(withJSONObject: result)
                return String(data: data, encoding: .utf8)!
            }

            let apnsClient = req.application.environment == .development
                ? await req.application.apns.client(.development)
                : await req.application.apns.client(.production)
            var notifiedTokens: [String] = []
            var errors: [String] = []

            for registrationKey in registrationKeys {
                let token = String(registrationKey.rawValue.dropFirst(keyPrefix.count))

                let favorites = (try? await req.application.redis.get(registrationKey, asJSON: [String].self)) ?? []
                let favoritesMatch = favorites.contains(where: { $0 == body.homeTeam || $0 == body.awayTeam })

                let eventsKey = RedisEndpoint.pushToStartEvents(token).getValue(isDebug: isDebug)
                let eventIDs = (try? await req.application.redis.get(eventsKey, asJSON: [String].self)) ?? []
                let eventMatch = eventIDs.contains(body.eventID)

                trace.append("token=\(token.prefix(12))... favorites=\(favorites) eventIDs=\(eventIDs) favMatch=\(favoritesMatch) eventMatch=\(eventMatch)")

                guard favoritesMatch || eventMatch else { continue }

                let attributes = LiveSportAttributes(
                    homeTeam: body.homeTeam,
                    awayTeam: body.awayTeam,
                    eventID: body.eventID
                )
                let contentState = ContentState(
                    homeScore: 12,
                    awayScore: 9,
                    status: "in",
                    progress: "4:20 - 1st"
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
                            title: .raw("\(body.homeTeam) vs \(body.awayTeam)"),
                            body: .raw("Debug game is starting now!")
                        )
                    )
                    try await apnsClient.sendStartLiveActivityNotification(notification, deviceToken: token)
                    notifiedTokens.append(String(token.prefix(12)) + "...")
                    trace.append("SENT OK to \(token.prefix(12))...")
                } catch {
                    let errMsg = "\(error)"
                    errors.append("\(token.prefix(12))...: \(errMsg)")
                    trace.append("SEND FAILED \(token.prefix(12))...: \(errMsg)")
                    if let apnsError = error as? APNSError,
                       apnsError.reason == .badDeviceToken || apnsError.reason == .unregistered {
                        _ = try? await req.application.redis.delete([registrationKey]).get()
                        _ = try? await req.application.redis.delete([eventsKey]).get()
                        trace.append("Removed stale token \(token.prefix(12))...")
                    }
                }
            }

            let traceStr = trace.joined(separator: "\n")
            var result: [String: Any] = [
                "notified": notifiedTokens.count,
                "tokens": notifiedTokens,
                "trace": traceStr
            ]
            if !errors.isEmpty { result["errors"] = errors }
            if notifiedTokens.isEmpty && registrationKeys.count > 0 {
                result["reason"] = "no_match"
            }
            let data = try JSONSerialization.data(withJSONObject: result)
            return String(data: data, encoding: .utf8)!
        }

    }

    //MARK: - live
    routes.get("live") { req async throws in
        var result = try await req.application.redis.get(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: req.application.environment == .development), asJSON: LiveScore.self)
        result?.removeNonStarting()
//        result?.removeOtherInfo()
        return encodeResult(res: result)
    }

    //MARK: - liveActivity
    routes.get("liveActivity",":token",":eventID") { req async throws in
        let token = req.parameters.get("token")!
        let eventID = req.parameters.get("eventID")!
        if req.application.environment == .development {
            try await req.application.redis.setex("debug-APNS-\(token)", to: eventID, expirationInSeconds: 60 * 60 * 8).get()
        } else {
            try await req.application.redis.setex("APNS-\(token)", to: eventID, expirationInSeconds: 60 * 60 * 8).get()
        }
        return HTTPStatus.ok
    }

    //MARK: - livescore/sport
    routes.webSocket("livescore",":sport") { req, ws async in
        let sport = SportType(rawValue: req.parameters.get("sport")!)
        do {
            switch sport {
            case .basketball:
                let basketball: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .basketball)
                let result = LiveScore(nba: basketball)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .soccer:
                let soccer: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .soccer)
                let result = LiveScore(soccer: soccer)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .hockey:
                let hockey: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .hockey)
                let result = LiveScore(nhl: hockey)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .nfl:
                let mlb: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .mlb)
                let result = LiveScore(mlb: mlb)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .mlb:
                let nfl: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .nfl)
                let result = LiveScore(nfl: nfl)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .golf:
                let golf: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .golf)
                let result = LiveScore(golf: golf)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .tennis:
                let tennis: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .tennis)
                let result = LiveScore(tennis: tennis)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .racing:
                let racing: LiveEvent? = try await SportsDBNetworking.callLiveScore(req: req.client, DecodeType: LiveEvent.self, scoreType: .motorsport)
                let result = LiveScore(racing: racing)
                let stringData = encodeResult(res: result)
                try await ws.send(stringData)
            case .none:
                req.logger.warning("livescore WebSocket called with invalid sport")
            }
        } catch {
            req.logger.error("livescore WebSocket failed", metadata: [
                "sport": "\(sport?.rawValue ?? "nil")",
                "error": "\(error)"
            ])
        }

    }

    //MARK: - test-call
    routes.get("test-call") { req async in
        req.logger.info("test-call endpoint hit")
        return "Welcome to sportscal! BG task call"
    }

    //MARK: - Standings
    routes.get("standings", ":leagueID") { req async throws -> String in
        guard let leagueIDString = req.parameters.get("leagueID"),
              let leagueID = Int(leagueIDString),
              let league = Leagues(rawValue: leagueID) else {
            throw Abort(.badRequest)
        }
        let standingsResponse = try await ESPNNetworking.getStandings(req: req.client, DecodeType: StandingsResponse.self, league: league)
        let standing = Standing(id: league, standings: standingsResponse)
        return encodeResult(res: standing)
    }

    //MARK: - Standings History
    routes.get("standings", ":leagueID", "history") { req async throws -> String in
        guard let leagueIDString = req.parameters.get("leagueID"),
              let leagueID = Int(leagueIDString),
              let _ = Leagues(rawValue: leagueID) else {
            throw Abort(.badRequest)
        }
        let days = (try? req.query.get(Int.self, at: "days")) ?? 30
        let isDebug = req.application.environment == .development

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var snapshots: [StandingsSnapshot] = []
        let today = Date()

        for dayOffset in 0..<min(days, 90) {
            guard let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = formatter.string(from: date)
            let key: RedisKey = isDebug
                ? "debug-Standings-\(leagueID)-\(dateStr)"
                : "Standings-\(leagueID)-\(dateStr)"

            if let json = try await req.application.redis.get(key, as: String.self).get(),
               let data = json.data(using: .utf8),
               let snapshot = try? JSONDecoder().decode(StandingsSnapshot.self, from: data) {
                snapshots.append(snapshot)
            }
        }

        snapshots.sort { $0.date < $1.date }
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshots)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    //MARK: - Team Stats
    routes.get("stats", ":leagueID", "teams") { req async throws -> String in
        guard let leagueIDString = req.parameters.get("leagueID"),
              let leagueID = Int(leagueIDString),
              let league = Leagues(rawValue: leagueID) else {
            throw Abort(.badRequest)
        }
        let standingsResponse = try await ESPNNetworking.getStandings(
            req: req.client,
            DecodeType: StandingsResponse.self,
            league: league
        )

        // Reshape standings entries into team stat objects
        var teamStats: [[String: Any]] = []
        if let children = standingsResponse.children {
            for child in children {
                guard let entries = child.standings?.entries else { continue }
                for entry in entries {
                    var statDict: [String: String] = [:]
                    for stat in entry.stats ?? [] {
                        if let name = stat.name, let value = stat.displayValue {
                            statDict[name] = value
                        }
                    }
                    let teamObj: [String: Any] = [
                        "teamName": entry.team?.displayName ?? "Unknown",
                        "teamAbbreviation": entry.team?.abbreviation ?? "",
                        "teamColor": entry.team?.color ?? "",
                        "teamLogo": entry.team?.logos?.first?.href ?? "",
                        "division": child.name ?? "",
                        "stats": statDict
                    ]
                    teamStats.append(teamObj)
                }
            }
        }

        let data = try JSONSerialization.data(withJSONObject: teamStats)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    //MARK: - Player Stats (Stat Leaders)
    routes.get("stats", ":leagueID", "players") { req async throws -> String in
        guard let leagueIDString = req.parameters.get("leagueID"),
              let leagueID = Int(leagueIDString),
              let league = Leagues(rawValue: leagueID) else {
            throw Abort(.badRequest)
        }

        let isDebug = req.application.environment == .development
        let cacheKey = "PlayerStats-\(leagueID)"

        // Check Redis cache first (24h TTL)
        if let cached = try? await req.application.redis.get(RedisKey(cacheKey), as: String.self).get() {
            return cached
        }

        let leadersResponse = try await ESPNNetworking.getLeaders(
            req: req.client,
            DecodeType: LeadersResponse.self,
            league: league
        )

        var categories: [[String: Any]] = []
        for category in leadersResponse.leaders ?? [] {
            var entries: [[String: Any]] = []
            for leader in category.leaders ?? [] {
                var entry: [String: Any] = [
                    "value": leader.displayValue ?? ""
                ]
                if let athlete = leader.athlete {
                    entry["playerName"] = athlete.displayName ?? ""
                    entry["shortName"] = athlete.shortName ?? ""
                    entry["headshot"] = athlete.headshot?.href ?? ""
                    entry["position"] = athlete.position?.abbreviation ?? ""
                }
                if let team = leader.team {
                    entry["teamName"] = team.displayName ?? ""
                    entry["teamAbbreviation"] = team.abbreviation ?? ""
                    entry["teamColor"] = team.color ?? ""
                    entry["teamLogo"] = team.logos?.first?.href ?? ""
                }
                entries.append(entry)
            }
            categories.append([
                "name": category.name ?? "",
                "displayName": category.displayName ?? "",
                "abbreviation": category.abbreviation ?? "",
                "leaders": entries
            ])
        }

        let data = try JSONSerialization.data(withJSONObject: categories)
        let result = String(data: data, encoding: .utf8) ?? "[]"

        // Cache for 24 hours
        try? await req.application.redis.setex(RedisKey(cacheKey), to: result, expirationInSeconds: 60 * 60 * 24)

        return result
    }

    //MARK: - Push-to-Start Registration
    routes.post("pushToStart", "register") { req async throws -> HTTPStatus in
        let registration = try req.content.decode(PushToStartRegistration.self)
        let isDebug = req.application.environment == .development
        let key = RedisEndpoint.pushToStart(registration.token).getValue(isDebug: isDebug)
        try await req.application.redis.setex(key, toJSON: registration.favorites, expirationInSeconds: 60 * 60 * 24)

        // Store auto-follow event IDs if provided
        if let eventIDs = registration.eventIDs, !eventIDs.isEmpty {
            let eventsKey = RedisEndpoint.pushToStartEvents(registration.token).getValue(isDebug: isDebug)
            try await req.application.redis.setex(eventsKey, toJSON: eventIDs, expirationInSeconds: 60 * 60 * 24)
            req.logger.info("Registered push-to-start token with \(registration.favorites.count) favorites, \(eventIDs.count) event IDs")
        } else {
            // Clear event IDs if none provided (user removed all auto-follows)
            let eventsKey = RedisEndpoint.pushToStartEvents(registration.token).getValue(isDebug: isDebug)
            _ = try? await req.application.redis.delete(eventsKey).get()
            req.logger.info("Registered push-to-start token with \(registration.favorites.count) favorites")
        }
        return .ok
    }

    //MARK: - teams-by-league
    routes.get("teams-by-league") { req async throws -> String in
        let result = try await req.application.redis.get(RedisEndpoint.ESPN.teams.getValue(isDebug: req.application.environment == .development), asJSON: [Leagues: TeamResponse].self)
        return encodeResult(res: result)
    }

    //MARK: - Widget Schedule (lightweight combined endpoint)
    routes.get("widget", "schedule") { req async throws -> String in
        let sportsParam = (try? req.query.get(String.self, at: "sports")) ?? ""
        let limit = (try? req.query.get(Int.self, at: "limit")) ?? 6
        let favoritesParam = (try? req.query.get(String.self, at: "favorites")) ?? ""

        let requestedSports = Set(sportsParam.split(separator: ",").map(String.init))
        let favoriteTeams = Set(favoritesParam.split(separator: ",").map(String.init))

        // Load full schedule from Redis
        guard let schedule = try await req.application.redis.get(
            RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: req.application.environment == .development),
            asJSON: LiveScore.self
        ) else {
            throw NetworkError.invalidData
        }

        // Collect events from requested sports
        let sportEvents: [(String, LiveEvent?)] = [
            ("basketball", schedule.nba),
            ("soccer", schedule.soccer),
            ("hockey", schedule.nhl),
            ("mlb", schedule.mlb),
            ("nfl", schedule.nfl),
            ("golf", schedule.golf),
            ("tennis", schedule.tennis),
            ("racing", schedule.racing),
        ]

        var allGames: [Game] = []
        for (sportName, liveEvent) in sportEvents {
            guard requestedSports.isEmpty || requestedSports.contains(sportName) else { continue }
            if let events = liveEvent?.events {
                allGames.append(contentsOf: events)
            }
        }

        // Filter to upcoming games only
        let now = Calendar.current.startOfDay(for: Date())
        allGames = allGames.filter { ($0.isoDate ?? .distantPast) >= now }

        // Sort: favorites first, then by date
        allGames.sort { g1, g2 in
            let g1Fav = favoriteTeams.contains(g1.strHomeTeam) || favoriteTeams.contains(g1.strAwayTeam)
            let g2Fav = favoriteTeams.contains(g2.strHomeTeam) || favoriteTeams.contains(g2.strAwayTeam)
            if g1Fav && !g2Fav { return true }
            if !g1Fav && g2Fav { return false }
            return (g1.isoDate ?? .distantFuture) < (g2.isoDate ?? .distantFuture)
        }

        // Trim to limit
        let trimmed = Array(allGames.prefix(limit))

        // Strip heavy fields — keep only what the widget needs
        let strippedGames = trimmed.map { game -> Game in
            // Trim leaderboard to top 3, drop headshots
            let strippedLeaderboard = game.leaderboardEntries?.prefix(3).map { entry in
                LeaderboardEntry(
                    name: entry.name,
                    score: entry.score,
                    position: entry.position,
                    headshot: nil,
                    thruHole: entry.thruHole,
                    rounds: [],
                    constructor: entry.constructor,
                    gap: entry.gap
                )
            }

            // Trim lastPlay to top 3 lines (for legacy leaderboard parsing)
            let trimmedLastPlay: String? = game.lastPlay.flatMap { lp in
                let lines = lp.split(separator: "\n", omittingEmptySubsequences: false)
                return lines.isEmpty ? nil : lines.prefix(3).joined(separator: "\n")
            }

            return Game(
                idEvent: game.idEvent,
                idLeague: game.idLeague,
                idHomeTeam: game.idHomeTeam,
                idAwayTeam: game.idAwayTeam,
                strHomeTeam: game.strHomeTeam,
                strAwayTeam: game.strAwayTeam,
                intHomeScore: game.intHomeScore,
                intAwayScore: game.intAwayScore,
                strStatus: game.strStatus,
                strProgress: game.strProgress,
                strTimestamp: game.strTimestamp,
                lastPlay: trimmedLastPlay,
                isCompleted: game.isCompleted,
                isoDate: game.isoDate,
                leaderboardEntries: strippedLeaderboard.map(Array.init)
            )
        }

        // Only include teams referenced by returned games
        let teamIDs = Set(strippedGames.flatMap { [$0.idHomeTeam, $0.idAwayTeam].compactMap { $0 } })
        let allTeams = try await req.application.redis.get(
            RedisEndpoint.teams.getValue(isDebug: req.application.environment == .development),
            asJSON: [Team].self
        ) ?? []
        let relevantTeams = allTeams.filter { teamIDs.contains($0.idTeam ?? "") }

        let response = WidgetScheduleResponse(games: strippedGames, teams: relevantTeams)
        return encodeResult(res: response)
    }
}

/// Lightweight response for the widget schedule endpoint
struct WidgetScheduleResponse: Codable {
    let games: [Game]
    let teams: [Team]
}

func encodeResult(res: some Codable) -> String {
    let encoder = JSONEncoder()
    guard let resultString = try? encoder.encode(res) else { return "" }
    return String(data: resultString, encoding: .utf8) ?? ""
}
