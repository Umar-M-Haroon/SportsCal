//
//  TennisMatchScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel

/// Whether tennis rows name their tournament. Off where rows already sit under a
/// tournament heading (Browse, the hub, Home's per-tournament groups); on in mixed
/// lists (Live, Your Teams).
private struct TennisRowShowsTournamentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tennisRowShowsTournament: Bool {
        get { self[TennisRowShowsTournamentKey.self] }
        set { self[TennisRowShowsTournamentKey.self] = newValue }
    }
}

/// Compact list row for a tennis head-to-head match showing player names and set scores
struct TennisMatchScoreView: View {
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Environment(\.tennisRowShowsTournament) private var showsTournament
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var isLive: Bool
    @ScaledMetric(relativeTo: .subheadline) private var setColumnWidth: CGFloat = 28

    private var sportType: SportType? {
        guard let id = game.idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) else { return nil }
        return SportType(league: league)
    }

    /// Finished sets only: 6-4 3-2 is one set to none, not one each.
    private var setsWon: (home: Int, away: Int) { game.tennisSetsWon }

    /// The side to bold: the winner once it's over (ESPN's call, so a retirement reads
    /// right), the side ahead on sets while it's live. Nobody at 0-0 or on a walkover.
    private var emphasizedSide: GameSituation.Side? {
        TennisMatchPresentation.emphasizedSide(game)
    }

    /// One VoiceOver sentence: "Live, Sinner vs Alcaraz, QF, sets 1 to 0, 7 6, tiebreak 7 4, 3 2, Sinner serving".
    /// Home player first, matching the visual row order.
    private var accessibilityLabel: String {
        var parts: [String] = []
        if isLive { parts.append("Live") }
        if let stoppage = game.tennisStoppageText { parts.append(stoppage) }
        parts.append("\(game.strHomeTeam) vs \(game.strAwayTeam)")
        if showsTournament, let tournament = game.tournamentName { parts.append(tournament) }
        if let round = game.round { parts.append(round) }
        parts.append(contentsOf: TennisMatchPresentation.spokenScore(game))
        if game.tennisMatchWinner == nil {
            if let status = game.displayStatus {
                parts.append(game.isFinalStatus ? status.lowercased() : status)
            } else if !isLive, let date = game.standardDate, date > Date() {
                parts.append(GameRowAccessibility.when(date))
            }
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            // Players read as part of the header's sentence.
            let sets = game.tennisSets
            VStack(alignment: .leading, spacing: 6) {
                playerRow(side: .home, name: game.strHomeTeam, seed: game.tennisHomeSeed,
                          headshot: game.strHomeTeamBadge, sets: sets)
                playerRow(side: .away, name: game.strAwayTeam, seed: game.tennisAwaySeed,
                          headshot: game.strAwayTeamBadge, sets: sets)
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }

    /// Sport icon, round, tournament (in mixed lists), status or start time, and the
    /// actions menu — on one line, so the menu no longer takes a row of its own.
    private var header: some View {
        HStack(spacing: 6) {
            headerSummary
                // The whole row's sentence lives here; the menu stays its own element.
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
            if let sport = sportType {
                Image(systemName: sport.systemImage)
                    .foregroundColor(sport.color)
            }
            if let round = game.shortRoundLabel {
                Text(round)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            if showsTournament, let tournament = game.tournamentName {
                Text(tournament)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            statusLabel
            Spacer(minLength: 4)
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
        if let stoppage = game.tennisStoppageText {
            TennisStoppageBadge(text: stoppage)
        } else if let progress = game.displayStatus {
            Text(progress)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if let date = game.standardDate {
            GameTimeLabel(date: date, includeDate: false)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func playerRow(side: GameSituation.Side, name: String, seed: Int?, headshot: String?, sets: [TennisSet]) -> some View {
        let isEmphasized = emphasizedSide == side
        let isServing = game.tennisServer == side
        let marker = game.tennisMatchWinner == side ? game.tennisResultMarker : nil
        return HStack(spacing: 0) {
            HeadshotView(url: headshot, size: 24)
                .padding(.trailing, 6)
            if let seed {
                Text("\(seed)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 3)
            }
            Text(name)
                .font(.subheadline)
                .fontWeight(isEmphasized ? .semibold : .regular)
                .lineLimit(1)
            if isServing {
                TennisServeDot()
                    .padding(.leading, 4)
            }
            if let marker {
                Text(marker)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 4)

            ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                let wonSet = set.winner == side
                Text(set.text(for: side))
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(wonSet ? .bold : .regular)
                    .foregroundColor(wonSet || !set.isComplete ? .primary : .secondary)
                    .frame(minWidth: setColumnWidth, alignment: .center)
            }
        }
    }
}

/// The ball by the server's name.
struct TennisServeDot: View {
    var body: some View {
        Circle()
            .fill(Color.yellow)
            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// Rain delay / suspension, distinct from the plain status text.
struct TennisStoppageBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "cloud.rain.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .lineLimit(1)
    }
}

/// Reading shared by the tennis row and detail.
enum TennisMatchPresentation {
    /// Winner once it's over, the side ahead on sets while live; nobody at level sets
    /// or on a walkover (there's no match to have won).
    static func emphasizedSide(_ game: Game) -> GameSituation.Side? {
        if game.tennisResultMarker == "w/o" { return nil }
        if let winner = game.tennisMatchWinner { return winner }
        let won = game.tennisSetsWon
        if won.home == won.away { return nil }
        return won.home > won.away ? .home : .away
    }

    /// "sets 1 to 0", "7 6, tiebreak 7 4, 3 2", "Sinner serving", "Sinner won by retirement".
    static func spokenScore(_ game: Game) -> [String] {
        var parts: [String] = []
        let sets = game.tennisSets
        if !sets.isEmpty {
            let won = game.tennisSetsWon
            parts.append("sets \(won.home) to \(won.away)")
            parts.append(sets.map(\.spokenText).joined(separator: ", "))
        }
        if let server = game.tennisServer {
            parts.append("\(server == .home ? game.strHomeTeam : game.strAwayTeam) serving")
        }
        if let winner = game.tennisMatchWinner {
            let name = winner == .home ? game.strHomeTeam : game.strAwayTeam
            let how: String
            switch game.tennisResultMarker {
            case "w/o": how = " by walkover"
            case "ret.": how = ", opponent retired"
            default: how = ""
            }
            parts.append("\(name) won\(how)")
        }
        return parts
    }
}
