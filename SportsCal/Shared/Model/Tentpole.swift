//
//  Tentpole.swift
//  SportsCal
//
//  The big days on the sports calendar (Christmas Day basketball, Thanksgiving football…)
//  and the banner the day page shows on them, with one tap to switch the slate on.
//

import SwiftUI
import SportsCalModel

/// A day the whole country watches one slate. Dates come from calendar rules, not a
/// table, so they never go stale; the banner only appears when the schedule actually
/// has games in these leagues that day.
struct Tentpole: Identifiable, Equatable {
    let id: String
    let title: String
    let emoji: String
    let leagues: [Leagues]
    /// Whether `day` (a local calendar day) is this tentpole's date.
    let matches: (DateComponents) -> Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    static let all: [Tentpole] = [
        Tentpole(id: "thanksgiving", title: "Thanksgiving football", emoji: "🦃", leagues: [.nfl, .ncaaf]) {
            $0.month == 11 && $0.weekday == 5 && nthWeekday($0) == 4
        },
        Tentpole(id: "christmas", title: "Christmas Day", emoji: "🎄", leagues: [.nba, .nfl]) {
            $0.month == 12 && $0.day == 25
        },
        Tentpole(id: "new-years-day", title: "New Year's Day bowls", emoji: "🏈", leagues: [.ncaaf]) {
            $0.month == 1 && $0.day == 1
        },
        Tentpole(id: "mlk-day", title: "MLK Day basketball", emoji: "🏀", leagues: [.nba]) {
            $0.month == 1 && $0.weekday == 2 && nthWeekday($0) == 3
        },
    ]

    /// Which occurrence of its weekday in the month a day is (the 4th Thursday → 4).
    private static func nthWeekday(_ day: DateComponents) -> Int {
        guard let d = day.day else { return 0 }
        return (d - 1) / 7 + 1
    }

    /// The tentpole on `date`, if any.
    static func on(_ date: Date, calendar: Calendar = .current) -> Tentpole? {
        let day = calendar.dateComponents([.month, .day, .weekday], from: date)
        return all.first { $0.matches(day) }
    }

    /// The per-year key a dismissal is stored under, so next Christmas shows again.
    func dismissalKey(for date: Date, calendar: Calendar = .current) -> String {
        "\(id)-\(calendar.component(.year, from: date))"
    }
}

/// What the banner says about one tentpole day: game counts per league, from the full
/// schedule (switched off or not), and which of those leagues the user doesn't show.
struct TentpoleSlate: Equatable {
    let tentpole: Tentpole
    let counts: [(league: Leagues, games: Int)]
    let hiddenLeagues: [Leagues]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tentpole == rhs.tentpole && lhs.hiddenLeagues == rhs.hiddenLeagues
            && lhs.counts.map(\.league) == rhs.counts.map(\.league) && lhs.counts.map(\.games) == rhs.counts.map(\.games)
    }

    /// "5 NBA · 3 NFL games"
    var summary: String {
        let total = counts.reduce(0) { $0 + $1.games }
        let parts = counts.map { "\($0.games) \(Tentpole.shortName($0.league))" }.joined(separator: " · ")
        return "\(parts) \(total == 1 ? "game" : "games")"
    }

    /// Nil when nothing in the tentpole's leagues is scheduled that day.
    static func build(for date: Date, games: [Game], shows: (Leagues) -> Bool,
                      calendar: Calendar = .current) -> TentpoleSlate? {
        guard let tentpole = Tentpole.on(date, calendar: calendar) else { return nil }
        let ids = Dictionary(uniqueKeysWithValues: tentpole.leagues.map { ("\($0.rawValue)", $0) })
        var counts: [Leagues: Int] = [:]
        for game in games {
            guard let id = game.idLeague, let league = ids[id],
                  let start = game.standardDate, calendar.isDate(start, inSameDayAs: date) else { continue }
            counts[league, default: 0] += 1
        }
        let ordered = tentpole.leagues.compactMap { league in counts[league].map { (league: league, games: $0) } }
        guard !ordered.isEmpty else { return nil }
        return TentpoleSlate(tentpole: tentpole, counts: ordered,
                             hiddenLeagues: ordered.map(\.league).filter { !shows($0) })
    }
}

extension Tentpole {
    static func shortName(_ league: Leagues) -> String {
        switch league {
        case .ncaaf: return "college"
        default: return league.leagueName
        }
    }
}

/// The day page's card for a tentpole: what's on, and a button to show the leagues the
/// user has switched off. Dismissible for the year.
struct TentpoleBanner: View {
    let slate: TentpoleSlate
    let turnOn: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(slate.tentpole.emoji)
                .font(.system(size: 30))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(slate.tentpole.title).font(.headline)
                Text(slate.summary).font(.subheadline).foregroundStyle(.secondary)
                if !slate.hiddenLeagues.isEmpty {
                    Button(action: turnOn) {
                        Text("Show \(slate.hiddenLeagues.map(Tentpole.shortName).joined(separator: " & ")) Games")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
