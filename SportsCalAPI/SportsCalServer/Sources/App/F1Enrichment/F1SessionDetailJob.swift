//
//  F1SessionDetailJob.swift
//  SportsCalServer
//

import Foundation
import Queues
import Vapor
import SportsCalModel
import Logging

/// Backfills post-session race stories (`F1SessionDetail`) for every finished Race and
/// Sprint of the season, one Redis key per session. Finished sessions never change, so
/// each is fetched once. OpenF1's free tier allows 30 req/min and a session costs 7,
/// so each run takes at most `perRun` sessions; a full season backfills in a few hours.
///
/// `GET /f1/session` only ever reads what this job wrote: user traffic never reaches OpenF1.
struct F1SessionDetailJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.f1-session-detail")
    static let perRun = 2
    /// OpenF1 publishes finished-session data shortly after the flag; give it time to settle.
    static let settleDelay: TimeInterval = 45 * 60

    struct IndexEntry: Codable {
        let sessionKey: Int
        let sessionName: String
        let dateStart: String
    }

    static func indexKey(isDebug: Bool) -> String {
        isDebug ? "debug-F1 Session Index" : "F1 Session Index"
    }

    static func detailKey(_ sessionKey: Int, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + "F1 Session Detail \(sessionKey)"
    }

    /// Set when a fetch comes back empty (e.g. a cancelled session OpenF1 has no laps
    /// for), so newest-first retries don't spend every run's slots on it and starve
    /// the backlog. Expires so a slow-to-publish session still gets retried.
    static func missKey(_ sessionKey: Int, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + "F1 Session Detail Miss \(sessionKey)"
    }
    static let missRetryAfter: TimeInterval = 6 * 3600

    func run(context: QueueContext) async throws {
        let app = context.application
        let isDebug = app.environment == .development
        let year = Calendar.current.component(.year, from: Date())
        let now = Date()

        let sessions = await OpenF1Networking.getRaceSessions(client: app.client, year: year)
        let finished = sessions.filter { session in
            guard let end = session.date_end.flatMap(DateParsers.parse) else { return false }
            return end.addingTimeInterval(Self.settleDelay) < now
        }

        var stored: [IndexEntry] = []
        var fetchedThisRun = 0
        // Newest first: the race people just watched matters more than the backlog.
        for session in finished {
            let key = Self.detailKey(session.session_key, isDebug: isDebug)
            var have = (try? await app.kv.exists(key)) ?? false
            let missKey = Self.missKey(session.session_key, isDebug: isDebug)
            var recentlyMissed = false
            if !have { recentlyMissed = (try? await app.kv.exists(missKey)) ?? false }
            if !have, !recentlyMissed, fetchedThisRun < Self.perRun {
                if fetchedThisRun > 0 { try? await Task.sleep(nanoseconds: 20_000_000_000) }
                fetchedThisRun += 1
                if let detail = await OpenF1Networking.getSessionDetail(client: app.client, session: session) {
                    try await app.kv.setJSON(key, value: detail, ttl: nil)
                    have = true
                    Self.logger.info("F1 session detail stored", metadata: [
                        "sessionKey": "\(session.session_key)", "name": "\(session.session_name ?? "")",
                        "laps": "\(detail.totalLaps)", "drivers": "\(detail.lapPositions.count)"
                    ])
                } else {
                    try? await app.kv.setString(missKey, value: "1", ttl: Self.missRetryAfter)
                }
            }
            if have, let start = session.date_start {
                stored.append(IndexEntry(sessionKey: session.session_key, sessionName: session.session_name ?? "Race", dateStart: start))
            }
        }

        if !stored.isEmpty {
            try await app.kv.setJSON(Self.indexKey(isDebug: isDebug), value: stored, ttl: nil)
        }
        Self.logger.info("F1 session detail run", metadata: [
            "finished": "\(finished.count)", "stored": "\(stored.count)", "fetched": "\(fetchedThisRun)"
        ])
    }

    /// Detail for the session starting within 3h of `start` (ESPN's session start; the two
    /// feeds can disagree by minutes). Matching on time, not name, keeps the 2026
    /// "Bahrain Grand Prix" at Sakhir and the one in Kuala Lumpur apart.
    static func detail(startingNear start: Date, kv: KeyValueStore, isDebug: Bool) async throws -> F1SessionDetail? {
        guard let index = try await kv.getJSON(indexKey(isDebug: isDebug), as: [IndexEntry].self) else { return nil }
        let match = index
            .compactMap { entry in DateParsers.parse(entry.dateStart).map { (entry, abs($0.timeIntervalSince(start))) } }
            .filter { $0.1 <= 3 * 3600 }
            .min { $0.1 < $1.1 }?.0
        guard let match else { return nil }
        return try await kv.getJSON(detailKey(match.sessionKey, isDebug: isDebug), as: F1SessionDetail.self)
    }
}
