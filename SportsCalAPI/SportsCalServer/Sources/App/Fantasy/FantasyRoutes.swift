//
//  FantasyRoutes.swift
//  SportsCalServer
//
//  GET /fantasy/:sport/slate[?week=N&seasontype=2]  → FantasySlate
//  GET /fantasy/event/:eventID                      → [FantasyPlayerLine]
//  GET /fantasy/import/sleeper/:username            → FantasySleeperUser
//  GET /fantasy/import/sleeper/league/:id?userID=   → FantasyLeague
//
//  Lines carry raw stats, not points: the app scores them with whichever scoring the
//  user picked (a preset, their own, an imported league's).
//

import Foundation
import SportsCalModel
import Redis
import Vapor

func registerFantasyRoutes(on routes: RoutesBuilder, app: Application) {
    let fantasy = routes.grouped("fantasy")

    fantasy.get(":sport", "slate") { req async throws -> String in
        guard let sport = req.parameters.get("sport").flatMap(SportType.init(rawValue:)),
              FantasyScoring.supports(sport) else {
            throw Abort(.notFound)
        }
        let week = try? req.query.get(Int.self, at: "week")
        let seasonType = try? req.query.get(Int.self, at: "seasontype")
        if let week, !(1...25).contains(week) { throw Abort(.badRequest) }
        if let seasonType, !(1...3).contains(seasonType) { throw Abort(.badRequest) }
        let slate = try await FantasyService.slate(
            sport: sport, week: week, seasonType: seasonType, app: req.application, isDebug: req.isDebugEnvironment
        )
        return encodeResult(res: slate)
    }

    fantasy.get("event", ":eventID") { req async throws -> String in
        guard let eventID = req.parameters.get("eventID"), !eventID.isEmpty, eventID.count <= 20,
              eventID.allSatisfy(\.isNumber) else {
            throw Abort(.badRequest)
        }
        let lines = try await FantasyService.eventLines(eventID: eventID, app: req.application, isDebug: req.isDebugEnvironment)
        return encodeResult(res: lines)
    }

    // Imports reach a third party per request; keep them well under Sleeper's own
    // 1000/min limit even if a key leaks.
    let imports = fantasy.grouped("import")
        .grouped(RateLimitMiddleware(limit: 30, windowSeconds: 60, keyPrefix: "rl:fantasy-import", ipCeiling: 120))

    imports.get("sleeper", "league", ":leagueID") { req async throws -> String in
        guard let leagueID = req.parameters.get("leagueID") else { throw Abort(.badRequest) }
        let userID = try? req.query.get(String.self, at: "userID")
        let league = try await SleeperImport.league(id: leagueID, userID: userID, app: req.application, isDebug: req.isDebugEnvironment)
        return encodeResult(res: league)
    }

    imports.get("sleeper", ":username") { req async throws -> String in
        guard let username = req.parameters.get("username") else { throw Abort(.badRequest) }
        let user = try await SleeperImport.user(username: username, app: req.application)
        return encodeResult(res: user)
    }
}

extension Request {
    var isDebugEnvironment: Bool { application.environment == .development }
}
