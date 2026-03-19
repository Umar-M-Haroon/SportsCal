//
//  AdminController.swift
//
//
//  Created by Claude Code
//

import Vapor
import Redis
import SportsCalModel
import Queues

struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let admin = routes.grouped("api", "admin")

        // Read endpoints
        admin.get("health", use: health)
        admin.get("metrics", use: metrics)
        admin.get("redis", "keys", use: redisKeys)
        admin.get("redis", "key", ":key", use: redisKey)
        admin.get("data-gaps", use: dataGaps)
        admin.get("leagues", ":league", "stats", use: leagueStats)
        admin.get("live-tsdb", use: liveTSDB)
        admin.get("live-espn", use: liveESPN)

        admin.get("push-to-start", "registrations", use: pushToStartRegistrations)
        admin.get("push-to-start", "diagnostics", use: pushToStartDiagnostics)
        admin.get("push-to-start", "device-status", use: pushToStartDeviceStatus)

        // Write endpoints
        admin.post("redis", "invalidate", ":key", use: invalidateKey)
        admin.post("redis", "refresh", use: refreshSchedules)
        admin.post("force-refresh", use: forceRefresh)
        admin.post("jobs", "trigger", ":jobName", use: triggerJob)
        admin.delete("cache", "all", use: clearAllCache)
    }

    // MARK: - Health Endpoint

    struct HealthResponse: Content {
        let status: String
        let redis: RedisHealth
        let jobs: [JobStatus]
        let timestamp: String
    }

    struct RedisHealth: Content {
        let connected: Bool
        let keyCount: Int?
        let memory: String?
    }

    struct JobStatus: Content {
        let name: String
        let schedule: String
        let lastRun: String?
        let status: String
    }

    func health(req: Request) async throws -> HealthResponse {
        let isDebug = req.application.environment == .development

        // Check Redis connection and get key count
        var keyCount: Int?
        var isConnected = false
        var memory: String?

        do {
            let keys = try await req.redis.send(command: "KEYS", with: [.init(from: "*")]).get()
            if case .array(let keyArray) = keys {
                keyCount = keyArray.count
            }

            let info = try await req.redis.send(command: "INFO", with: [.init(from: "memory")]).get()
            if case .bulkString(let buffer) = info,
               let infoString = buffer.map({ String(buffer: $0) }) {
                // Parse memory info
                let lines = infoString.components(separatedBy: "\r\n")
                if let usedMemoryLine = lines.first(where: { $0.hasPrefix("used_memory_human:") }) {
                    memory = usedMemoryLine.replacingOccurrences(of: "used_memory_human:", with: "")
                }
            }

            isConnected = true
        } catch {
            req.logger.error("Redis health check failed: \(error)")
        }

        // Get last update times from Redis
        let scheduleLastUpdate = try? await req.redis.get(
            RedisEndpoint.ESPN.scheduleLastUpdate.getValue(isDebug: isDebug),
            as: String.self
        ).get()

        let jobs = [
            JobStatus(name: "ScheduleUpdateJob", schedule: "Every second", lastRun: scheduleLastUpdate, status: "active"),
            JobStatus(name: "APNSJob", schedule: "Every second", lastRun: nil, status: "active"),
            JobStatus(name: "ESPNFetchJob", schedule: "Minutely at :15", lastRun: nil, status: "active"),
            JobStatus(name: "ESPNSoccerJob", schedule: "Minutely at :02", lastRun: nil, status: "active"),
            JobStatus(name: "ESPNTennisJob", schedule: "Minutely at :02", lastRun: nil, status: "active"),
            JobStatus(name: "ESPNTeamFetchJob", schedule: "Hourly at :38", lastRun: nil, status: "active")
        ]

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return HealthResponse(
            status: isConnected ? "healthy" : "degraded",
            redis: RedisHealth(connected: isConnected, keyCount: keyCount, memory: memory),
            jobs: jobs,
            timestamp: dateFormatter.string(from: Date())
        )
    }

    // MARK: - Metrics Endpoint

    struct MetricsResponse: Content {
        let totalRequests: Int
        let averageResponseTime: Double
        let errorRate: Double
        let timestamp: String
    }

    func metrics(req: Request) async throws -> MetricsResponse {
        // Placeholder for now - in production, you'd integrate with actual metrics collection
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return MetricsResponse(
            totalRequests: 0,
            averageResponseTime: 0.0,
            errorRate: 0.0,
            timestamp: dateFormatter.string(from: Date())
        )
    }

    // MARK: - Redis Keys Endpoint

    struct RedisKeyInfo: Content {
        let key: String
        let type: String
        let size: Int?
        let ttl: Int?
    }

    struct RedisKeysResponse: Content {
        let keys: [RedisKeyInfo]
        let total: Int
    }

    func redisKeys(req: Request) async throws -> RedisKeysResponse {
        let keysResponse = try await req.redis.send(command: "KEYS", with: [.init(from: "*")]).get()

        var keyInfos: [RedisKeyInfo] = []

        if case .array(let keyArray) = keysResponse {
            for keyData in keyArray {
                if case .bulkString(let buffer) = keyData,
                   let keyString = buffer.map({ String(buffer: $0) }) {

                    // Get key type
                    let typeResponse = try await req.redis.send(command: "TYPE", with: [.init(from: keyString)]).get()
                    var typeString = "unknown"
                    if case .simpleString(let buffer) = typeResponse {
                        typeString = String(buffer: buffer)
                    }

                    // Get TTL
                    let ttlResponse = try await req.redis.send(command: "TTL", with: [.init(from: keyString)]).get()
                    var ttl: Int?
                    if case .integer(let ttlValue) = ttlResponse, ttlValue >= 0 {
                        ttl = ttlValue
                    }

                    // Get size (approximate)
                    var size: Int?
                    if typeString == "string" {
                        let strlenResponse = try await req.redis.send(command: "STRLEN", with: [.init(from: keyString)]).get()
                        if case .integer(let length) = strlenResponse {
                            size = length
                        }
                    }

                    keyInfos.append(RedisKeyInfo(key: keyString, type: typeString, size: size, ttl: ttl))
                }
            }
        }

        return RedisKeysResponse(keys: keyInfos, total: keyInfos.count)
    }

    // MARK: - Redis Key Content Endpoint

    struct RedisKeyContentResponse: Content {
        let key: String
        let type: String
        let value: String
        let ttl: Int?
    }

    func redisKey(req: Request) async throws -> RedisKeyContentResponse {
        guard let key = req.parameters.get("key") else {
            throw Abort(.badRequest, reason: "Key parameter is required")
        }

        // Get key type
        let typeResponse = try await req.redis.send(command: "TYPE", with: [.init(from: key)]).get()
        var typeString = "unknown"
        if case .simpleString(let buffer) = typeResponse {
            typeString = String(buffer: buffer)
        }

        // Get TTL
        let ttlResponse = try await req.redis.send(command: "TTL", with: [.init(from: key)]).get()
        var ttl: Int?
        if case .integer(let ttlValue) = ttlResponse, ttlValue >= 0 {
            ttl = ttlValue
        }

        // Get value
        let valueResponse = try await req.redis.get(RedisKey(key), as: String.self).get()
        let value = valueResponse ?? "null"

        return RedisKeyContentResponse(key: key, type: typeString, value: value, ttl: ttl)
    }

    // MARK: - Data Gaps Endpoint

    struct DataGapsResponse: Content {
        let leagues: [LeagueAnalysis]
        let summary: GapSummary
        let timestamp: String
    }

    struct LeagueAnalysis: Content {
        let league: String
        let leagueId: Int
        let sport: String
        let totalGames: Int
        let gamesWithoutBadges: Int
        let gamesWithoutScores: Int
        let gamesWithoutTimestamps: Int
        let completeness: Double
    }

    struct GapSummary: Content {
        let totalLeagues: Int
        let totalGames: Int
        let overallCompleteness: Double
        let leaguesWithIssues: Int
    }

    func dataGaps(req: Request) async throws -> DataGapsResponse {
        let isDebug = req.application.environment == .development

        // Get the latest schedule
        let schedule = try await req.application.redis.get(
            RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug),
            asJSON: LiveScore.self
        )

        var leagueAnalyses: [LeagueAnalysis] = []
        var totalGames = 0

        // Analyze each sport
        if let nba = schedule?.nba {
            let analysis = analyzeLeague(events: nba.events, league: .nba)
            leagueAnalyses.append(analysis)
            totalGames += nba.events.count
        }

        if let nfl = schedule?.nfl {
            let analysis = analyzeLeague(events: nfl.events, league: .nfl)
            leagueAnalyses.append(analysis)
            totalGames += nfl.events.count
        }

        if let nhl = schedule?.nhl {
            let analysis = analyzeLeague(events: nhl.events, league: .nhl)
            leagueAnalyses.append(analysis)
            totalGames += nhl.events.count
        }

        if let mlb = schedule?.mlb {
            let analysis = analyzeLeague(events: mlb.events, league: .mlb)
            leagueAnalyses.append(analysis)
            totalGames += mlb.events.count
        }

        // Analyze soccer leagues
        if let soccer = schedule?.soccer {
            let soccerLeagues = Dictionary(grouping: soccer.events) { game -> Leagues? in
                guard let idLeague = game.idLeague,
                      let leagueID = Int(idLeague),
                      let league = Leagues(rawValue: leagueID) else {
                    return nil
                }
                return league
            }

            for (league, games) in soccerLeagues {
                guard let league = league else { continue }
                let analysis = analyzeLeague(events: games, league: league)
                leagueAnalyses.append(analysis)
                totalGames += games.count
            }
        }

        if let golf = schedule?.golf {
            let analysis = analyzeLeague(events: golf.events, league: .pga)
            leagueAnalyses.append(analysis)
            totalGames += golf.events.count
        }

        // Analyze tennis leagues
        if let tennis = schedule?.tennis {
            let tennisLeagues = Dictionary(grouping: tennis.events) { game -> Leagues? in
                guard let idLeague = game.idLeague,
                      let leagueID = Int(idLeague),
                      let league = Leagues(rawValue: leagueID) else {
                    return nil
                }
                return league
            }

            for (league, games) in tennisLeagues {
                guard let league = league else { continue }
                let analysis = analyzeLeague(events: games, league: league)
                leagueAnalyses.append(analysis)
                totalGames += games.count
            }
        }

        if let racing = schedule?.racing {
            let analysis = analyzeLeague(events: racing.events, league: .formula1)
            leagueAnalyses.append(analysis)
            totalGames += racing.events.count
        }

        // Calculate summary
        let totalCompleteness = leagueAnalyses.isEmpty ? 0.0 :
            leagueAnalyses.map { $0.completeness }.reduce(0, +) / Double(leagueAnalyses.count)
        let leaguesWithIssues = leagueAnalyses.filter { $0.completeness < 1.0 }.count

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return DataGapsResponse(
            leagues: leagueAnalyses,
            summary: GapSummary(
                totalLeagues: leagueAnalyses.count,
                totalGames: totalGames,
                overallCompleteness: totalCompleteness,
                leaguesWithIssues: leaguesWithIssues
            ),
            timestamp: dateFormatter.string(from: Date())
        )
    }

    private func analyzeLeague(events: [Game], league: Leagues) -> LeagueAnalysis {
        let totalGames = events.count
        let gamesWithoutBadges = events.filter {
            $0.strHomeTeamBadge == nil || $0.strAwayTeamBadge == nil
        }.count
        let gamesWithoutScores = events.filter {
            $0.intHomeScore == nil || $0.intAwayScore == nil
        }.count
        let gamesWithoutTimestamps = events.filter {
            $0.strTimestamp == nil
        }.count

        let issues = gamesWithoutBadges + gamesWithoutScores + gamesWithoutTimestamps
        let maxIssues = totalGames * 3 // 3 potential issues per game
        let completeness = maxIssues > 0 ? Double(maxIssues - issues) / Double(maxIssues) : 1.0

        return LeagueAnalysis(
            league: league.leagueName,
            leagueId: league.rawValue,
            sport: league.sport,
            totalGames: totalGames,
            gamesWithoutBadges: gamesWithoutBadges,
            gamesWithoutScores: gamesWithoutScores,
            gamesWithoutTimestamps: gamesWithoutTimestamps,
            completeness: completeness
        )
    }

    // MARK: - League Stats Endpoint

    struct LeagueStatsResponse: Content {
        let league: String
        let leagueId: Int
        let sport: String
        let totalGames: Int
        let liveGames: Int
        let completedGames: Int
        let upcomingGames: Int
        let teams: [String]
    }

    func leagueStats(req: Request) async throws -> LeagueStatsResponse {
        guard let leagueParam = req.parameters.get("league"),
              let leagueId = Int(leagueParam),
              let league = Leagues(rawValue: leagueId) else {
            throw Abort(.badRequest, reason: "Invalid league ID")
        }

        let isDebug = req.application.environment == .development

        // Get the latest schedule
        let schedule = try await req.application.redis.get(
            RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug),
            asJSON: LiveScore.self
        )

        var games: [Game] = []

        // Get games for the sport
        if league == .nba, let nba = schedule?.nba {
            games = nba.events
        } else if league == .nfl, let nfl = schedule?.nfl {
            games = nfl.events
        } else if league == .nhl, let nhl = schedule?.nhl {
            games = nhl.events
        } else if league == .mlb, let mlb = schedule?.mlb {
            games = mlb.events
        } else if league.isGolf, let golf = schedule?.golf {
            games = golf.events
        } else if league.isTennis, let tennis = schedule?.tennis {
            games = tennis.events.filter { game in
                guard let idLeague = game.idLeague,
                      let gameLeagueId = Int(idLeague) else {
                    return false
                }
                return gameLeagueId == leagueId
            }
        } else if league.isRacing, let racing = schedule?.racing {
            games = racing.events
        } else if let soccer = schedule?.soccer {
            games = soccer.events.filter { game in
                guard let idLeague = game.idLeague,
                      let gameLeagueId = Int(idLeague) else {
                    return false
                }
                return gameLeagueId == leagueId
            }
        }

        // Calculate stats
        let liveGames = games.filter { game in
            !["NS", "FT", "AOT", "pre", "Final", "Final/OT", "AP", "post"].contains(game.strStatus ?? "")
        }.count

        let completedGames = games.filter { game in
            ["FT", "AOT", "Final", "Final/OT", "post"].contains(game.strStatus ?? "")
        }.count

        let upcomingGames = games.filter { game in
            ["NS", "pre"].contains(game.strStatus ?? "")
        }.count

        // Extract unique teams
        var teamSet = Set<String>()
        for game in games {
            teamSet.insert(game.strHomeTeam)
            teamSet.insert(game.strAwayTeam)
        }

        return LeagueStatsResponse(
            league: league.leagueName,
            leagueId: league.rawValue,
            sport: league.sport,
            totalGames: games.count,
            liveGames: liveGames,
            completedGames: completedGames,
            upcomingGames: upcomingGames,
            teams: Array(teamSet).sorted()
        )
    }

    // MARK: - Push-to-Start Registrations

    struct PushToStartRegistrationInfo: Content {
        let tokenPrefix: String
        let favorites: [String]
        let eventIDs: [String]
    }

    struct PushToStartRegistrationsResponse: Content {
        let registrations: [PushToStartRegistrationInfo]
        let totalTokens: Int
    }

    func pushToStartRegistrations(req: Request) async throws -> PushToStartRegistrationsResponse {
        let isDebug = req.application.environment == .development
        let keyPattern = isDebug ? "debug-PushToStart-*" : "PushToStart-*"
        let keyPrefix = isDebug ? "debug-PushToStart-" : "PushToStart-"
        let eventsKeyPrefix = isDebug ? "debug-PushToStartEvents-" : "PushToStartEvents-"

        guard let registrationKeys = try? await req.application.redis.send(command: "keys", with: [keyPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .filter({ !$0.contains("Events-") && !$0.contains("SentPush") })
            .map({ RedisKey($0) }) else {
            return PushToStartRegistrationsResponse(registrations: [], totalTokens: 0)
        }

        var infos: [PushToStartRegistrationInfo] = []

        for registrationKey in registrationKeys {
            let token = String(registrationKey.rawValue.dropFirst(keyPrefix.count))
            let favorites = (try? await req.application.redis.get(registrationKey, asJSON: [String].self)) ?? []
            let eventsKey = RedisKey("\(eventsKeyPrefix)\(token)")
            let eventIDs = (try? await req.application.redis.get(eventsKey, asJSON: [String].self)) ?? []

            infos.append(PushToStartRegistrationInfo(
                tokenPrefix: String(token.prefix(16)) + "...",
                favorites: favorites,
                eventIDs: eventIDs
            ))
        }

        return PushToStartRegistrationsResponse(registrations: infos, totalTokens: infos.count)
    }

    // MARK: - Push-to-Start Diagnostics

    struct PipelineStep: Content {
        let name: String
        let status: String // "green", "yellow", "red"
        let detail: String
    }

    struct TokenPipeline: Content {
        let tokenPrefix: String
        let steps: [PipelineStep]
    }

    struct SystemCheck: Content {
        let name: String
        let ok: Bool
        let detail: String
    }

    struct PushToStartDiagnosticsResponse: Content {
        let system: [SystemCheck]
        let tokens: [TokenPipeline]
    }

    func pushToStartDiagnostics(req: Request) async throws -> PushToStartDiagnosticsResponse {
        let isDebug = req.application.environment == .development
        let keyPrefix = isDebug ? "debug-PushToStart-" : "PushToStart-"
        let eventsKeyPrefix = isDebug ? "debug-PushToStartEvents-" : "PushToStartEvents-"
        let sentKeyPrefix = isDebug ? "debug-SentPushToStart-" : "SentPushToStart-"

        // System checks
        var redisConnected = false
        var tokenCount = 0
        do {
            let pong = try await req.redis.send(command: "PING").get()
            redisConnected = (pong.string == "PONG")
        } catch {}

        let apnsConfigured = req.application.storage[APNSConfiguredKey.self] ?? false

        // Count registration tokens
        let keyPattern = isDebug ? "debug-PushToStart-*" : "PushToStart-*"
        let registrationKeys: [String]
        if let keys = try? await req.application.redis.send(command: "keys", with: [keyPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .filter({ !$0.contains("Events-") && !$0.contains("SentPush") }) {
            registrationKeys = keys
            tokenCount = keys.count
        } else {
            registrationKeys = []
        }

        let systemChecks = [
            SystemCheck(name: "Redis Connected", ok: redisConnected, detail: redisConnected ? "PONG" : "Connection failed"),
            SystemCheck(name: "APNS Configured", ok: apnsConfigured, detail: apnsConfigured ? "Auth key loaded" : "Missing APNSkeyID or TeamID"),
            SystemCheck(name: "Registered Tokens", ok: tokenCount > 0, detail: "\(tokenCount) token(s)")
        ]

        // Per-token pipeline
        var tokenPipelines: [TokenPipeline] = []
        for keyString in registrationKeys {
            let token = String(keyString.dropFirst(keyPrefix.count))
            let shortToken = String(token.prefix(16)) + "..."

            var steps: [PipelineStep] = []

            // Step 1: Token Registered
            steps.append(PipelineStep(name: "Token Registered", status: "green", detail: "Key exists"))

            // Step 2: Events Stored
            let eventsKey = RedisKey("\(eventsKeyPrefix)\(token)")
            let eventIDs = (try? await req.application.redis.get(eventsKey, asJSON: [String].self)) ?? []
            if !eventIDs.isEmpty {
                steps.append(PipelineStep(name: "Events Stored", status: "green", detail: "\(eventIDs.count) event(s)"))
            } else {
                steps.append(PipelineStep(name: "Events Stored", status: "yellow", detail: "No event IDs"))
            }

            // Step 3: APNS Configured
            steps.append(PipelineStep(name: "APNS Configured", status: apnsConfigured ? "green" : "red", detail: apnsConfigured ? "Ready" : "Not configured"))

            // Step 4: Notification Sent
            let sentPattern = "\(sentKeyPrefix)\(token)-*"
            let sentKeys = (try? await req.application.redis.send(command: "keys", with: [sentPattern.convertedToRESPValue()])
                .array?
                .compactMap({ $0.string })) ?? []
            if !sentKeys.isEmpty {
                steps.append(PipelineStep(name: "Notification Sent", status: "green", detail: "\(sentKeys.count) sent"))
            } else {
                steps.append(PipelineStep(name: "Notification Sent", status: "yellow", detail: "None sent yet"))
            }

            // Step 5: Token Valid
            steps.append(PipelineStep(name: "Token Valid", status: "green", detail: "Presumed valid (in Redis)"))

            tokenPipelines.append(TokenPipeline(tokenPrefix: shortToken, steps: steps))
        }

        return PushToStartDiagnosticsResponse(system: systemChecks, tokens: tokenPipelines)
    }

    // MARK: - Push-to-Start Device Status

    struct DeviceStatusResponse: Content {
        let registered: Bool
        let favorites: [String]
        let eventIDs: [String]
        let sentNotifications: [String]
        let apnsConfigured: Bool
    }

    func pushToStartDeviceStatus(req: Request) async throws -> DeviceStatusResponse {
        guard let tokenPrefix = req.query[String.self, at: "tokenPrefix"], tokenPrefix.count >= 16 else {
            throw Abort(.badRequest, reason: "tokenPrefix query parameter required (at least 16 chars)")
        }

        let isDebug = req.application.environment == .development
        let keyPrefix = isDebug ? "debug-PushToStart-" : "PushToStart-"
        let eventsKeyPrefix = isDebug ? "debug-PushToStartEvents-" : "PushToStartEvents-"
        let sentKeyPrefix = isDebug ? "debug-SentPushToStart-" : "SentPushToStart-"
        let keyPattern = "\(keyPrefix)*"

        // Find the full token matching this prefix
        let allKeys = (try? await req.application.redis.send(command: "keys", with: [keyPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .filter({ !$0.contains("Events-") && !$0.contains("SentPush") })) ?? []

        guard let matchingKey = allKeys.first(where: {
            let token = String($0.dropFirst(keyPrefix.count))
            return token.hasPrefix(tokenPrefix)
        }) else {
            return DeviceStatusResponse(registered: false, favorites: [], eventIDs: [], sentNotifications: [], apnsConfigured: req.application.storage[APNSConfiguredKey.self] ?? false)
        }

        let fullToken = String(matchingKey.dropFirst(keyPrefix.count))

        let favorites = (try? await req.application.redis.get(RedisKey(matchingKey), asJSON: [String].self)) ?? []
        let eventsKey = RedisKey("\(eventsKeyPrefix)\(fullToken)")
        let eventIDs = (try? await req.application.redis.get(eventsKey, asJSON: [String].self)) ?? []

        // Find sent notifications
        let sentPattern = "\(sentKeyPrefix)\(fullToken)-*"
        let sentKeys = (try? await req.application.redis.send(command: "keys", with: [sentPattern.convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .map({ String($0.dropFirst("\(sentKeyPrefix)\(fullToken)-".count)) })) ?? []

        let apnsConfigured = req.application.storage[APNSConfiguredKey.self] ?? false

        return DeviceStatusResponse(registered: true, favorites: favorites, eventIDs: eventIDs, sentNotifications: sentKeys, apnsConfigured: apnsConfigured)
    }

    // MARK: - Write Endpoints

    struct InvalidateResponse: Content {
        let success: Bool
        let message: String
    }

    func invalidateKey(req: Request) async throws -> InvalidateResponse {
        guard let key = req.parameters.get("key") else {
            throw Abort(.badRequest, reason: "Key parameter is required")
        }

        let deleted = try await req.redis.delete([RedisKey(key)]).get()

        return InvalidateResponse(
            success: deleted > 0,
            message: deleted > 0 ? "Key '\(key)' invalidated successfully" : "Key '\(key)' not found"
        )
    }

    struct RefreshResponse: Content {
        let success: Bool
        let message: String
        let keysRefreshed: [String]
    }

    func refreshSchedules(req: Request) async throws -> RefreshResponse {
        let isDebug = req.application.environment == .development

        // Delete main schedule keys to force refresh
        let keysToDelete = [
            RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug),
            RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug),
            RedisEndpoint.ESPN.latestFullLiveInfo.getValue(isDebug: isDebug),
            RedisEndpoint.ESPN.latestSoccerScoreboards.getValue(isDebug: isDebug),
            RedisEndpoint.ESPN.latestTennisScoreboards.getValue(isDebug: isDebug)
        ]

        var deletedKeys: [String] = []

        for key in keysToDelete {
            let deleted = try await req.redis.delete([key]).get()
            if deleted > 0 {
                deletedKeys.append(String(key.rawValue))
            }
        }

        return RefreshResponse(
            success: true,
            message: "Schedule cache cleared. Data will refresh on next job run.",
            keysRefreshed: deletedKeys
        )
    }

    struct ForceRefreshResponse: Content {
        let success: Bool
        let message: String
        let keysCleared: [String]
        let gamesLoaded: [String: Int]
    }

    func forceRefresh(req: Request) async throws -> ForceRefreshResponse {
        let isDebug = req.application.environment == .development

        // Step 1: Clear schedule cache keys to bypass freshness check
        let keysToDelete = [
            RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug),
            RedisEndpoint.ESPN.scheduleLastUpdate.getValue(isDebug: isDebug)
        ]

        var deletedKeys: [String] = []
        for key in keysToDelete {
            let deleted = try await req.redis.delete([key]).get()
            if deleted > 0 {
                deletedKeys.append(String(key.rawValue))
            }
        }

        // Step 2: Run ScheduleUpdateJob immediately
        let context = QueueContext(
            queueName: .default,
            configuration: .init(),
            application: req.application,
            logger: req.logger,
            on: req.eventLoop
        )

        let job = ScheduleUpdateJob()
        try await job.run(context: context)

        // Step 3: Read back the new schedule to report game counts
        let schedule = try await req.application.redis.get(
            RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug),
            asJSON: LiveScore.self
        )

        var gamesLoaded: [String: Int] = [:]
        gamesLoaded["nba"] = schedule?.nba?.events.count ?? 0
        gamesLoaded["nfl"] = schedule?.nfl?.events.count ?? 0
        gamesLoaded["nhl"] = schedule?.nhl?.events.count ?? 0
        gamesLoaded["mlb"] = schedule?.mlb?.events.count ?? 0
        gamesLoaded["soccer"] = schedule?.soccer?.events.count ?? 0
        gamesLoaded["golf"] = schedule?.golf?.events.count ?? 0
        gamesLoaded["tennis"] = schedule?.tennis?.events.count ?? 0
        gamesLoaded["racing"] = schedule?.racing?.events.count ?? 0

        let totalGames = gamesLoaded.values.reduce(0, +)

        return ForceRefreshResponse(
            success: true,
            message: "Force refresh complete. Loaded \(totalGames) games across all sports.",
            keysCleared: deletedKeys,
            gamesLoaded: gamesLoaded
        )
    }

    struct TriggerJobResponse: Content {
        let success: Bool
        let message: String
        let jobName: String
    }

    func triggerJob(req: Request) async throws -> TriggerJobResponse {
        guard let jobName = req.parameters.get("jobName") else {
            throw Abort(.badRequest, reason: "Job name parameter is required")
        }

        // Manual job triggering
        switch jobName {
        case "ESPNTeamFetchJob":
            // Create a QueueContext to run the job
            let context = QueueContext(
                queueName: .default,
                configuration: .init(),
                application: req.application,
                logger: req.logger,
                on: req.eventLoop
            )

            // Run the job
            let job = ESPNTeamFetchJob()
            try await job.run(context: context)

            return TriggerJobResponse(
                success: true,
                message: "ESPNTeamFetchJob executed successfully. Team logos updated from ESPN.",
                jobName: jobName
            )
        case "ScheduleUpdateJob":
            // Create a QueueContext to run the job
            let context = QueueContext(
                queueName: .default,
                configuration: .init(),
                application: req.application,
                logger: req.logger,
                on: req.eventLoop
            )

            // Run the job
            let job = ScheduleUpdateJob()
            try await job.run(context: context)

            return TriggerJobResponse(
                success: true,
                message: "ScheduleUpdateJob executed successfully. Schedules refreshed.",
                jobName: jobName
            )
        case "ESPNFetchJob":
            let context = QueueContext(
                queueName: .default,
                configuration: .init(),
                application: req.application,
                logger: req.logger,
                on: req.eventLoop
            )

            let job = ESPNFetchJob()
            try await job.run(context: context)

            return TriggerJobResponse(
                success: true,
                message: "ESPNFetchJob executed successfully. Live scores updated with translated team IDs.",
                jobName: jobName
            )
        default:
            return TriggerJobResponse(
                success: false,
                message: "Job '\(jobName)' not recognized. Available jobs: ESPNTeamFetchJob, ScheduleUpdateJob",
                jobName: jobName
            )
        }
    }

    func clearAllCache(req: Request) async throws -> InvalidateResponse {
        // Get all keys and delete them
        let keysResponse = try await req.redis.send(command: "KEYS", with: [.init(from: "*")]).get()

        var deletedCount = 0
        if case .array(let keyArray) = keysResponse {
            for keyData in keyArray {
                if case .bulkString(let buffer) = keyData,
                   let keyString = buffer.map({ String(buffer: $0) }) {
                    let deleted = try await req.redis.delete([RedisKey(keyString)]).get()
                    deletedCount += deleted
                }
            }
        }

        return InvalidateResponse(
            success: true,
            message: "Cleared \(deletedCount) cache keys"
        )
    }

    // MARK: - Live TSDB Endpoint
    // Returns live games from TheSportsDB (which actually has current live data)
    func liveTSDB(req: Request) async throws -> String {
        let isDebug = req.application.environment == .development
        let liveScore = try await req.redis.get(
            RedisEndpoint.SportsDB.latestFullLiveInfo.getValue(isDebug: isDebug),
            asJSON: LiveScore.self
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let resultData = try? encoder.encode(liveScore) else {
            return "{}"
        }
        return String(data: resultData, encoding: .utf8) ?? "{}"
    }

    // MARK: - Live ESPN Endpoint
    // Fetches live games directly from ESPN API (bypasses cache)
    func liveESPN(req: Request) async throws -> String {
        // Fetch scoreboards for all major sports
        var result = LiveScore(nba: nil, mlb: nil, soccer: nil, nfl: nil, nhl: nil, golf: nil, tennis: nil, racing: nil)

        // Fetch NBA scoreboard
        if let nbaScoreboard = try? await Integrator.getESPNScoreboard(for: .nba, req.application.client) {
            result.nba = LiveEvent(events: nbaScoreboard, league: .nba)
        }

        // Fetch NHL scoreboard
        if let nhlScoreboard = try? await Integrator.getESPNScoreboard(for: .nhl, req.application.client) {
            result.nhl = LiveEvent(events: nhlScoreboard, league: .nhl)
        }

        // Fetch MLB scoreboard
        if let mlbScoreboard = try? await Integrator.getESPNScoreboard(for: .mlb, req.application.client) {
            result.mlb = LiveEvent(events: mlbScoreboard, league: .mlb)
        }

        // Fetch NFL scoreboard
        if let nflScoreboard = try? await Integrator.getESPNScoreboard(for: .nfl, req.application.client) {
            result.nfl = LiveEvent(events: nflScoreboard, league: .nfl)
        }

        // Fetch PGA Golf scoreboard
        if let golfScoreboard = try? await Integrator.getESPNScoreboard(for: .pga, req.application.client) {
            result.golf = LiveEvent(events: golfScoreboard, league: .pga)
        }

        // Fetch Tennis scoreboards (ATP + WTA)
        var tennisGames: [Game] = []
        for tennisLeague in Leagues.allCases.filter({ $0.isTennis }) {
            if let scoreboard = try? await Integrator.getESPNScoreboard(for: tennisLeague, req.application.client),
               let liveEvent = LiveEvent(events: scoreboard, league: tennisLeague) {
                tennisGames.append(contentsOf: liveEvent.events)
            }
        }
        if !tennisGames.isEmpty {
            result.tennis = LiveEvent(events: tennisGames)
        }

        // Fetch F1 Racing scoreboard
        if let racingScoreboard = try? await Integrator.getESPNScoreboard(for: .formula1, req.application.client) {
            result.racing = LiveEvent(events: racingScoreboard, league: .formula1)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let resultData = try? encoder.encode(result) else {
            return "{}"
        }
        return String(data: resultData, encoding: .utf8) ?? "{}"
    }
}
