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

        // Leader-election: minutely tick; ttl 50s gives a 10s safety margin
        // before the next tick. Multi-replica deploys: only one wins per tick.
        _ = try await JobLock.withLock(
            app.kv,
            name: "apns-job",
            ttl: 50,
            instanceID: app.instanceID,
            logger: Self.logger,
            body: {
                try await APNSJob.runOnce(
                    kv: app.kv,
                    apns: app.apnsSending,
                    clock: app.appClock,
                    isDebug: isDebug,
                    logger: Self.logger,
                    metrics: app.pushMetrics
                )
            }
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
        let runStart = clock.now
        // Always iterate BOTH keyspaces regardless of the server's own
        // environment: a single instance must dispatch sandbox tokens (Xcode
        // dev devices) and production tokens (TestFlight / App Store) to their
        // respective APNS gateways. The prefix is the load-bearing signal for
        // which gateway to use.
        let prodKeys = try await kv.scanKeys(matching: "APNS-*")
        let sandboxKeys = try await kv.scanKeys(matching: "debug-APNS-*")
        await metrics?.recordScanSize(prod: prodKeys.count, sandbox: sandboxKeys.count)
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
        await metrics?.recordDuration(clock.now.timeIntervalSince(runStart))
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
        // Bound the MGET argument count (a single 10k-arg MGET is a latency spike)
        // by chunking, collecting the present registrations.
        var pending: [(key: String, raw: String)] = []
        for chunk in keys.chunked(into: 500) {
            let values = try await kv.mget(chunk)
            for (offset, key) in chunk.enumerated() {
                if let raw = values[offset] { pending.append((key: key, raw: raw)) }
            }
        }

        // Process with bounded concurrency (~8 simultaneous APNS sends) instead of
        // fully serially. The atomic per-(token, event, state) claim inside
        // processRegistration keeps concurrent tasks from sending duplicates.
        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = 8
            var iterator = pending.makeIterator()
            func addNext() {
                guard let item = iterator.next() else { return }
                group.addTask {
                    await processRegistration(
                        key: item.key,
                        rawValue: item.raw,
                        events: events,
                        keyPrefix: keyPrefix,
                        environment: environment,
                        kv: kv,
                        apns: apns,
                        clock: clock,
                        isDebug: isDebug,
                        logger: logger,
                        metrics: metrics
                    )
                }
            }
            for _ in 0..<Swift.min(maxConcurrent, pending.count) { addNext() }
            while await group.next() != nil { addNext() }
        }
    }

    /// Processes a single registration: match → claim → send → cleanup. Extracted
    /// from `dispatchBatch` so a bounded TaskGroup can run many in parallel.
    /// Non-throwing and self-contained: a Redis hiccup on one registration is
    /// logged/skipped rather than aborting the whole batch.
    private static func processRegistration(
        key: String,
        rawValue: String,
        events: [Game],
        keyPrefix: String,
        environment: APNSEnvironment,
        kv: KeyValueStore,
        apns: APNSSending,
        clock: AppClock,
        isDebug: Bool,
        logger: Logger,
        metrics: PushMetrics?
    ) async {
        let registration = decodeRegistration(from: rawValue)
        guard let event = matchEvent(events: events, registration: registration) else { return }
        guard let homeScore = Int(event.intHomeScore ?? ""),
              let awayScore = Int(event.intAwayScore ?? "") else { return }

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
            let savedState = try? await kv.getJSON(stateKey, as: ContentState.self)
            guard savedState != contentState else { return }
            // Atomic per-(token, eventID, contentState) claim: only one server
            // instance — across all replicas — wins permission to send this exact
            // update. The stateKey cache write moves below the claim so a lost-claim
            // caller doesn't trample it.
            let stateHash = contentState.stableHash()
            let claimKey = RedisEndpoint.eventStateClaim(event.id + "-" + tokenString, stateHash).getValue(isDebug: isDebug).rawValue
            let claimed = (try? await kv.setIfAbsent(claimKey, value: "1", ttl: 60 * 60 * 12)) ?? false
            guard claimed else {
                await metrics?.recordDedup(hit: true)
                logger.info("Lost update claim for \(event.id) → \(tokenString.prefix(8))... — skipping")
                return
            }
            await metrics?.recordDedup(hit: false)
            try? await kv.setJSON(stateKey, value: contentState, ttl: 60 * 60 * 12)
            // If the score went up versus the last state we pushed, send an
            // *alerting* update so the device vibrates / banners on the lock
            // screen. Clock ticks and status changes stay silent.
            let goalAlert = scoreAlert(event: event, homeScore: homeScore, awayScore: awayScore, previous: savedState)
            do {
                _ = try await apns.sendLiveActivityUpdate(
                    deviceToken: tokenString,
                    appID: "com.KomodoLLC.SportsCal",
                    contentState: contentState,
                    isFinal: false,
                    alert: goalAlert,
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
                    _ = try? await kv.delete([key])
                    await metrics?.recordCleanup(reason: sendError.reason.rawValue)
                } else {
                    // Release the claim so the next tick can retry — otherwise a
                    // single transient error would silence updates for 12h.
                    _ = try? await kv.delete([claimKey])
                }
            } catch {
                logger.error("Failed to send APNS update for \(event.id) [\(environment.rawValue)]: \(error)")
                await metrics?.recordError(.other)
                _ = try? await kv.delete([claimKey])
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
                    alert: nil,
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
            _ = try? await kv.delete([key, stateKey])
        }
    }

    // MARK: - Helpers (internal for unit tests)

    /// Builds an alert for an *alerting* Live Activity update when a team's score
    /// has increased since the last state we pushed — i.e. a goal / score just
    /// happened. Returns nil when there's no prior state (don't alert on the first
    /// push after a follow/restart) or when neither score went up (clock ticks,
    /// status flips, or a score correction downward).
    static func scoreAlert(
        event: Game,
        homeScore: Int,
        awayScore: Int,
        previous: ContentState?
    ) -> LiveActivityAlert? {
        guard let previous else { return nil }
        // Only low-frequency, high-value sports alert — basketball/baseball and
        // the individual sports stay silent. Shared rule lives on SportType.
        guard event.sportType?.alertsOnScoreChange == true else { return nil }
        let homeScored = homeScore > previous.homeScore
        let awayScored = awayScore > previous.awayScore
        guard homeScored || awayScored else { return nil }

        let title: String
        switch event.sportType {
        case .soccer: title = "⚽️ Goal!"
        case .hockey: title = "🏒 Goal!"
        default: title = "Score!"
        }
        let body = "\(event.strHomeTeam) \(homeScore) – \(awayScore) \(event.strAwayTeam)"
        return LiveActivityAlert(title: title, body: body)
    }

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
