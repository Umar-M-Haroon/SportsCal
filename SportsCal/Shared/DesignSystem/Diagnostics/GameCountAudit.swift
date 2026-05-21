//
//  GameCountAudit.swift
//  SportsCal — Diagnostics
//
//  Pure-data layer that snapshots how many games each view "sees" for a
//  given date. Built to catch the class of bug we hit twice during the
//  design system migration:
//
//    - `gamesDict` going stale → EFRemix Today empty while Browse worked
//    - `hidePastEvents` filter → ModernDayPage hid finished games of today
//      while Calendar still counted them
//
//  Returns a `GameCountSnapshot`. Used by both the in-app HUD overlay and
//  the Settings → "Game count audit" diagnostic screen, plus
//  SportsCalTests for CI parity assertions.
//
//  No view dependencies — pure read of GameViewModel + UserDefaultStorage.
//

import Foundation
import SwiftUI
import SportsCalModel

/// One row in the audit table — a (label, count) pair plus its source so
/// the audit screen can show *why* a number diverges.
public struct GameCountRow: Identifiable {
    public let id: String
    public let label: String
    public let count: Int
    public let source: String

    public init(label: String, count: Int, source: String) {
        self.id = label
        self.label = label
        self.count = count
        self.source = source
    }
}

public struct GameCountSnapshot {
    public let date: Date
    public let dateLabel: String

    // Day-bounded counts (selected date) — these SHOULD all match each other
    public let modernTodayCount: Int           // ModernDayPage.dayGames path
    public let classicTodayCount: Int          // viewModel.gamesWithTeams(for:) — used by Classic + Ambient
    public let filteredGamesOnDate: Int        // viewModel.filteredGames clipped to date
    public let totalGamesOnDate: Int           // viewModel.totalGames clipped to date (no prefs)

    // All-dates counts — unrelated to selected date
    public let totalGamesAllDates: Int
    public let filteredGamesAllDates: Int
    public let calendarGamesAllDates: Int
    public let liveEventsCount: Int
    public let liveEventsWithTeamsCount: Int

    // Per-sport on Browse (all dates) — sums should equal calendarGames
    public let browsePerSport: [(sport: SportType, total: Int, live: Int)]

    /// Day-bounded set the user expects to be the SAME number across views.
    /// If these diverge, a screen is silently dropping games.
    public var dayBoundedCounts: [Int] {
        [modernTodayCount, classicTodayCount, totalGamesOnDate]
    }

    public var hasDivergence: Bool {
        Set(dayBoundedCounts).count > 1
    }

    public var rows: [GameCountRow] {
        [
            GameCountRow(label: "Modern Today (\(dateLabel))",
                         count: modernTodayCount,
                         source: "ModernDayPage.dayGames — totalGames + sport prefs + hidden competitions, NOT hidePastEvents"),
            GameCountRow(label: "Classic / Ambient Today (\(dateLabel))",
                         count: classicTodayCount,
                         source: "viewModel.gamesWithTeams(for:) — gamesDict path"),
            GameCountRow(label: "filteredGames on \(dateLabel)",
                         count: filteredGamesOnDate,
                         source: "viewModel.filteredGames clipped to date — applies hidePastEvents"),
            GameCountRow(label: "totalGames on \(dateLabel)",
                         count: totalGamesOnDate,
                         source: "viewModel.totalGames clipped to date — raw, no sport/comp prefs"),
            GameCountRow(label: "totalGames (all dates)",
                         count: totalGamesAllDates,
                         source: "viewModel.totalGames"),
            GameCountRow(label: "filteredGames (all dates)",
                         count: filteredGamesAllDates,
                         source: "viewModel.filteredGames — sport prefs + hidePastEvents applied"),
            GameCountRow(label: "calendarGames (all dates)",
                         count: calendarGamesAllDates,
                         source: "viewModel.calendarGames — totalGames + hidden soccer comps only"),
            GameCountRow(label: "liveEvents",
                         count: liveEventsCount,
                         source: "viewModel.liveEvents"),
            GameCountRow(label: "liveEventsWithTeams",
                         count: liveEventsWithTeamsCount,
                         source: "viewModel.liveEventsWithTeams"),
        ]
    }

    public var browseRows: [GameCountRow] {
        browsePerSport.map { tuple in
            GameCountRow(
                label: "\(tuple.sport.displayName) (Browse)",
                count: tuple.total,
                source: "max(liveGameCountsBySport, totalGames.filter sport) — used by ModernBrowsePage + EFRemixBrowsePage"
            )
        }
    }
}

@MainActor
enum GameCountAudit {

    /// Snapshot every count source for `date`. Pure read — no side effects.
    static func snapshot(
        for date: Date,
        viewModel: GameViewModel,
        storage: UserDefaultStorage
    ) -> GameCountSnapshot {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date

        let total = viewModel.totalGames ?? []
        let filtered = viewModel.filteredGames ?? []
        let calendarG = viewModel.calendarGames ?? []
        let live = viewModel.liveEvents

        // Modern Today path — mirror of ModernDayPage.dayGames.
        let modern = total.filter { game in
            guard let d = game.standardDate, d >= start, d < end else { return false }
            guard let sport = game.sportType, isSportEnabled(sport, storage: storage) else { return false }
            if let id = game.idLeague, let intID = Int(id),
               let league = Leagues(rawValue: intID),
               storage.hiddenCompetitions.contains(league.leagueName) {
                return false
            }
            return true
        }

        // Classic / Ambient Today path
        let classic = viewModel.gamesWithTeams(for: date)

        // filteredGames on date
        let filteredOnDate = filtered.filter { game in
            guard let d = game.standardDate else { return false }
            return d >= start && d < end
        }

        // totalGames on date (raw)
        let totalOnDate = total.filter { game in
            guard let d = game.standardDate else { return false }
            return d >= start && d < end
        }

        // Browse per-sport (all dates) — mirror of ModernBrowsePage.total(for:)
        let allSports: [SportType] = [
            .basketball, .soccer, .hockey, .mlb,
            .nfl, .golf, .tennis, .racing,
        ]
        let browsePerSport: [(SportType, Int, Int)] = allSports.map { sport in
            let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
            let fetched = total.filter { $0.sportType == sport }.count
            return (sport, max(liveCount, fetched), liveCount)
        }

        let f = DateFormatter()
        f.dateFormat = "MMM d"

        return GameCountSnapshot(
            date: date,
            dateLabel: f.string(from: date),
            modernTodayCount: modern.count,
            classicTodayCount: classic.count,
            filteredGamesOnDate: filteredOnDate.count,
            totalGamesOnDate: totalOnDate.count,
            totalGamesAllDates: total.count,
            filteredGamesAllDates: filtered.count,
            calendarGamesAllDates: calendarG.count,
            liveEventsCount: live.count,
            liveEventsWithTeamsCount: viewModel.liveEventsWithTeams.count,
            browsePerSport: browsePerSport
        )
    }

    static func isSportEnabled(_ sport: SportType, storage: UserDefaultStorage) -> Bool {
        switch sport {
        case .basketball: return storage.shouldShowNBA || storage.shouldShowWNBA
        case .soccer:     return storage.shouldShowSoccer
        case .hockey:     return storage.shouldShowNHL
        case .mlb:        return storage.shouldShowMLB
        case .nfl:        return storage.shouldShowNFL
        case .golf:       return storage.shouldShowGolf
        case .tennis:     return storage.shouldShowTennis
        case .racing:     return storage.shouldShowRacing
        }
    }
}
