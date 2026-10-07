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

    /// Every fetched game bucketed by local start-of-day, unresolved. Team-sport browse pages
    /// one day at a time over this, so nothing is capped and only the shown day is resolved.
    private(set) var gamesByDay: [Date: [Game]] = [:]
    /// Leagues in the feed, busiest first — the browse league chips.
    private(set) var leagues: [Leagues] = []
    /// Resolved rows per day, filled on first view of that day.
    @ObservationIgnored private var resolvedDays: [Date: [GameWithTeams]] = [:]
    /// Day-strip dots per league filter (nil key = all leagues).
    @ObservationIgnored private var datesCache: [Leagues?: Set<DateComponents>] = [:]

    func fetch() async {
        isLoading = true
        errorMessage = nil

        // Live games from existing snapshot (already fetched for all sports)
        let live = viewModel.liveEventsForSport(sport)
        liveGames = live.compactMap { viewModel.resolveGameWithTeams($0) }

        // Reuse games already in viewModel if the sport was fetched by getInfo(). Football
        // without college switched on came down without college games, and Browse has a
        // College tab — fetch it instead (the browse fetch asks for all of FBS).
        let missingCollege = sport == .nfl && !NetworkHandler.wantsCollegeFootball
        if !missingCollege, let cached = viewModel.gamesDict[sport], !cached.isEmpty {
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
    /// is the bulk of the tennis load time. Skip it entirely for tennis. (Golf browse also reads
    /// only `fetchedGames`, but `SportBrowseSheet` still lists golf by today/upcoming/recent,
    /// and a few hundred tournaments are cheap to categorize.)
    private func categorizeIfNeeded(_ games: [Game]) {
        guard sport != .tennis else { return }
        categorize(games)
        indexByDay(games)
    }

    // MARK: - Day index

    private func indexByDay(_ games: [Game]) {
        let calendar = Calendar.current
        var byDay: [Date: [Game]] = [:]
        var counts: [Leagues: Int] = [:]
        for game in games {
            guard let league = game.knownLeague, let date = game.standardDate else { continue }
            byDay[calendar.startOfDay(for: date), default: []].append(game)
            counts[league, default: 0] += 1
        }
        gamesByDay = byDay
        resolvedDays = [:]
        datesCache = [:]
        leagues = counts.keys.sorted {
            counts[$0] != counts[$1] ? counts[$0]! > counts[$1]! : $0.leagueName < $1.leagueName
        }
    }

    /// Days with games, optionally for one league — the day strip's dots.
    func datesWithGames(league: Leagues?) -> Set<DateComponents> {
        if let cached = datesCache[league] { return cached }
        let calendar = Calendar.current
        var dates = Set<DateComponents>()
        for (day, games) in gamesByDay where league == nil || games.contains(where: { $0.knownLeague == league }) {
            dates.insert(calendar.dateComponents([.day, .month, .year], from: day))
        }
        datesCache[league] = dates
        return dates
    }

    /// The nearest day with games strictly before or after `day`, for the empty-day hint.
    func adjacentDayWithGames(from day: Date, league: Leagues?, forward: Bool) -> Date? {
        let start = Calendar.current.startOfDay(for: day)
        let candidates = gamesByDay.lazy
            .filter { forward ? $0.key > start : $0.key < start }
            .filter { league == nil || $0.value.contains(where: { $0.knownLeague == league }) }
            .map(\.key)
        return forward ? candidates.min() : candidates.max()
    }

    /// The day a browse page opens on: today when anything's on (or live), else the next
    /// matchday, else the most recent one.
    func initialDay() -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        if !liveGames.isEmpty || gamesByDay[today] != nil { return today }
        return adjacentDayWithGames(from: today, league: nil, forward: true)
            ?? adjacentDayWithGames(from: today, league: nil, forward: false)
            ?? today
    }

    /// One day's games, resolved with teams and sorted by start time. Games that are live
    /// right now are left out; the page shows those in its Live section.
    func games(on day: Date) -> [GameWithTeams] {
        let day = Calendar.current.startOfDay(for: day)
        if let cached = resolvedDays[day] { return cached }
        let liveIDs = Set(liveGames.compactMap { $0.game.idEvent })
        let resolved = (gamesByDay[day] ?? [])
            .filter { $0.idEvent.map { !liveIDs.contains($0) } ?? true }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .compactMap { viewModel.resolveGameWithTeams($0) }
        resolvedDays[day] = resolved
        return resolved
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

extension Game {
    /// `idLeague` as a known `Leagues` case, nil for leagues the app doesn't model.
    var knownLeague: Leagues? {
        idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
    }
}
