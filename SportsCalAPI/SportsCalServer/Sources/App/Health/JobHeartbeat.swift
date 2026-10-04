//
//  JobHeartbeat.swift
//
//  Per-job "last successful run" timestamps, written by each background job and
//  read by `GET /health` and the admin jobs view.
//

import Foundation
import Vapor

/// Records when each background job last completed successfully, so staleness is
/// observable from outside the process (`/health`, admin dashboard).
///
/// Keys: `job:last-success:<raw>` (prefixed `debug-` in development, matching the
/// `RedisEndpoint` convention). Value: seconds since 1970 as a decimal string.
/// Writes are best-effort: a Redis failure never fails the calling job. Goes through
/// `app.kv` (Redis in production, in-memory in tests).
enum JobHeartbeat {
    enum Job: String, CaseIterable, Sendable {
        case scheduleUpdate
        case espnFetch
        case espnSoccer
        case liveTicker
        case espnScheduleWindow
        case injuries
        case f1Enrichment
        case golfEnrichment
        case worldCupEnrichment
        case apns

        /// Staleness threshold. Each value is a few multiples of the job's real
        /// cadence (see `configure.swift` and each job's internal freshness gate), so
        /// a single missed tick does not flip `/health` to 503 but a wedged job does.
        /// They hold whether a job records on every completed run or only when it
        /// actually refreshes data.
        var maxAge: TimeInterval {
            switch self {
            case .scheduleUpdate:
                // Minutely at :30, but the TSDB refresh is gated to >1h since the last.
                return 3 * 3600
            case .espnFetch, .espnSoccer, .apns:
                // Minutely.
                return 10 * 60
            case .liveTicker:
                // 15s while games are live, 60s idle; longer only during an ESPN cooldown.
                return 10 * 60
            case .espnScheduleWindow:
                // Minutely tick, internally gated to ~every 15 min.
                return 45 * 60
            case .injuries:
                // Hourly at :42, refreshed when >4h old → at most ~5h between refreshes.
                return 7 * 3600
            case .f1Enrichment:
                // Hourly at :10, refreshed when >6h old → at most ~7h between refreshes.
                return 9 * 3600
            case .golfEnrichment:
                // Hourly at :25, refreshed when >25min old → effectively hourly.
                return 3 * 3600
            case .worldCupEnrichment:
                // Hourly at :50, refreshed when >30min old → effectively hourly.
                return 3 * 3600
            }
        }

        /// Human-readable cadence for the admin dashboard.
        var scheduleDescription: String {
            switch self {
            case .scheduleUpdate: return "Every minute at :30s (TSDB refresh when >1h old)"
            case .espnFetch: return "Every minute at :15s"
            case .espnSoccer: return "Every minute at :07s"
            case .liveTicker: return "Continuous loop: 15s while live, 60s idle"
            case .espnScheduleWindow: return "Every minute at :00s (refresh every ~15 min)"
            case .injuries: return "Hourly at :42 (refresh when >4h old)"
            case .f1Enrichment: return "Hourly at :10 (refresh when >6h old)"
            case .golfEnrichment: return "Hourly at :25 (refresh when >25 min old)"
            case .worldCupEnrichment: return "Hourly at :50 (refresh when >30 min old)"
            case .apns: return "Every minute at :05s"
            }
        }

        var displayName: String {
            switch self {
            case .scheduleUpdate: return "ScheduleUpdateJob"
            case .espnFetch: return "ESPNFetchJob"
            case .espnSoccer: return "ESPNSoccerJob"
            case .liveTicker: return "LiveTicker"
            case .espnScheduleWindow: return "ESPNScheduleWindowJob"
            case .injuries: return "InjuriesEnrichmentJob"
            case .f1Enrichment: return "F1EnrichmentJob"
            case .golfEnrichment: return "GolfEnrichmentJob"
            case .worldCupEnrichment: return "WorldCupEnrichmentJob"
            case .apns: return "APNSJob"
            }
        }
    }

    /// Retention for heartbeat keys: long enough to show "last ran 3 days ago".
    static let ttlSeconds = 7 * 24 * 3600

    static func key(_ job: Job, isDebug: Bool) -> String {
        let base = "job:last-success:\(job.rawValue)"
        return isDebug ? "debug-\(base)" : base
    }

    /// Stamps `now` as the job's last success. Never throws; failures are logged at debug.
    static func recordSuccess(_ job: Job, app: Application, isDebug: Bool) async {
        let value = String(Date().timeIntervalSince1970)
        do {
            try await app.kv.setString(key(job, isDebug: isDebug), value: value, ttl: TimeInterval(ttlSeconds))
        } catch {
            app.logger.debug("JobHeartbeat write failed", metadata: ["job": "\(job.rawValue)", "error": "\(error)"])
        }
    }

    /// The job's last recorded success, or nil if never recorded / expired / Redis unreachable.
    static func lastSuccess(_ job: Job, app: Application, isDebug: Bool) async -> Date? {
        guard let raw = try? await app.kv.getString(key(job, isDebug: isDebug)),
              let seconds = Double(raw) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }
}
