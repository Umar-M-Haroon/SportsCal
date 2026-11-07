//
//  LiveSourcesController.swift
//
//  Admin view of the racing live sources: which source reports score changes first and
//  by how much the others lag (LiveSourceStats), and a per-game override that pins a
//  game to one source when the others are wrong — Real Sports' "forced source" idea.
//

import Vapor
import SportsCalModel

struct LiveSourcesController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let live = routes.grouped("api", "admin", "live-sources")
        live.get(use: overview)
        live.put("forced", use: forceSource)
        live.delete("forced", ":eventID", use: clearForcedSource)
        live.delete("stats", use: resetStats)
    }

    struct SourceSummary: Content {
        let name: String
        let wins: Int
        let follows: Int
        let averageLagSeconds: Double
        let maxLagSeconds: Double
        let behind: Int
    }

    struct Overview: Content {
        let since: Date?
        let tickIntervalSeconds: Double
        let sources: [SourceSummary]
        let recent: [LiveSourceStats.Race]
        /// Snapshot idEvent → pinned source name.
        let forced: [String: String]
        /// League → source names racing for it (ESPN alone when a league isn't listed).
        let configured: [String: [String]]
    }

    struct ForceRequest: Content {
        let eventID: String
        let source: String
    }

    /// Source names a game may be pinned to. Kept in step with each LiveSource's `name`.
    static let knownSources: Set<String> = ["espn", "fifa", "mlb-statsapi", "nhl-apiweb", "nba-cdn"]

    func overview(req: Request) async throws -> Overview {
        let isDebug = req.application.environment == .development
        let kv = req.application.kv
        let stats = try? await kv.getJSON(LiveSourceStats.key(isDebug: isDebug), as: LiveSourceStats.self)
        let forced = (try? await kv.getJSON(LiveSourceStats.forcedSourcesKey(isDebug: isDebug), as: [String: String].self)) ?? [:]
        let sources = (stats?.sources ?? [:])
            .map { name, r in
                SourceSummary(
                    name: name, wins: r.wins, follows: r.follows,
                    averageLagSeconds: r.averageLagSeconds, maxLagSeconds: r.maxLagSeconds, behind: r.behind
                )
            }
            .sorted { $0.name < $1.name }
        return Overview(
            since: stats?.since,
            tickIntervalSeconds: LiveTicker.fastInterval,
            sources: sources,
            recent: stats?.recent ?? [],
            forced: forced,
            configured: LiveSourceResolver.fromEnvironment().describe()
        )
    }

    func forceSource(req: Request) async throws -> [String: String] {
        let body = try req.content.decode(ForceRequest.self)
        guard !body.eventID.isEmpty else { throw Abort(.badRequest, reason: "eventID is required") }
        guard Self.knownSources.contains(body.source) else {
            throw Abort(.badRequest, reason: "Unknown source '\(body.source)'")
        }
        return try await updateForced(req) { $0[body.eventID] = body.source }
    }

    func clearForcedSource(req: Request) async throws -> [String: String] {
        guard let eventID = req.parameters.get("eventID") else { throw Abort(.badRequest) }
        return try await updateForced(req) { $0[eventID] = nil }
    }

    func resetStats(req: Request) async throws -> HTTPStatus {
        let isDebug = req.application.environment == .development
        _ = try await req.application.kv.delete([LiveSourceStats.key(isDebug: isDebug)])
        return .noContent
    }

    /// Read-modify-write of the pinned-source map. Admin-only and rare, so a lost update
    /// between two simultaneous admin edits is acceptable. Pins expire after two days:
    /// they're for one game, and a forgotten one shouldn't outlive it.
    private func updateForced(_ req: Request, _ change: (inout [String: String]) -> Void) async throws -> [String: String] {
        let isDebug = req.application.environment == .development
        let key = LiveSourceStats.forcedSourcesKey(isDebug: isDebug)
        var forced = (try? await req.application.kv.getJSON(key, as: [String: String].self)) ?? [:]
        change(&forced)
        if forced.isEmpty {
            _ = try await req.application.kv.delete([key])
        } else {
            try await req.application.kv.setJSON(key, value: forced, ttl: 2 * 24 * 3600)
        }
        return forced
    }
}
