//
//  SportBrowseViewModel.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import Foundation
import SwiftUI
import SportsCalModel

@MainActor
@Observable
class SportBrowseViewModel {
    let sport: SportType
    private let viewModel: GameViewModel

    var isLoading = true
    var errorMessage: String?
    var liveGames: [GameWithTeams] = []
    var todayGames: [GameWithTeams] = []
    var upcomingGames: [GameWithTeams] = []
    var recentGames: [GameWithTeams] = []

    init(sport: SportType, viewModel: GameViewModel) {
        self.sport = sport
        self.viewModel = viewModel
    }

    /// The raw games fetched during browse (kept so "Add to My Sports" can merge without re-fetching)
    private(set) var fetchedGames: [Game] = []

    func fetch() async {
        isLoading = true
        errorMessage = nil

        // Live games from existing snapshot (already fetched for all sports)
        let live = viewModel.liveEventsForSport(sport)
        liveGames = live.compactMap { viewModel.resolveGameWithTeams($0) }

        // Reuse games already in viewModel if the sport was fetched by getInfo()
        if let cached = viewModel.gamesDict[sport], !cached.isEmpty {
            fetchedGames = cached
            categorizeIfNeeded(cached)
        } else {
            // Sport not in enabled list — fetch from network
            do {
                let schedule = try await NetworkHandler.getScheduleFor(sport: sport)
                fetchedGames = schedule.events
                categorizeIfNeeded(fetchedGames)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    /// Tennis browse drills in by tournament (see `BrowsePage.tennisTournamentSections`) and only
    /// reads `fetchedGames` — it never touches today/upcoming/recent. Running `categorize()` over a
    /// full two-season tennis schedule (~20k matches) calls `resolveGameWithTeams` per match, which
    /// is the bulk of the tennis load time. Skip it entirely for tennis.
    private func categorizeIfNeeded(_ games: [Game]) {
        guard sport != .tennis else { return }
        categorize(games)
    }

    private func categorize(_ games: [Game]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        // Filter to valid league games
        let valid = games.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let _ = Leagues(rawValue: intLeague) else { return false }
            return true
        }

        var today: [GameWithTeams] = []
        var upcoming: [GameWithTeams] = []
        var recent: [GameWithTeams] = []

        // Collect IDs of live games to avoid duplicates
        let liveIDs = Set(liveGames.map { $0.game.idEvent })

        for game in valid {
            // Skip if already in live section
            if let eventID = game.idEvent, liveIDs.contains(eventID) { continue }

            guard let gwt = viewModel.resolveGameWithTeams(game) else { continue }
            // Race weekends span multiple days; bucket them by race day (last session)
            // rather than the weekend start, so an in-progress weekend whose race hasn't
            // run yet stays in Upcoming/Today instead of falling into Past.
            let bucketDate = game.isRace ? (game.effectiveEndDate ?? game.standardDate) : game.standardDate
            guard let date = bucketDate else {
                upcoming.append(gwt)
                continue
            }

            if date < startOfToday {
                recent.append(gwt)
            } else if date < startOfTomorrow {
                today.append(gwt)
            } else {
                upcoming.append(gwt)
            }
        }

        // Sort: recent newest first, today/upcoming earliest first
        recent.sort { ($0.game.standardDate ?? .distantPast) > ($1.game.standardDate ?? .distantPast) }
        today.sort { ($0.game.standardDate ?? .distantFuture) < ($1.game.standardDate ?? .distantFuture) }
        upcoming.sort { ($0.game.standardDate ?? .distantFuture) < ($1.game.standardDate ?? .distantFuture) }

        self.todayGames = today
        self.upcomingGames = Array(upcoming.prefix(50))
        // Racing returns ~2 full seasons (~50 races) which we split by season; keep enough.
        self.recentGames = Array(recent.prefix(sport == .racing ? 80 : 30))
    }
}
