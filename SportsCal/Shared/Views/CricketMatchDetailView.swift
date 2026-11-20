//
//  CricketMatchDetailView.swift
//  SportsCal
//
//  A cricket match: both sides' innings, ESPN's state line, the chase (target, runs and
//  rate required) while one is on, and the innings-by-innings card. Batting and bowling
//  cards come from ESPN's match summary in a later pass.
//

import SwiftUI
import SportsCalModel

struct CricketMatchDetailView: View {
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?

    /// The freshest copy: a live match keeps updating under an open detail.
    private var current: Game {
        guard let id = game.idEvent else { return game }
        return viewModel.totalGames?.first(where: { $0.idEvent == id }) ?? game
    }

    private var isLive: Bool { current.strStatus == "in" }

    var body: some View {
        let game = current
        List {
            Section {
                header(game)
            }
            if let chase = chase(game) {
                Section("Chase") {
                    chase
                }
            }
            if let innings = game.cricket?.innings, !innings.isEmpty {
                Section("Innings") {
                    ForEach(innings, id: \.number) { inning in
                        inningsRow(inning, game: game)
                    }
                }
            }
            Section {
                if let venue = game.venueName {
                    LabeledContent("Venue", value: venue)
                }
                if let date = game.standardDate {
                    LabeledContent("Start") {
                        Text(date, format: .dateTime.weekday().month().day().hour().minute())
                    }
                }
                if let format = game.cricket?.format {
                    LabeledContent("Format", value: format.displayName)
                }
                if let series = game.tournamentName {
                    LabeledContent("Series", value: series)
                }
                LabeledContent("Competition", value: game.strLeague ?? "Cricket")
            }
            Section {
                CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
            }
        }
        .navigationTitle(game.round ?? "Match")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    FavoriteMenu(game: game)
                        .environment(favorites)
                } label: {
                    Label("Follow", systemImage: "star")
                }
            }
        }
    }

    private func header(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: SportType.cricket.systemImage)
                    .foregroundColor(SportType.cricket.color)
                if let context = game.cricketContext {
                    Text(context)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
            side(.home, name: game.strHomeTeam, badge: game.strHomeTeamBadge, game: game)
            side(.away, name: game.strAwayTeam, badge: game.strAwayTeamBadge, game: game)
            if let summary = game.cricketSummary {
                Text(summary)
                    .font(.subheadline.weight(.medium))
            }
            if let status = game.cricketStatusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let date = game.standardDate {
                GameTimeLabel(date: date, includeDate: true, isTBD: game.isTimeTBD)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func side(_ side: GameSituation.Side, name: String, badge: String?, game: Game) -> some View {
        let winner = game.cricketWinner
        let batting = isLive && game.cricket?.battingSide == side
        return HStack(spacing: 10) {
            CricketTeamBadge(url: badge, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .fontWeight(winner == side || batting ? .bold : .regular)
                if batting {
                    Text("Batting")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SportType.cricket.color)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let score = game.cricketScore(for: side) {
                    Text(score)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(winner == nil || winner == side ? Color.primary : Color.secondary)
                }
                if let overs = game.cricketOvers(for: side) {
                    Text(overs)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func chaseContent(_ cricket: CricketMatchExtras, target: Int) -> some View {
        LabeledContent("Target", value: "\(target)")
        if let required = cricket.runsRequired {
            LabeledContent("Runs needed", value: "\(required)")
        }
        if let rate = cricket.currentInnings?.runRate {
            LabeledContent("Run rate", value: rate.formatted(.number.precision(.fractionLength(2))))
        }
        if let rate = cricket.requiredRunRate {
            LabeledContent("Required rate", value: rate.formatted(.number.precision(.fractionLength(2))))
        }
    }

    private func chase(_ game: Game) -> AnyView? {
        guard isLive, let cricket = game.cricket, let target = cricket.target,
              cricket.currentInnings != nil else { return nil }
        return AnyView(chaseContent(cricket, target: target))
    }

    private func inningsRow(_ inning: CricketInnings, game: Game) -> some View {
        let name = inning.side == .home ? game.strHomeTeam : game.strAwayTeam
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                Text(Self.ordinal(inning.number) + " innings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(inning.scoreText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                HStack(spacing: 6) {
                    if let overs = inning.oversText { Text(overs) }
                    if let rate = inning.runRate {
                        Text("RR \(rate.formatted(.number.precision(.fractionLength(2))))")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func ordinal(_ number: Int) -> String {
        switch number {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(number)th"
        }
    }
}
