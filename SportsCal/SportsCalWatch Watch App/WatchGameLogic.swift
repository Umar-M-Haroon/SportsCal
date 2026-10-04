//
//  WatchGameLogic.swift
//  SportsCalWatch Watch App
//
//  Pure game filtering / merging used by `WatchViewModel`, kept free of state so the
//  watch unit tests can exercise it directly.
//

import Foundation
import SportsCalModel

enum WatchGameLogic {

    /// How long a cached / last-fetched snapshot stays "fresh". Older data is still shown,
    /// but marked stale and no longer trusted for live state.
    static let staleAfter: TimeInterval = 2 * 60 * 60

    /// Whether `game` is in progress: it has a status that isn't pre-game or final, and scores.
    static func isLive(_ game: Game) -> Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" &&
               status != "aet" &&
               status != "not started" &&
               status != "ns" &&
               game.intHomeScore != nil &&
               game.intAwayScore != nil
    }

    /// Drops games whose sport the user turned off, and games in a competition the user
    /// hid on the phone (same rule as the iOS app: `Game.isInHiddenCompetition`).
    /// Games with no recognisable sport are kept.
    static func visibleGames(
        _ games: [Game],
        enabledSports: Set<SportType>,
        hiddenCompetitions: Set<String>
    ) -> [Game] {
        games.filter { game in
            if let sport = game.sportType, !enabledSports.contains(sport) { return false }
            if !hiddenCompetitions.isEmpty, game.isInHiddenCompetition(hiddenCompetitions) { return false }
            return true
        }
    }

    /// Overlays live score/status fields onto the matching scheduled games, preserving the
    /// schedule-only fields (start time, season, tournament grouping). Mirrors the iOS
    /// `GameViewModel.mergeLiveIntoSchedule`: match by `idEvent` (never falling back to
    /// team names for a game that has one), team-name + same-day fallback otherwise, and
    /// pre-game live entries are ignored. Live games with no scheduled counterpart are
    /// not appended. O(n + m).
    static func mergeLive(_ live: [Game], into schedule: [Game]) -> [Game] {
        guard !live.isEmpty, !schedule.isEmpty else { return schedule }

        var liveByEventID: [String: Game] = [:]
        var liveByTeams: [String: Game] = [:]
        for game in live {
            if let eventID = game.idEvent, liveByEventID[eventID] == nil {
                liveByEventID[eventID] = game
            }
            liveByTeams[teamKey(game)] = game
        }

        var merged = schedule
        for i in merged.indices {
            let scheduled = merged[i]
            let match: Game
            if let eventID = scheduled.idEvent {
                guard let byID = liveByEventID[eventID] else { continue }
                match = byID
            } else {
                guard let byTeams = liveByTeams[teamKey(scheduled)] else { continue }
                if let scheduledDate = scheduled.standardDate,
                   let liveDate = byTeams.standardDate,
                   !Calendar.current.isDate(scheduledDate, inSameDayAs: liveDate) {
                    continue
                }
                match = byTeams
            }
            guard match.strStatus != "pre" && match.strStatus != "NS" else { continue }
            if scheduled.intHomeScore == match.intHomeScore &&
               scheduled.intAwayScore == match.intAwayScore &&
               scheduled.strStatus == match.strStatus &&
               scheduled.strProgress == match.strProgress &&
               scheduled.isCompleted == match.isCompleted { continue }
            merged[i] = overlay(live: match, onto: scheduled)
        }
        return merged
    }

    private static func teamKey(_ game: Game) -> String {
        "\(game.strHomeTeam.lowercased())|\(game.strAwayTeam.lowercased())|\(game.idLeague ?? "")"
    }

    /// The scheduled game with the live feed's score, status and progress laid over it.
    static func overlay(live: Game, onto scheduled: Game) -> Game {
        Game(
            idLiveScore: scheduled.idLiveScore, idEvent: scheduled.idEvent,
            idLeague: scheduled.idLeague,
            idHomeTeam: scheduled.idHomeTeam, idAwayTeam: scheduled.idAwayTeam,
            strHomeTeam: scheduled.strHomeTeam, strAwayTeam: live.strAwayTeam,
            strHomeTeamBadge: live.strHomeTeamBadge ?? scheduled.strHomeTeamBadge,
            strAwayTeamBadge: live.strAwayTeamBadge ?? scheduled.strAwayTeamBadge,
            intHomeScore: live.intHomeScore ?? scheduled.intHomeScore,
            intAwayScore: live.intAwayScore ?? scheduled.intAwayScore,
            strStatus: live.strStatus ?? scheduled.strStatus,
            strProgress: live.strProgress ?? scheduled.strProgress,
            strTimestamp: scheduled.strTimestamp,
            lastPlay: live.lastPlay ?? scheduled.lastPlay,
            homeLinescores: live.homeLinescores ?? scheduled.homeLinescores,
            awayLinescores: live.awayLinescores ?? scheduled.awayLinescores,
            homeLeaders: live.homeLeaders ?? scheduled.homeLeaders,
            awayLeaders: live.awayLeaders ?? scheduled.awayLeaders,
            isCompleted: live.isCompleted ?? scheduled.isCompleted,
            isoDate: scheduled.isoDate,
            leaderboardEntries: live.leaderboardEntries ?? scheduled.leaderboardEntries,
            sessions: live.sessions ?? scheduled.sessions,
            venueName: live.venueName ?? scheduled.venueName,
            circuitInfo: live.circuitInfo ?? scheduled.circuitInfo,
            homeSeed: live.homeSeed ?? scheduled.homeSeed,
            awaySeed: live.awaySeed ?? scheduled.awaySeed,
            tournamentName: scheduled.tournamentName ?? live.tournamentName,
            round: scheduled.round ?? live.round,
            drawSlug: scheduled.drawSlug ?? live.drawSlug,
            playoff: live.playoff ?? scheduled.playoff,
            endDate: scheduled.endDate ?? live.endDate,
            season: scheduled.season ?? live.season,
            seasonPhase: live.seasonPhase ?? scheduled.seasonPhase,
            situation: live.situation,
            excitement: live.excitement ?? scheduled.excitement
        )
    }

    /// Poll interval: 30s with a live game, 60s otherwise, doubling per consecutive
    /// failure up to 5 minutes so a dead network doesn't burn battery.
    static func pollInterval(hasLiveGames: Bool, consecutiveFailures: Int) -> TimeInterval {
        let base: TimeInterval = hasLiveGames ? 30 : 60
        let factor = pow(2.0, Double(min(max(consecutiveFailures, 0), 4)))
        return min(base * factor, 300)
    }
}
