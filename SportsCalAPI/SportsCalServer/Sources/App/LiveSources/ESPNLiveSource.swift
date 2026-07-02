//
//  ESPNLiveSource.swift
//
//  The default live source: ESPN scoreboards, matched into the snapshot by `idEvent`
//  (same upstream the snapshot was built from). The ticker also uses `fetchBoards`
//  directly so it can refresh `latestSoccerScoreboards` (an ESPN-shaped cache the slow
//  pipeline reads); other sources don't have that obligation.
//

import Foundation
import Vapor
import SportsCalModel

struct ESPNLiveSource: LiveSource {
    let name = "espn"
    /// ESPN's fast-path role is soccer; other sports stay on the 60s pipeline.
    let sport: SportType = .soccer
    let matchStrategy: LiveMerge.MatchStrategy = .eventID

    func fetchLive(leagues: Set<Leagues>, app: Application) async throws -> [Game] {
        let boards = await fetchBoards(leagues: leagues, app: app)
        return boards.compactMap { LiveEvent(events: $0.value, league: $0.key) }
            .flatMap { $0.events }
    }

    /// Concurrent per-league scoreboard fetch. World Cup uses the default (today) window —
    /// fresher live clock/FT than the season query. The global 429 breaker and per-league
    /// 5xx cooldown auto-skip failing leagues.
    func fetchBoards(leagues: Set<Leagues>, app: Application) async -> [Leagues: Scoreboard] {
        await withTaskGroup(of: (Leagues, Scoreboard?).self) { group in
            for league in leagues {
                group.addTask {
                    do {
                        return (league, try await Integrator.getESPNScoreboard(for: league, app.client, dates: nil))
                    } catch {
                        return (league, nil)
                    }
                }
            }
            var out: [Leagues: Scoreboard] = [:]
            for await (league, board) in group {
                if let board { out[league] = board }
            }
            return out
        }
    }
}
