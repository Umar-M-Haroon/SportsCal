//
//  APNSJob.swift
//
//
//  Created by Umar Haroon on 11/1/22.
//

import Foundation
import Queues
import SportsCalModel
import Logging

struct APNSJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.apns-job")

    func run(context: Queues.QueueContext) async throws {
        let app = context.application
        let isDebug = app.environment == .development
        guard app.storage[APNSConfiguredKey.self] == true else { return }

        try await APNSJob.runOnce(
            kv: app.kv,
            apns: app.apnsSending,
            clock: app.appClock,
            isDebug: isDebug,
            logger: Self.logger,
            metrics: app.pushMetrics
        )
    }

    /// Extracted loop body so tests can exercise it without booting the queue runner.
    /// Keeping the pipeline in a single function keeps the control flow readable.
    /// `metrics` is optional so unit tests can skip metrics wiring when they
    /// only care about behavior.
    static func runOnce(
        kv: KeyValueStore,
        apns: APNSSending,
        clock: AppClock,
        isDebug: Bool,
        logger: Logger,
        metrics: PushMetrics? = nil
    ) async throws {
        // Always iterate BOTH keyspaces regardless of the server's own
        // environment: a single instance must dispatch sandbox tokens (Xcode
        // dev devices) and production tokens (TestFlight / App Store) to their
        // respective APNS gateways. The prefix is the load-bearing signal for
        // which gateway to use.
        let prodKeys = try await kv.scanKeys(matching: "APNS-*")
        let sandboxKeys = try await kv.scanKeys(matching: "debug-APNS-*")
        guard !prodKeys.isEmpty || !sandboxKeys.isEmpty else { return }

        let liveScoreKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug).rawValue
        let liveScore = try await kv.getJSON(liveScoreKey, as: LiveScore.self)

        var events: [Game] = []
        events.append(contentsOf: liveScore?.mlb?.events ?? [])
        events.append(contentsOf: liveScore?.nfl?.events ?? [])
        events.append(contentsOf: liveScore?.nba?.events ?? [])
        events.append(contentsOf: liveScore?.soccer?.events ?? [])
        events.append(contentsOf: liveScore?.nhl?.events ?? [])
        events.append(contentsOf: liveScore?.golf?.events ?? [])
        events.append(contentsOf: liveScore?.tennis?.events ?? [])
        events.append(contentsOf: liveScore?.racing?.events ?? [])

        try await dispatchBatch(
            keys: prodKeys,
            keyPrefix: "APNS-",
            environment: .production,
            events: events,
            kv: kv,
            apns: apns,
            clock: clock,
            isDebug: isDebug,
            logger: logger,
            metrics: metrics
        )
        try await dispatchBatch(
            keys: sandboxKeys,
            keyPrefix: "debug-APNS-",
            environment: .sandbox,
            events: events,
            kv: kv,
            apns: apns,
            clock: clock,
            isDebug: isDebug,
            logger: logger,
            metrics: metrics
        )
    }

    /// Iterate one keyspace and dispatch its tokens through the matching APNS
    /// gateway. Extracted so `runOnce` can run two passes — production and
    /// sandbox — without duplicating the iteration logic.
    private static func dispatchBatch(
        keys: [String],
        keyPrefix: String,
        environment: APNSEnvironment,
        events: [Game],
        kv: KeyValueStore,
        apns: APNSSending,
        clock: AppClock,
        isDebug: Bool,
        logger: Logger,
        metrics: PushMetrics?
    ) async throws {
        guard !keys.isEmpty else { return }
        let registrationValues = try await kv.mget(keys)

        for (index, key) in keys.enumerated() {
            guard let rawValue = registrationValues[index] else { continue }

            let registration = decodeRegistration(from: rawValue)
            guard let event = matchEvent(events: events, registration: registration) else { continue }
            guard let homeScore = Int(event.intHomeScore ?? ""),
                  let awayScore = Int(event.intAwayScore ?? "") else { continue }

            let tokenString = tokenFromKey(key, prefix: keyPrefix)
            let now = Int(clock.now.timeIntervalSince1970)

            if !event.hasDoneStatus {
                let contentState = ContentState(
                    homeScore: homeScore,
                    awayScore: awayScore,
                    status: event.strStatus,
                    progress: event.strProgress,
                    lastPlay: event.lastPlay
                )
                let stateKey = RedisEndpoint.eventState(event.id).getValue(isDebug: isDebug).rawValue
                let savedState = try await kv.getJSON(stateKey, as: ContentState.self)
                guard savedState != contentState else { continue }
                try await kv.setJSON(stateKey, value: contentState, ttl: 60 * 60 * 12)
                do {
                    _ = try await apns.sendLiveActivityUpdate(
                        deviceToken: tokenString,
                        appID: "com.KomodoLLC.SportsCal",
                        contentState: contentState,
                        isFinal: false,
                        timestamp: now,
                        environment: environment
                    )
                    await metrics?.recordSend(kind: .update)
                    // Slide the registration TTL forward so an active activity never
                    // expires mid-game even if the client can't run BGAppRefresh.
                    _ = try? await kv.expire(key, ttl: 60 * 60 * 12)
                } catch let sendError as APNSSendError {
                    logger.error("Failed to send APNS update for \(event.id) [\(environment.rawValue)]: \(sendError.reason.rawValue) \(sendError.underlying ?? "")")
                    await metrics?.recordError(sendError.reason)
                    if sendError.isStaleToken {
                        _ = try await kv.delete([key])
                        await metrics?.recordCleanup(reason: sendError.reason.rawValue)
                    }
                } catch {
                    logger.error("Failed to send APNS update for \(event.id) [\(environment.rawValue)]: \(error)")
                    await metrics?.recordError(.other)
                }
            } else {
                logger.info("Ending live activity for game \(key)")
                let contentState = ContentState(
                    homeScore: homeScore,
                    awayScore: awayScore,
                    status: event.strStatus,
                    progress: event.strProgress,
                    lastPlay: event.lastPlay
                )
                do {
                    _ = try await apns.sendLiveActivityUpdate(
                        deviceToken: tokenString,
                        appID: "com.KomodoLLC.SportsCal",
                        contentState: contentState,
                        isFinal: true,
                        timestamp: now,
                        environment: environment
                    )
                    await metrics?.recordSend(kind: .end)
                } catch let sendError as APNSSendError {
                    logger.error("Failed to send APNS end for \(event.id) [\(environment.rawValue)]: \(sendError.reason.rawValue) \(sendError.underlying ?? "")")
                    await metrics?.recordError(sendError.reason)
                } catch {
                    logger.error("Failed to send APNS end for \(event.id) [\(environment.rawValue)]: \(error)")
                    await metrics?.recordError(.other)
                }
                let stateKey = RedisEndpoint.eventState(event.id).getValue(isDebug: isDebug).rawValue
                _ = try await kv.delete([key, stateKey])
            }
        }
    }

    // MARK: - Helpers (internal for unit tests)

    /// Parses the Redis value into a registration. Supports both the JSON shape
    /// (new) and a legacy plain-eventID string that pre-dates the JSON migration.
    static func decodeRegistration(from rawValue: String) -> APNSRegistration {
        if let data = rawValue.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(APNSRegistration.self, from: data) {
            return parsed
        }
        return APNSRegistration(eventID: rawValue, homeTeam: nil, awayTeam: nil)
    }

    /// Match an event from the live scoreboard. Tries eventID first, then falls
    /// back to case-insensitive team-name match. Kept pure for unit-testability.
    static func matchEvent(events: [Game], registration: APNSRegistration) -> Game? {
        if let found = events.first(where: { $0.idEvent == registration.eventID }) {
            return found
        }
        if let home = registration.homeTeam, let away = registration.awayTeam {
            let homeLower = home.lowercased()
            let awayLower = away.lowercased()
            return events.first(where: {
                $0.strHomeTeam.lowercased() == homeLower && $0.strAwayTeam.lowercased() == awayLower
            })
        }
        return nil
    }

    /// `APNS-abc123` → `abc123`; `debug-APNS-abc123` → `abc123`. The token itself
    /// contains only hex digits so there's never a stray `-` inside to worry about.
    static func tokenFromKey(_ key: String, prefix: String) -> String {
        if key.hasPrefix(prefix) {
            return String(key.dropFirst(prefix.count))
        }
        return key
    }
}
