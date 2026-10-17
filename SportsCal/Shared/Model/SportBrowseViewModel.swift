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
    @ObservationIgnored private var seasonsCache: [Leagues?: [SeasonSpan]] = [:]
    @ObservationIgnored private var leagueGamesCache: [Leagues: [Game]] = [:]

    /// A season in the feed and the matchdays it covers.
    struct SeasonSpan: Hashable {
        let season: String
        let firstDay: Date
        let lastDay: Date
    }

    func fetch() async {
        isLoading = true
        errorMessage = nil

        // Live games from existing snapshot (already fetched for all sports)
        let live = viewModel.liveEventsForSport(sport)
        liveGames = live.compactMap { viewModel.resolveGameWithTeams($0) }

        // Reuse games already in viewModel if the sport was fetched by getInfo(). Football
        // without college switched on came down without college games, and racing without a
        // series beyond F1 came down F1-only, yet Browse lists both — fetch those instead (the
        // browse fetch asks for all of FBS and every series).
        let missingCollege = sport == .nfl && !NetworkHandler.wantsCollegeFootball
        let missingSeries = sport == .racing && !NetworkHandler.wantsMotorsportSeries
        if !missingCollege, !missingSeries, let cached = viewModel.gamesDict[sport], !cached.isEmpty {
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
        seasonsCache = [:]
        leagueGamesCache = [:]
        leagues = counts.keys.sorted {
            let (rankA, rankB) = (Self.soccerChipRank[$0] ?? .max, Self.soccerChipRank[$1] ?? .max)
            if rankA != rankB { return rankA < rankB }
            return counts[$0] != counts[$1] ? counts[$0]! > counts[$1]! : $0.leagueName < $1.leagueName
        }
    }

    /// Soccer chips lead with the top flights and the Champions League; busiest-first alone put
    /// the Championship and the cups (more fixtures) ahead of the Premier League. Leagues not
    /// listed, and every other sport, fall back to busiest-first.
    private static let soccerChipRank: [Leagues: Int] = {
        let order: [Leagues] = [
            .English_Premier_League, .La_Liga, .UEFA_Champions_League, .German_Bundesliga, .Serie_A,
            .Ligue_1, .MLS, .FIFA_World_Cup, .Womens_World_Cup, .UEFA_Europa_League,
            .UEFA_Conference_League, .Liga_MX, .Eredivisie, .A_League, .English_League_Championship,
            .UEFA_Nations_League, .Copa_America, .FA_Cup, .Copa_del_Rey, .DFB_Pokal, .Coupe_De_France,
        ]
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    }()

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

    /// Seasons in the feed, newest first, optionally for one league — the season menu.
    func seasons(league: Leagues?) -> [SeasonSpan] {
        if let cached = seasonsCache[league] { return cached }
        let calendar = Calendar.current
        var spans: [String: (first: Date, last: Date)] = [:]
        for (day, games) in gamesByDay {
            for game in games where league == nil || game.knownLeague == league {
                guard let season = game.resolvedSeason else { continue }
                let span = spans[season]
                spans[season] = (min(span?.first ?? day, day), max(span?.last ?? day, day))
            }
        }
        let result = spans
            .map { SeasonSpan(season: $0.key, firstDay: calendar.startOfDay(for: $0.value.first),
                              lastDay: calendar.startOfDay(for: $0.value.last)) }
            .sorted { $0.lastDay > $1.lastDay }
        seasonsCache[league] = result
        return result
    }

    /// One league's games, unresolved — what its hub lists.
    func games(in league: Leagues) -> [Game] {
        if let cached = leagueGamesCache[league] { return cached }
        let games = fetchedGames.filter { $0.knownLeague == league }
        leagueGamesCache[league] = games
        return games
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
        // By fixture, not id: live games carry ESPN ids, schedule rows TheSportsDB ones.
        let live = LiveFixtureIndex(live: liveGames.map(\.game))
        let resolved = (gamesByDay[day] ?? [])
            .filter { !live.contains($0) }
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
        // Racing keeps everything: browse splits it by series and season, and five series
        // run ~100 races a year, so a shared cap would cut whole seasons out of one series.
        self.upcomingGames = sport == .racing ? upcoming : Array(upcoming.prefix(50))
        self.recentGames = sport == .racing ? recent : Array(recent.prefix(30))
    }
}

extension Game {
    /// `idLeague` as a known `Leagues` case, nil for leagues the app doesn't model.
    var knownLeague: Leagues? {
        idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))
    }
}
