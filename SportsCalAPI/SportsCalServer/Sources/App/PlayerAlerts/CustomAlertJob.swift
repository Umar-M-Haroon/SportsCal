//
//  CustomAlertJob.swift
//  App
//
//  Minutely: Pro custom live alerts. For each live game that has subscribers (found
//  through the team / sport scope sets, see `CustomAlertRegistry`):
//  - player plays: new plays since `CustomAlertState-{event}.lastPlayID` in the
//    server-only `LivePlayers-{event}` feed, matched on their `PlayHighlight`s
//    (soccer: new key events in the cached match centre, by athlete ID);
//  - player milestones: each subscribed player's live number against the one seen
//    last minute, so "reaches 30 points" fires on the way up, once;
//  - game situations: `ClutchMoment`, without needing a Live Activity.
//  The first look at a game only records what's there.
//
//  Each push is claimed per install (`CustomAlertSent-{install}-{rule}-{event}-{key}`,
//  SETNX, 24h) and counted (`CustomAlertCount-{install}-{event}`, at most 15 a game).
//  Plain alert pushes with the `CUSTOM_ALERT` category, threaded by event.
//
//  Redis per tick: two SMEMBERS of the scope lists (nothing more when nobody has a
//  rule); then the live board, one SMEMBERS per subscribed team that's playing, MGETs
//  of the devices, and per subscribed game one state read/write plus the player feed
//  (only when a player rule is on that game). Never a SCAN, never the schedule.
//

import Foundation
import Queues
import Logging
import Crypto
import SportsCalModel

/// What the job saw last time it looked at a game.
struct CustomAlertGameState: Codable, Equatable, Sendable {
    /// The newest feed play accounted for.
    var lastPlayID: String?
    /// Soccer key events accounted for.
    var seenSoccerEventIDs: [String]?
    /// "athleteID|stat" → the value last seen, for the milestones someone follows.
    var stats: [String: Double]
    var homeWinProbability: Double?

    static let ttl: TimeInterval = 12 * 60 * 60

    static func key(eventID: String, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + "CustomAlertState-\(eventID)"
    }
}

/// One push to one install.
struct CustomAlert: Equatable, Sendable {
    var ruleID: String
    /// Unique per rule and game: a play ID, "milestone", or a clutch moment key.
    var key: String
    var title: String
    var body: String
    var type: String
    var athleteID: String?
}

struct CustomAlertJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.custom-alerts")
    static let appID = "com.KomodoLLC.SportsCal"
    static let sendConcurrency = 8
    static let sentTTL: TimeInterval = 24 * 60 * 60

    func run(context: QueueContext) async throws {
        let app = context.application
        guard app.storage[APNSConfiguredKey.self] == true else { return }
        let isDebug = app.environment == .development
        _ = try await JobLock.withLock(
            app.kv, name: "custom-alerts", ttl: 50, instanceID: app.instanceID, logger: Self.logger,
            body: {
                try await Self.runOnce(
                    kv: app.kv, apns: app.apnsSending, entitlements: app.proEntitlements,
                    now: Date(), isDebug: isDebug, logger: Self.logger,
                    soccerMatch: { game in
                        guard let eventID = game.idEvent else { return nil }
                        return await SoccerMatchService.detail(app: app, eventID: eventID, lookup: SoccerAlertJob.lookup(for: game))
                    }
                )
            }
        )
    }

    // MARK: - Devices

    struct Entry: Sendable {
        let key: String
        let device: CustomAlertDevice
        let environment: APNSEnvironment
        /// After the free cap, when Pro has lapsed.
        var rules: [AlertRule]
        var sandbox: Bool { environment == .sandbox }
    }

    /// The sports whose live games can match a rule.
    static let sports: [SportType] = [.basketball, .mlb, .hockey, .soccer, .nfl]

    static func liveGames(_ liveScore: LiveScore?) -> [Game] {
        guard let liveScore else { return [] }
        let buckets: [[Game]?] = [
            liveScore.nba?.events, liveScore.mlb?.events, liveScore.nhl?.events,
            liveScore.soccer?.events, liveScore.nfl?.events,
        ]
        return buckets.compactMap { $0 }.joined().filter { $0.strStatus == "in" && $0.idEvent != nil }
    }

    /// The index scopes a game sits in.
    static func scopes(of game: Game) -> [String] {
        guard let sport = game.sportType, sports.contains(sport) else { return [] }
        var scopes = [game.idHomeTeam, game.idAwayTeam].compactMap { $0 }.filter { !$0.isEmpty }
            .map { CustomAlertIndex.teamScope(sport: sport, teamID: $0) }
        let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
        if let league, league == AlertRule.mainLeague(for: sport) { scopes.append(CustomAlertIndex.sportScope(sport)) }
        return scopes
    }

    /// Whether `rule` is about `game`.
    static func rule(_ rule: AlertRule, matches game: Game) -> Bool {
        guard let sport = game.sportType, rule.sport == sport else { return false }
        let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
        let onTeam = rule.teamID.map { $0 == game.idHomeTeam || $0 == game.idAwayTeam } ?? false
        switch rule.kind {
        case .playerPlay, .playerMilestone:
            return onTeam && AlertRule.isPlayerAlertLeague(league, sport: sport)
        case .gameSituation:
            return rule.teamID == nil ? league == AlertRule.mainLeague(for: sport) : onTeam
        }
    }

    // MARK: - Run

    static func runOnce(
        kv: KeyValueStore,
        apns: APNSSending,
        entitlements: ProEntitlementChecking,
        now: Date,
        isDebug: Bool,
        logger: Logger,
        soccerMatch: (Game) async -> SoccerMatchDetail?
    ) async throws {
        // Nobody has a rule most of the time: answer that before reading the live board.
        var scopesByEnvironment: [(APNSEnvironment, Set<String>)] = []
        for environment in [APNSEnvironment.production, .sandbox] {
            let scopes = await CustomAlertIndex.scopesInUse(sandbox: environment == .sandbox, kv: kv)
            if !scopes.isEmpty { scopesByEnvironment.append((environment, scopes)) }
        }
        guard !scopesByEnvironment.isEmpty else { return }

        let liveKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug).rawValue
        let games = liveGames(try? await kv.getJSON(liveKey, as: LiveScore.self))
        guard !games.isEmpty else { return }

        // Device keys per game, both environments; each scope set read once.
        var deviceKeysByGame: [String: [(key: String, environment: APNSEnvironment)]] = [:]
        var allKeys: [APNSEnvironment: [String: Set<String>]] = [:]   // env → device key → scopes it came from
        for (environment, inUse) in scopesByEnvironment {
            let sandbox = environment == .sandbox
            var members: [String: [String]] = [:]
            for game in games {
                guard let eventID = game.idEvent else { continue }
                for scope in scopes(of: game) where inUse.contains(scope) {
                    if members[scope] == nil {
                        members[scope] = await CustomAlertIndex.devices(in: scope, sandbox: sandbox, kv: kv)
                    }
                    for key in members[scope] ?? [] {
                        allKeys[environment, default: [:]][key, default: []].insert(scope)
                        if !(deviceKeysByGame[eventID] ?? []).contains(where: { $0.key == key }) {
                            deviceKeysByGame[eventID, default: []].append((key, environment))
                        }
                    }
                }
            }
        }
        guard !deviceKeysByGame.isEmpty else { return }

        let entries = await loadDevices(allKeys, kv: kv, entitlements: entitlements, now: now, logger: logger)
        guard !entries.isEmpty else { return }

        for game in games {
            guard let eventID = game.idEvent, let keys = deviceKeysByGame[eventID] else { continue }
            let subscribers: [Entry] = keys.compactMap { entries[$0.key] }.compactMap { entry in
                var entry = entry
                entry.rules = entry.rules.filter { rule($0, matches: game) }
                return entry.rules.isEmpty ? nil : entry
            }
            guard !subscribers.isEmpty else { continue }
            await process(game: game, eventID: eventID, subscribers: subscribers, kv: kv, apns: apns,
                          isDebug: isDebug, logger: logger, soccerMatch: soccerMatch)
        }
    }

    /// MGETs the devices (500 a round trip), drops the expired ones from the scope sets
    /// they were found in, and caps any whose Pro has lapsed.
    static func loadDevices(
        _ keys: [APNSEnvironment: [String: Set<String>]],
        kv: KeyValueStore,
        entitlements: ProEntitlementChecking,
        now: Date,
        logger: Logger
    ) async -> [String: Entry] {
        var entries: [String: Entry] = [:]
        let decoder = JSONDecoder()
        for (environment, scopesByKey) in keys {
            let sandbox = environment == .sandbox
            let all = Array(scopesByKey.keys)
            for start in stride(from: 0, to: all.count, by: 500) {
                let chunk = Array(all[start..<min(start + 500, all.count)])
                let values = (try? await kv.mget(chunk)) ?? Array(repeating: nil, count: chunk.count)
                for (key, value) in zip(chunk, values) {
                    guard let data = value?.data(using: .utf8),
                          let device = try? decoder.decode(CustomAlertDevice.self, from: data) else {
                        await CustomAlertIndex.remove(key, from: scopesByKey[key] ?? [], sandbox: sandbox, kv: kv)
                        continue
                    }
                    var rules = device.rules
                    if device.isPro, now.timeIntervalSince(device.proCheckedAt) > CustomAlertDevice.proRecheckInterval {
                        // RevenueCat answers are cached 6h, so this is at most one lookup per
                        // Pro install per 6h, and only while one of its games is live.
                        let check = await entitlements.check(appUserID: device.revenueCatAppUserID)
                        if !check.isPro {
                            rules = CustomAlertLimits.free.apply(to: rules).accepted
                            logger.info("Custom alerts: Pro not confirmed for install \(device.installID.prefix(8))..., free cap applied")
                        }
                    }
                    entries[key] = Entry(key: key, device: device, environment: environment, rules: rules)
                }
            }
        }
        return entries
    }

    // MARK: - One game

    private static func process(
        game: Game, eventID: String, subscribers: [Entry],
        kv: KeyValueStore, apns: APNSSending, isDebug: Bool, logger: Logger,
        soccerMatch: (Game) async -> SoccerMatchDetail?
    ) async {
        let rules = subscribers.flatMap(\.rules)
        let wantsPlayers = rules.contains { $0.isPlayerRule }
        let stateKey = CustomAlertGameState.key(eventID: eventID, isDebug: isDebug)
        let previous = try? await kv.getJSON(stateKey, as: CustomAlertGameState.self)

        var feed: LivePlayerFeed?
        var soccer: SoccerMatchDetail?
        if wantsPlayers {
            if game.sportType == .soccer {
                soccer = await soccerMatch(game)
            } else {
                let feedKey = RedisEndpoint.ESPN.livePlayers(eventID).getValue(isDebug: isDebug).rawValue
                feed = try? await kv.getJSON(feedKey, as: LivePlayerFeed.self)
            }
        }

        let (alertsByDevice, state) = evaluate(
            game: game, subscribers: subscribers, previous: previous, feed: feed, soccer: soccer
        )
        if state != previous {
            try? await kv.setJSON(stateKey, value: state, ttl: CustomAlertGameState.ttl)
        }
        guard !alertsByDevice.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            for entry in subscribers {
                guard let alerts = alertsByDevice[entry.key], !alerts.isEmpty else { continue }
                if inFlight == sendConcurrency {
                    await group.next()
                    inFlight -= 1
                }
                group.addTask { await deliver(alerts, eventID: eventID, to: entry, kv: kv, apns: apns, logger: logger) }
                inFlight += 1
            }
        }
        let total = alertsByDevice.values.reduce(0) { $0 + $1.count }
        logger.info("Custom alerts for \(game.strAwayTeam) @ \(game.strHomeTeam): \(total) candidate pushes → \(alertsByDevice.count) devices")
    }

    /// Pure: the alerts each device should get for `game` right now, and the state to
    /// remember. Nothing fires on the first look (`previous` nil).
    static func evaluate(
        game: Game,
        subscribers: [Entry],
        previous: CustomAlertGameState?,
        feed: LivePlayerFeed?,
        soccer: SoccerMatchDetail?
    ) -> (alerts: [String: [CustomAlert]], state: CustomAlertGameState) {
        guard let sport = game.sportType else {
            return ([:], previous ?? CustomAlertGameState(stats: [:]))
        }
        let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
        let homeScore = Int(game.intHomeScore ?? "") ?? 0
        let awayScore = Int(game.intAwayScore ?? "") ?? 0
        let margin = abs(homeScore - awayScore)
        let currentPeriod = game.situation?.period
        var scoreLine = "\(game.strAwayTeam) \(awayScore), \(game.strHomeTeam) \(homeScore)"
        if let progress = game.strProgress, !progress.isEmpty { scoreLine += " · \(progress)" }
        let firstLook = previous == nil
        var state = previous ?? CustomAlertGameState(stats: [:])
        var alerts: [String: [CustomAlert]] = [:]
        // One push per device per play and player, however many of its rules match.
        var claimedPlays: [String: Set<String>] = [:]

        func name(_ rule: AlertRule, fallback: String?) -> String {
            rule.athleteName ?? fallback ?? "Your player"
        }

        // Player plays: the new highlights since last look.
        var newHighlights: [(playID: String, highlight: PlayHighlight, name: String?)] = []
        if let feed {
            let plays = feed.plays
            if !firstLook, let last = state.lastPlayID, let index = plays.lastIndex(where: { $0.playID == last }) {
                for play in plays[(index + 1)...] {
                    for highlight in play.highlights ?? [] {
                        let participant = play.participants.first { $0.athleteID == highlight.athleteID }
                        newHighlights.append((play.playID, highlight, participant?.name))
                    }
                }
            }
            // A missing last play (ESPN rewrote the list) skips ahead rather than replaying.
            if let newest = plays.last?.playID { state.lastPlayID = newest }
        }
        if let soccer {
            let seen = Set(state.seenSoccerEventIDs ?? [])
            let hadSeen = state.seenSoccerEventIDs != nil
            for event in soccer.events where hadSeen && !seen.contains(event.id) {
                let names = zip(event.athleteIDs ?? [], event.playerNames)
                for highlight in PlayHighlight.highlights(in: event) {
                    let name = names.first { $0.0 == highlight.athleteID }?.1
                    newHighlights.append((event.id, highlight, name))
                }
            }
            state.seenSoccerEventIDs = soccer.events.map(\.id)
        }

        // Milestones: current numbers for the stats someone follows.
        let lines = Dictionary((feed?.statLines ?? []).map { ($0.athleteID, $0) }, uniquingKeysWith: { first, _ in first })
        var nextStats = state.stats

        // Situation: at most one clutch moment a tick.
        let wantsSituations = subscribers.contains { $0.rules.contains { $0.kind == .gameSituation } }
        var moment: ClutchMoment?
        if wantsSituations, let situation = game.situation, !firstLook {
            let before = state.homeWinProbability.map { GameSituation(homeWinProbability: $0) }
            moment = ClutchMoment.detect(
                sport: sport, league: league, phase: game.resolvedSeasonPhase, situation: situation, previous: before,
                homeScore: homeScore, awayScore: awayScore, homeName: game.strHomeTeam, awayName: game.strAwayTeam
            )
        }
        if let probability = game.situation?.homeWinProbability { state.homeWinProbability = probability }

        for entry in subscribers {
            var mine: [CustomAlert] = []
            for rule in entry.rules {
                switch rule.kind {
                case .playerPlay:
                    let types = Set(rule.playTypes ?? [])
                    for item in newHighlights where item.highlight.athleteID == rule.athleteID && types.contains(item.highlight.type) {
                        guard rule.passesFilters(period: item.highlight.period ?? currentPeriod, margin: margin, league: league),
                              claimedPlays[entry.key, default: []].insert("\(item.playID)|\(item.highlight.athleteID)").inserted
                        else { continue }
                        mine.append(CustomAlert(
                            ruleID: rule.id, key: item.playID,
                            title: "\(name(rule, fallback: item.name)) \(item.highlight.type.phrase(sport: sport))",
                            body: scoreLine, type: CustomAlertNotification.playType, athleteID: rule.athleteID
                        ))
                    }
                case .playerMilestone:
                    guard let athleteID = rule.athleteID, let milestone = rule.milestone,
                          let line = lines[athleteID], let current = milestone.value(in: line.stats) else { continue }
                    let statKey = "\(athleteID)|\(milestone.stat)"
                    let before = state.stats[statKey]
                    nextStats[statKey] = max(current, nextStats[statKey] ?? current)
                    guard !firstLook, milestone.isCrossed(from: before, to: current),
                          rule.passesFilters(period: currentPeriod, margin: margin, league: league) else { continue }
                    let derived = milestone.stat == AlertMilestone.doubleDouble || milestone.stat == AlertMilestone.tripleDouble
                    mine.append(CustomAlert(
                        ruleID: rule.id, key: "milestone",
                        title: "\(name(rule, fallback: line.name)) \(derived ? "records" : "reaches") \(milestone.description(sport: sport))",
                        body: scoreLine, type: CustomAlertNotification.milestoneType, athleteID: athleteID
                    ))
                case .gameSituation:
                    guard let moment, rule.situation == nil || rule.situation == moment.kind,
                          rule.passesFilters(period: currentPeriod, margin: margin, league: league) else { continue }
                    // Several situation rules (a team's and the league's) shouldn't double up.
                    guard !mine.contains(where: { $0.type == CustomAlertNotification.situationType }) else { continue }
                    mine.append(CustomAlert(
                        ruleID: rule.id, key: "situation-\(moment.key)",
                        title: moment.title, body: moment.body, type: CustomAlertNotification.situationType, athleteID: nil
                    ))
                }
            }
            if !mine.isEmpty { alerts[entry.key] = mine }
        }
        state.stats = nextStats
        return (alerts, state)
    }

    // MARK: - Delivery

    static func sentKey(installID: String, ruleID: String, eventID: String, key: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "CustomAlertSent-\(installID)-\(ruleID)-\(eventID)-\(key)"
    }

    static func countKey(installID: String, eventID: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "CustomAlertCount-\(installID)-\(eventID)"
    }

    /// One device's alerts for one game, in order: muted ones skipped, each claimed
    /// once, at most `CustomAlertNotification.maxPerDevicePerGame` a game.
    static func deliver(
        _ alerts: [CustomAlert], eventID: String, to entry: Entry,
        kv: KeyValueStore, apns: APNSSending, logger: Logger
    ) async {
        let sandbox = entry.sandbox
        let device = entry.device
        for alert in alerts {
            var muteKeys = [CustomAlertMute.ruleKey(installID: device.installID, eventID: eventID, ruleID: alert.ruleID, sandbox: sandbox)]
            if let athleteID = alert.athleteID {
                muteKeys.append(CustomAlertMute.athleteKey(installID: device.installID, eventID: eventID, athleteID: athleteID, sandbox: sandbox))
            }
            let mutes = (try? await kv.mget(muteKeys)) ?? []
            if mutes.contains(where: { $0 != nil }) { continue }

            let claim = sentKey(installID: device.installID, ruleID: alert.ruleID, eventID: eventID, key: alert.key, sandbox: sandbox)
            guard (try? await kv.setIfAbsent(claim, value: "1", ttl: sentTTL)) == true else { continue }
            let count = (try? await kv.increment(countKey(installID: device.installID, eventID: eventID, sandbox: sandbox), ttl: sentTTL)) ?? 1
            guard count <= CustomAlertNotification.maxPerDevicePerGame else {
                logger.debug("Custom alerts: install \(device.installID.prefix(8))... at its cap for \(eventID)")
                return
            }
            let options = AlertOptions(
                category: CustomAlertNotification.category, ruleID: alert.ruleID, athleteID: alert.athleteID,
                collapseID: collapseID(for: claim)
            )
            switch await send(alert, eventID: eventID, options: options, to: entry, apns: apns, logger: logger) {
            case .sent, .failed:
                continue
            case .staleToken:
                logger.info("Custom alerts: dropping stale token for install \(device.installID.prefix(8))...")
                _ = try? await kv.delete([entry.key])
                await CustomAlertIndex.remove(entry.key, from: device.scopes, sandbox: sandbox, kv: kv)
                return
            }
        }
    }

    /// 32 hex characters, within APNS's 64-byte collapse ID limit.
    static func collapseID(for claim: String) -> String {
        SHA256.hash(data: Data(claim.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private enum Outcome { case sent, failed, staleToken }

    private static func send(
        _ alert: CustomAlert, eventID: String, options: AlertOptions, to entry: Entry,
        apns: APNSSending, logger: Logger
    ) async -> Outcome {
        // The state has moved past this alert, so it isn't retried next minute; give a
        // transient failure one more go now.
        for attempt in 1...2 {
            do {
                _ = try await sendWithEnvironmentFallback(primary: entry.environment) { environment in
                    try await apns.sendAlert(
                        deviceToken: entry.device.token, appID: appID, title: alert.title, body: alert.body,
                        eventID: eventID, type: alert.type, options: options, environment: environment
                    )
                }
                return .sent
            } catch let error as APNSSendError where error.isStaleToken {
                return .staleToken
            } catch {
                logger.warning("Custom alert send failed for install \(entry.device.installID.prefix(8))... (attempt \(attempt)): \(error)")
                if attempt == 1 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
        return .failed
    }
}
