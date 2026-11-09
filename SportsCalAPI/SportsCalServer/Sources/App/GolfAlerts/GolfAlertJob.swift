//
//  GolfAlertJob.swift
//  SportsCalServer
//
//  Minutely: for every live golf tournament with a followed player in the field, read
//  the whole field, ask `GolfAlertDetector` what's new since last minute (teeing off,
//  taking the lead, finishing a round, winning), and push each alert to the devices that
//  follow that player and want that kind. Plain alert pushes, like `SoccerAlertJob`.
//
//  The live feed carries the top `LiveEvent.golfFieldLimit` of each board, so the field
//  comes from `GolfTournamentDetail` (cached a minute, shared with the app's tournament
//  page). Players are matched by name, as the leaderboard spells them.
//

import Foundation
import Queues
import Logging
import SportsCalModel

/// A device's golf alert registration, stored per install.
struct GolfAlertDevice: Codable, Equatable, Sendable {
    var installID: String
    var token: String
    var players: [String]
    var kinds: [GolfAlertKind]

    static let ttl: TimeInterval = 30 * 24 * 60 * 60

    static func key(installID: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "GolfAlertDevice-\(installID)"
    }
}

/// A Redis set of the `GolfAlertDevice` keys in one environment (see
/// `SoccerAlertDeviceIndex`, which this mirrors).
enum GolfAlertDeviceIndex {
    static func key(sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "GolfAlertDeviceIndex"
    }

    static func add(_ deviceKey: String, sandbox: Bool, kv: KeyValueStore) async {
        guard let sets = kv as? RedisSetStore else { return }
        try? await sets.setAdd(key(sandbox: sandbox), members: [deviceKey])
    }

    static func remove(_ deviceKeys: [String], sandbox: Bool, kv: KeyValueStore) async {
        guard !deviceKeys.isEmpty, let sets = kv as? RedisSetStore else { return }
        try? await sets.setRemove(key(sandbox: sandbox), members: deviceKeys)
    }

    static func members(sandbox: Bool, kv: KeyValueStore) async -> [String] {
        guard let sets = kv as? RedisSetStore else {
            return (try? await kv.scanKeys(matching: GolfAlertDevice.key(installID: "*", sandbox: sandbox))) ?? []
        }
        return (try? await sets.setMembers(key(sandbox: sandbox))) ?? []
    }
}

struct GolfAlertJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.golf-alerts")
    static let appID = SoccerAlertJob.appID

    func run(context: QueueContext) async throws {
        let app = context.application
        guard app.storage[APNSConfiguredKey.self] == true else { return }
        let isDebug = app.environment == .development
        _ = try await JobLock.withLock(
            app.kv, name: "golf-alerts", ttl: 50, instanceID: app.instanceID, logger: Self.logger,
            body: {
                try await Self.runOnce(
                    kv: app.kv, apns: app.apnsSending, isDebug: isDebug, logger: Self.logger,
                    field: { game in
                        guard let league = game.golfTour, let eventID = game.idEvent else { return nil }
                        return try? await GolfTournamentDetail.game(league: league, eventID: eventID, app: app)
                    }
                )
            }
        )
    }

    /// One pass. `field` reads a tournament's whole field (injected so tests can stub ESPN).
    static func runOnce(
        kv: KeyValueStore,
        apns: APNSSending,
        isDebug: Bool,
        logger: Logger,
        field: (Game) async -> Game?
    ) async throws {
        // Most minutes of the week no golf is on: check that before touching devices.
        let liveKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug).rawValue
        let liveScore = try? await kv.getJSON(liveKey, as: LiveScore.self)
        let tournaments = (liveScore?.golf?.events ?? []).filter { $0.strStatus == "in" || $0.strStatus == "post" }
        guard !tournaments.isEmpty else { return }

        let devices = await loadDevices(kv: kv)
        guard !devices.isEmpty else { return }
        let followed = Set(devices.flatMap { $0.device.players })

        for tournament in tournaments {
            guard let eventID = tournament.idEvent else { continue }
            let stateKey = (isDebug ? "debug-" : "") + "GolfAlertState-\(eventID)"
            let previous = try? await kv.getJSON(stateKey, as: GolfAlertState.self)
            // A finished tournament has nothing left to say once its winner has gone out
            // (or it was already over when first seen).
            if tournament.strStatus == "post", previous == nil || previous?.winnerAnnounced == true { continue }

            // The live board may hold every followed player already; only then skip the fetch.
            let board = Set(tournament.resolvedLeaderboard.map(\.name))
            let truncated = board.count >= LiveEvent.golfFieldLimit
            let whole = truncated && !followed.isSubset(of: board) ? await field(tournament) ?? tournament : tournament
            let players = followed.intersection(whole.resolvedLeaderboard.map(\.name))
            guard !players.isEmpty || previous != nil else { continue }

            let (alerts, state) = GolfAlertDetector.detect(whole, players: players, previous: previous)
            try? await kv.setJSON(stateKey, value: state, ttl: 5 * 24 * 60 * 60)

            for alert in alerts {
                let recipients = devices.filter { entry in
                    entry.device.kinds.contains(alert.kind) && entry.device.players.contains(alert.player)
                }
                await withTaskGroup(of: Void.self) { group in
                    var inFlight = 0
                    for entry in recipients {
                        if inFlight == SoccerAlertJob.sendConcurrency {
                            await group.next()
                            inFlight -= 1
                        }
                        group.addTask { await deliver(alert, eventID: eventID, to: entry, kv: kv, apns: apns, logger: logger) }
                        inFlight += 1
                    }
                }
                logger.info("Golf alert \(alert.kind.rawValue) for \(alert.player) → \(recipients.count) devices")
            }
        }
    }

    // MARK: Devices

    struct Entry: Sendable {
        let key: String
        let device: GolfAlertDevice
        let environment: APNSEnvironment
    }

    /// Both keyspaces, whatever this server's own environment (as `SoccerAlertJob`).
    static func loadDevices(kv: KeyValueStore) async -> [Entry] {
        var entries: [Entry] = []
        let decoder = JSONDecoder()
        for environment in [APNSEnvironment.production, .sandbox] {
            let sandbox = environment == .sandbox
            let keys = await GolfAlertDeviceIndex.members(sandbox: sandbox, kv: kv)
            var expired: [String] = []
            for start in stride(from: 0, to: keys.count, by: 500) {
                let chunk = Array(keys[start..<min(start + 500, keys.count)])
                let values = (try? await kv.mget(chunk)) ?? Array(repeating: nil, count: chunk.count)
                for (key, value) in zip(chunk, values) {
                    guard let data = value?.data(using: .utf8),
                          let device = try? decoder.decode(GolfAlertDevice.self, from: data) else {
                        expired.append(key)
                        continue
                    }
                    entries.append(Entry(key: key, device: device, environment: environment))
                }
            }
            await GolfAlertDeviceIndex.remove(expired, sandbox: sandbox, kv: kv)
        }
        return entries
    }

    private static func deliver(
        _ alert: GolfAlert, eventID: String, to entry: Entry,
        kv: KeyValueStore, apns: APNSSending, logger: Logger
    ) async {
        let sandbox = entry.environment == .sandbox
        let device = entry.device
        let claim = (sandbox ? "debug-" : "") + "GolfAlertSent-\(device.installID)-\(alert.id)"
        guard (try? await kv.setIfAbsent(claim, value: "1", ttl: 24 * 60 * 60)) == true else { return }

        let send = {
            _ = try await sendWithEnvironmentFallback(primary: entry.environment) { environment in
                try await apns.sendAlert(
                    deviceToken: device.token, appID: appID, title: alert.title, body: alert.body,
                    eventID: eventID, type: "golf_\(alert.kind.rawValue)", environment: environment
                )
            }
        }
        for attempt in 1...2 {
            do {
                try await send()
                return
            } catch let error as APNSSendError where error.isStaleToken {
                logger.info("Golf alerts: dropping stale token for install \(device.installID.prefix(8))...")
                _ = try? await kv.delete([entry.key])
                await GolfAlertDeviceIndex.remove([entry.key], sandbox: sandbox, kv: kv)
                return
            } catch {
                logger.warning("Golf alert send failed for install \(device.installID.prefix(8))... (attempt \(attempt)): \(error)")
                if attempt == 1 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
    }
}
