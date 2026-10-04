//
//  HealthController.swift
//
//  Public `GET /health`: a cheap, unauthenticated liveness + freshness probe for
//  uptime monitors. Reports only booleans, ages and job names — no keys, hosts,
//  versions or counts that would help an attacker.
//

import Foundation
import Vapor

struct HealthReport: Content, Sendable {
    struct Check: Content, Sendable {
        let name: String
        let ok: Bool
        /// Seconds since the data was written / the job last succeeded. Nil when unknown.
        let ageSeconds: Int?
        let maxAgeSeconds: Int?
    }

    /// "ok" or "degraded".
    let status: String
    let checkedAt: Date
    let redis: Bool
    let data: [Check]
    let jobs: [Check]
    /// Names of every failing check (`redis`, `data:<name>`, `job:<name>`).
    let failing: [String]
}

enum HealthCheck {
    /// The schedule refresh is gated to >1h, so 3h means at least two missed refreshes.
    static let scheduleMaxAge: TimeInterval = 3 * 3600

    /// Builds the report. Every Redis read is best-effort: a failure shows up as a
    /// failing check rather than an error.
    static func run(app: Application, now: Date = Date()) async -> HealthReport {
        let isDebug = app.environment == .development
        let kv = app.kv

        // Redis reachability: a round trip on a key that need not exist.
        let redisOK: Bool
        do {
            _ = try await kv.exists("health:probe")
            redisOK = true
        } catch {
            redisOK = false
        }

        func age(_ date: Date?) -> Int? {
            date.map { max(0, Int(now.timeIntervalSince($0))) }
        }

        // Data. The live and schedule blobs carry no write timestamp, so their checks are
        // presence; their freshness is covered by the jobs that write them (espnFetch /
        // liveTicker for live info, scheduleUpdate + the schedule last-update stamp below).
        let liveKey = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug).rawValue
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug).rawValue
        let lastUpdateKey = RedisEndpoint.ESPN.scheduleLastUpdate.getValue(isDebug: isDebug).rawValue
        let livePresent = (try? await kv.exists(liveKey)) ?? false
        let schedulePresent = (try? await kv.exists(scheduleKey)) ?? false
        let lastUpdate = try? await kv.getJSON(lastUpdateKey, as: Date.self)
        let lastUpdateAge = age(lastUpdate)

        var data: [HealthReport.Check] = [
            .init(name: "latestLiveInfo", ok: livePresent, ageSeconds: nil, maxAgeSeconds: nil),
            .init(name: "latestSchedule", ok: schedulePresent, ageSeconds: nil, maxAgeSeconds: nil),
            .init(
                name: "scheduleLastUpdate",
                ok: lastUpdateAge.map { TimeInterval($0) <= scheduleMaxAge } ?? false,
                ageSeconds: lastUpdateAge,
                maxAgeSeconds: Int(scheduleMaxAge)
            ),
        ]
        if !redisOK { data = data.map { .init(name: $0.name, ok: false, ageSeconds: $0.ageSeconds, maxAgeSeconds: $0.maxAgeSeconds) } }

        // Jobs. APNSJob is a no-op without an APNS key, so it can't be stale there.
        let apnsConfigured = app.storage[APNSConfiguredKey.self] == true
        var jobs: [HealthReport.Check] = []
        for job in JobHeartbeat.Job.allCases {
            if job == .apns, !apnsConfigured { continue }
            let jobAge = age(await JobHeartbeat.lastSuccess(job, app: app, isDebug: isDebug))
            jobs.append(.init(
                name: job.rawValue,
                ok: jobAge.map { TimeInterval($0) <= job.maxAge } ?? false,
                ageSeconds: jobAge,
                maxAgeSeconds: Int(job.maxAge)
            ))
        }

        var failing: [String] = redisOK ? [] : ["redis"]
        failing += data.filter { !$0.ok }.map { "data:\($0.name)" }
        failing += jobs.filter { !$0.ok }.map { "job:\($0.name)" }

        return HealthReport(
            status: failing.isEmpty ? "ok" : "degraded",
            checkedAt: now,
            redis: redisOK,
            data: data,
            jobs: jobs,
            failing: failing
        )
    }
}

/// Coalesces `/health` probes: at most one evaluation (~15 small Redis reads) per
/// `ttl`, however often the public endpoint is hit.
actor HealthReportCache {
    static let shared = HealthReportCache()

    private var cached: (report: HealthReport, at: Date)?
    private var inFlight: Task<HealthReport, Never>?
    private let ttl: TimeInterval = 5

    func report(app: Application) async -> HealthReport {
        if let cached, Date().timeIntervalSince(cached.at) < ttl { return cached.report }
        if let inFlight { return await inFlight.value }
        let task = Task { await HealthCheck.run(app: app) }
        inFlight = task
        let report = await task.value
        inFlight = nil
        cached = (report, Date())
        return report
    }

    func reset() {
        cached = nil
        inFlight = nil
    }
}

struct HealthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("health", use: health)
    }

    /// 200 with `status: "ok"` when every check passes, otherwise 503 with
    /// `status: "degraded"` and the failing checks listed in `failing`.
    func health(req: Request) async throws -> Response {
        let report = await HealthReportCache.shared.report(app: req.application)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var headers = HTTPHeaders()
        headers.contentType = .json
        headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return Response(
            status: report.failing.isEmpty ? .ok : .serviceUnavailable,
            headers: headers,
            body: .init(data: try encoder.encode(report))
        )
    }
}
