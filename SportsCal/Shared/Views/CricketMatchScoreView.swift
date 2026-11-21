//
//  CricketMatchScoreView.swift
//  SportsCal
//
//  A cricket match in a day list: context line (match label, tour), both sides with their
//  innings ("137 & 144/2") and the overs of the innings in progress, and ESPN's state line
//  ("India trail by 209 runs"). Team rows can't show it: their scores are `Int`s.
//

import SwiftUI
import SportsCalModel

struct CricketMatchScoreView: View {
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var isLive: Bool

    private var winner: GameSituation.Side? { game.cricketWinner }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if isLive { parts.append("Live") }
        parts.append("\(game.strHomeTeam) vs \(game.strAwayTeam)")
        if let context = game.cricketContext { parts.append(context) }
        for (side, name) in [(GameSituation.Side.home, game.strHomeTeam), (.away, game.strAwayTeam)] {
            if let score = game.cricketScore(for: side) {
                parts.append("\(name) \(CricketMatchScoreView.spoken(score))")
            }
        }
        if let summary = game.cricketSummary {
            parts.append(summary)
        } else if let status = game.cricketStatusText {
            parts.append(status)
        } else if let date = game.standardDate, date > Date() {
            parts.append(GameRowAccessibility.when(date))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            VStack(alignment: .leading, spacing: 6) {
                sideRow(.home, name: game.strHomeTeam, badge: game.strHomeTeamBadge)
                sideRow(.away, name: game.strAwayTeam, badge: game.strAwayTeamBadge)
            }
            .accessibilityHidden(true)
            if let summary = game.cricketSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(isLive ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            headerSummary
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel))
            Menu {
                FavoriteMenu(game: game)
                    .environment(favorites)
                CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 24)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions")
        }
    }

    private var headerSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: SportType.cricket.systemImage)
                .foregroundColor(SportType.cricket.color)
            // The match label ("1st Test", "Final") says the format too; the tour name
            // is the detail's — both don't fit beside the status.
            if let label = game.round ?? game.cricket?.format.displayName {
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            statusLabel
            if isLive {
                Text("LIVE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let status = game.cricketStatusText, !(isLive && status == "Live") {
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if game.strStatus == "pre" || game.strStatus == nil, let date = game.standardDate {
            GameTimeLabel(date: date, includeDate: false, isTBD: game.isTimeTBD)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func sideRow(_ side: GameSituation.Side, name: String, badge: String?) -> some View {
        let batting = isLive && game.cricket?.battingSide == side
        let emphasized = winner == side || batting
        return HStack(spacing: 6) {
            CricketTeamBadge(url: badge, size: 24)
            Text(name)
                .font(.subheadline)
                .fontWeight(emphasized ? .semibold : .regular)
                .lineLimit(1)
            if batting {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(SportType.cricket.color)
            }
            Spacer(minLength: 4)
            if let overs = game.cricketOvers(for: side) {
                Text(overs)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let score = game.cricketScore(for: side) {
                Text(score)
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(emphasized ? .bold : .regular)
                    .foregroundStyle(winner == nil || winner == side ? Color.primary : Color.secondary)
            }
        }
    }

    /// "144/2" reads as "144 for 2"; "137 & 144/2" as "137, then 144 for 2".
    static func spoken(_ score: String) -> String {
        score
            .replacingOccurrences(of: " & ", with: ", then ")
            .replacingOccurrences(of: "/", with: " for ")
            .replacingOccurrences(of: "d", with: " declared")
    }
}

/// A cricket crest: square-ish, so fitted rather than circle-cropped like a headshot.
struct CricketTeamBadge: View {
    let url: String?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        Image(systemName: "shield.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.quaternary)
            .padding(2)
    }
}

#Preview {
    let live = Game(
        idEvent: "1539442", idLeague: "\(Leagues.cricketTests.rawValue)",
        idHomeTeam: "cricket-2", idAwayTeam: "cricket-6",
        strHomeTeam: "New Zealand", strAwayTeam: "India",
        intHomeScore: "368", intAwayScore: "159/1 (39 ov)",
        strStatus: "in", strProgress: "Stumps", strTimestamp: "2026-11-18T22:00Z",
        lastPlay: "India trail by 209 runs", isoDate: nil,
        tournamentName: "India tour of New Zealand 2026/27", round: "1st Test",
        endDate: "2026-11-23T23:59Z",
        scoreboardExtras: ScoreboardExtras(cricket: CricketMatchExtras(
            format: .test,
            innings: [
                CricketInnings(side: .home, number: 1, runs: 368, wickets: 10, overs: 112.4),
                CricketInnings(side: .away, number: 2, runs: 159, wickets: 1, overs: 39, isCurrent: true),
            ],
            summary: "India trail by 209 runs", session: "Day 2", statusDetail: "Stumps", matchLabel: "1st Test"
        ))
    )
    List {
        CricketMatchScoreView(game: live, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
    }
    .environment(Favorites())
    .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
}
