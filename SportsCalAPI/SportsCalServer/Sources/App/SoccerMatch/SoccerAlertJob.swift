//
//  SoccerAlertJob.swift
//  SportsCalServer
//
//  Minutely: for every soccer match a registered device follows (by team name),
//  read the match centre, ask `SoccerAlertDetector` what's new since last minute,
//  and push each new alert to the devices that follow either side and want that
//  kind. Plain alert pushes, so they arrive without a Live Activity running.
//
//  Matches are watched from 75 minutes before kickoff (lineups land about an hour
//  out) until the full-time alert has gone. Each device gets each alert at most
//  once (a per-install claim), and goals are left to a running Live Activity for
//  that match, which already announces them.
//

import Foundation
import Queues
import Logging
import SportsCalModel

/// A device's soccer alert registration, stored per install.
struct SoccerAlertDevice: Codable, Equatable, Sendable {
    var installID: String
    var token: String
    var teams: [String]
    var kinds: [SoccerAlertKind]

    static let ttl: TimeInterval = 30 * 24 * 60 * 60

    static func key(installID: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "SoccerAlertDevice-\(installID)"
    }
}

/// A Redis set of the `SoccerAlertDevice` keys in one environment, so the minutely
/// job reads its devices without a SCAN (the pattern `APNSRegistrationIndex` moved
/// the Live Activity job off). The register routes are the only writers; members
/// whose registration expired are dropped when the job finds them gone.
enum SoccerAlertDeviceIndex {
    static func key(sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "SoccerAlertDeviceIndex"
    }

    static func add(_ deviceKey: String, sandbox: Bool, kv: KeyValueStore) async {
        guard let sets = kv as? RedisSetStore else { return }
        try? await sets.setAdd(key(sandbox: sandbox), members: [deviceKey])
    }

    static func remove(_ deviceKeys: [String], sandbox: Bool, kv: KeyValueStore) async {
        guard !deviceKeys.isEmpty, let sets = kv as? RedisSetStore else { return }
        try? await sets.setRemove(key(sandbox: sandbox), members: deviceKeys)
    }

    /// Falls back to a SCAN on a store without sets (some test fakes).
    static func members(sandbox: Bool, kv: KeyValueStore) async -> [String] {
        guard let sets = kv as? RedisSetStore else {
            return (try? await kv.scanKeys(matching: SoccerAlertDevice.key(installID: "*", sandbox: sandbox))) ?? []
        }
        return (try? await sets.setMembers(key(sandbox: sandbox))) ?? []
    }
}

/// Set by `POST /liveActivity` when the app says which install it is: this install
/// has a Live Activity running for this game, which announces goals itself.
enum LiveActivityInstallMarker {
    static func key(installID: String, eventID: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "LiveActivityInstall-\(installID)-\(eventID)"
    }
}

struct SoccerAlertJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.soccer-alerts")
    static let appID = "com.KomodoLLC.SportsCal"

    func run(context: QueueContext) async throws {
        let app = context.application
        guard app.storage[APNSConfiguredKey.self] == true else { return }
        let isDebug = app.environment == .development
        _ = try await JobLock.withLock(
            app.kv, name: "soccer-alerts", ttl: 50, instanceID: app.instanceID, logger: Self.logger,
            body: {
                try await Self.runOnce(
                    kv: app.kv, apns: app.apnsSending, now: Date(), isDebug: isDebug, logger: Self.logger,
                    match: { game in
                        guard let eventID = game.idEvent else { return nil }
                        return await SoccerMatchService.detail(app: app, eventID: eventID, lookup: Self.lookup(for: game))
                    }
                )
            }
        )
    }

    /// One pass. `match` reads a game's match centre (injected so tests can stub ESPN).
    static func runOnce(
        kv: KeyValueStore,
        apns: APNSSending,
        now: Date,
        isDebug: Bool,
        logger: Logger,
        match: (Game) async -> SoccerMatchDetail?
    ) async throws {
        // Most minutes of the week no soccer is on: check that before touching devices.
        let liveKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug).rawValue
        let liveScore = try? await kv.getJSON(liveKey, as: LiveScore.self)
        let watchable = (liveScore?.soccer?.events ?? []).filter { isWatchable($0, now: now) }
        guard !watchable.isEmpty else { return }

        let devices = await loadDevices(kv: kv)
        guard !devices.isEmpty else { return }
        let followed = Set(devices.flatMap { $0.device.teams })
        let games = watchable.filter { followed.contains($0.strHomeTeam) || followed.contains($0.strAwayTeam) }

        for game in games {
            guard let eventID = game.idEvent else { continue }
            let stateKey = (isDebug ? "debug-" : "") + "SoccerAlertState-\(eventID)"
            let previous = try? await kv.getJSON(stateKey, as: SoccerAlertState.self)
            // Nothing left to say before kickoff once lineups are out, or after full time.
            if let previous, previous.fullTimeAnnounced { continue }
            // (By kickoff time, not status: TheSportsDB-sourced games say "NS", ESPN's "pre".)
            if let previous, previous.lineupsAnnounced, game.strStatus != "in",
               let kickoff = game.isoDate, kickoff > now { continue }

            guard let detail = await match(game) else { continue }
            let (alerts, state) = SoccerAlertDetector.detect(detail, previous: previous)
            try? await kv.setJSON(stateKey, value: state, ttl: 12 * 60 * 60)

            for alert in alerts {
                let recipients = devices.filter { entry in
                    entry.device.kinds.contains(alert.kind)
                        && (entry.device.teams.contains(game.strHomeTeam) || entry.device.teams.contains(game.strAwayTeam))
                }
                // A goal for a big club can fan out wide; bound it like APNSJob does.
                await withTaskGroup(of: Void.self) { group in
                    var inFlight = 0
                    for entry in recipients {
                        if inFlight == sendConcurrency {
                            await group.next()
                            inFlight -= 1
                        }
                        group.addTask { await deliver(alert, eventID: eventID, to: entry, kv: kv, apns: apns, logger: logger) }
                        inFlight += 1
                    }
                }
                logger.info("Soccer alert \(alert.kind.rawValue) for \(game.strHomeTeam) v \(game.strAwayTeam) → \(recipients.count) devices")
            }
        }
    }

    /// From 75 minutes before kickoff (lineups) to four hours after it (full time,
    /// with room for extra time and a delayed start).
    static func isWatchable(_ game: Game, now: Date) -> Bool {
        if game.strStatus == "in" { return true }
        guard let kickoff = game.isoDate else { return false }
        return kickoff.timeIntervalSince(now) <= 75 * 60 && now.timeIntervalSince(kickoff) <= 4 * 60 * 60
    }

    static func lookup(for game: Game) -> SoccerMatchService.Lookup {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = game.isoDate.map { date -> Int in
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
        }
        let league = game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
        return .init(leagueSlug: league?.espnSlug, day: day, homeName: game.strHomeTeam, awayName: game.strAwayTeam)
    }

    // MARK: Devices

    static let sendConcurrency = 8

    struct Entry: Sendable {
        let key: String
        let device: SoccerAlertDevice
        let environment: APNSEnvironment
    }

    /// Both keyspaces, whatever this server's own environment: sandbox tokens
    /// (Xcode builds) and production tokens go to their own APNS gateways. Read in
    /// MGET chunks rather than a GET per device.
    static func loadDevices(kv: KeyValueStore) async -> [Entry] {
        var entries: [Entry] = []
        let decoder = JSONDecoder()
        for environment in [APNSEnvironment.production, .sandbox] {
            let sandbox = environment == .sandbox
            let keys = await SoccerAlertDeviceIndex.members(sandbox: sandbox, kv: kv)
            var expired: [String] = []
            for start in stride(from: 0, to: keys.count, by: 500) {
                let chunk = Array(keys[start..<min(start + 500, keys.count)])
                let values = (try? await kv.mget(chunk)) ?? Array(repeating: nil, count: chunk.count)
                for (key, value) in zip(chunk, values) {
                    guard let data = value?.data(using: .utf8),
                          let device = try? decoder.decode(SoccerAlertDevice.self, from: data) else {
                        expired.append(key)
                        continue
                    }
                    entries.append(Entry(key: key, device: device, environment: environment))
                }
            }
            await SoccerAlertDeviceIndex.remove(expired, sandbox: sandbox, kv: kv)
        }
        return entries
    }

    private static func deliver(
        _ alert: SoccerAlert, eventID: String, to entry: Entry,
        kv: KeyValueStore, apns: APNSSending, logger: Logger
    ) async {
        let sandbox = entry.environment == .sandbox
        let device = entry.device
        if alert.kind == .goal {
            let marker = LiveActivityInstallMarker.key(installID: device.installID, eventID: eventID, sandbox: sandbox)
            if (try? await kv.exists(marker)) == true { return }
        }
        let claim = (sandbox ? "debug-" : "") + "SoccerAlertSent-\(device.installID)-\(alert.id)"
        guard (try? await kv.setIfAbsent(claim, value: "1", ttl: 24 * 60 * 60)) == true else { return }

        let send = {
            _ = try await sendWithEnvironmentFallback(primary: entry.environment) { environment in
                try await apns.sendAlert(
                    deviceToken: device.token, appID: appID, title: alert.title, body: alert.body,
                    eventID: eventID, type: "soccer_\(alert.kind.rawValue)", environment: environment
                )
            }
        }
        // The detector has already moved past this alert, so a failed send isn't
        // retried next minute; give a transient failure one more go now.
        for attempt in 1...2 {
            do {
                try await send()
                return
            } catch let error as APNSSendError where error.isStaleToken {
                logger.info("Soccer alerts: dropping stale token for install \(device.installID.prefix(8))...")
                _ = try? await kv.delete([entry.key])
                await SoccerAlertDeviceIndex.remove([entry.key], sandbox: sandbox, kv: kv)
                return
            } catch {
                logger.warning("Soccer alert send failed for install \(device.installID.prefix(8))... (attempt \(attempt)): \(error)")
                if attempt == 1 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
    }
}
