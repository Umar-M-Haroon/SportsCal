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
    @State private var scorecard: CricketScorecard?
    @State private var selectedInnings: Int?

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
            if let scorecard, !scorecard.innings.isEmpty {
                scorecardSections(scorecard)
            } else if let innings = game.cricket?.innings, !innings.isEmpty {
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
        .task(id: game.idEvent) { await refreshScorecard() }
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

    // MARK: - Scorecard

    /// Loads the card, then keeps it fresh every 30 seconds while the match is live.
    private func refreshScorecard() async {
        while !Task.isCancelled {
            if current.strStatus != "pre",
               let card = try? await NetworkHandler.getCricketScorecard(for: current) {
                scorecard = card
            }
            guard isLive else { return }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    @ViewBuilder
    private func scorecardSections(_ card: CricketScorecard) -> some View {
        let shown = card.innings.first { $0.number == selectedInnings } ?? card.innings.last!
        Section {
            if card.innings.count > 1 {
                Picker("Innings", selection: Binding(
                    get: { shown.number },
                    set: { selectedInnings = $0 }
                )) {
                    ForEach(card.innings) { innings in
                        Text(Self.inningsTitle(innings, in: card)).tag(innings.number)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Scorecard")
        }
        Section {
            ForEach(shown.batters, id: \.self) { batter in
                batterRow(batter)
            }
            if let extras = shown.extras {
                LabeledContent("Extras", value: extras)
                    .font(.caption)
            }
            if !shown.yetToBat.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yet to bat")
                        .font(.caption.weight(.semibold))
                    Text(shown.yetToBat.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("\(shown.battingTeam) batting")
                Spacer()
                columnHeader(["R", "B", "4s", "6s"])
            }
        } footer: {
            if let total = shown.total {
                Text("Total \(total)" + (shown.overs.map { " (\(CricketInnings(side: shown.battingSide, number: shown.number, runs: 0, wickets: 0, overs: $0).oversText ?? ""))" } ?? ""))
            }
        }
        if !shown.bowlers.isEmpty {
            Section {
                ForEach(shown.bowlers, id: \.self) { bowler in
                    bowlerRow(bowler)
                }
            } header: {
                HStack {
                    Text("Bowling")
                    Spacer()
                    columnHeader(["O", "M", "R", "W"])
                }
            }
        }
    }

    /// Column labels on the same 32-point grid as the rows' figures.
    private func columnHeader(_ labels: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(labels, id: \.self) { label in
                Text(label).frame(width: 32, alignment: .trailing)
            }
        }
    }

    private func batterRow(_ batter: CricketScorecard.Batter) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(batter.name)
                    .font(.subheadline)
                    .fontWeight(batter.isOut ? .regular : .semibold)
                if let dismissal = batter.dismissal {
                    Text(dismissal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            statColumns([batter.runs, batter.balls, batter.fours, batter.sixes], emphasizeFirst: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(batter.name), \(batter.dismissal ?? (batter.isOut ? "out" : "not out")), \(batter.runs) off \(batter.balls) balls, \(batter.fours) fours, \(batter.sixes) sixes")
    }

    private func bowlerRow(_ bowler: CricketScorecard.Bowler) -> some View {
        let overs = CricketInnings(side: .home, number: 1, runs: 0, wickets: 0, overs: bowler.overs).oversText?
            .replacingOccurrences(of: " ov", with: "") ?? "0"
        return HStack(alignment: .firstTextBaseline) {
            Text(bowler.name)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 0) {
                Text(overs).frame(width: 32, alignment: .trailing)
                Text("\(bowler.maidens)").frame(width: 32, alignment: .trailing)
                Text("\(bowler.runs)").frame(width: 32, alignment: .trailing)
                Text("\(bowler.wickets)").frame(width: 32, alignment: .trailing).fontWeight(.semibold)
            }
            .font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bowler.name), \(overs) overs, \(bowler.maidens) maidens, \(bowler.wickets) for \(bowler.runs)")
    }

    private func statColumns(_ values: [Int], emphasizeFirst: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text("\(value)")
                    .fontWeight(emphasizeFirst && index == 0 ? .semibold : .regular)
                    .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .font(.subheadline.monospacedDigit())
    }

    /// "NZ 1st", "IND 2nd": short enough for a segmented control with four innings.
    static func inningsTitle(_ innings: CricketScorecard.Innings, in card: CricketScorecard) -> String {
        let sideInnings = card.innings.filter { $0.battingSide == innings.battingSide }
        let team = innings.battingTeam.split(separator: " ").map { String($0.prefix(1)) }.joined()
        let short = team.count >= 2 ? team.uppercased() : String(innings.battingTeam.prefix(3)).uppercased()
        guard sideInnings.count > 1, let index = sideInnings.firstIndex(where: { $0.number == innings.number }) else {
            return short
        }
        return "\(short) \(ordinal(index + 1))"
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

#Preview {
    let game = Game(
        idEvent: "1539442", idLeague: "\(Leagues.cricketTests.rawValue)",
        idHomeTeam: "cricket-2", idAwayTeam: "cricket-6",
        strHomeTeam: "New Zealand", strAwayTeam: "India",
        intHomeScore: "368", intAwayScore: "159/1 (39 ov)",
        strStatus: "post", strProgress: "Stumps", strTimestamp: "2026-11-18T22:00Z",
        lastPlay: "India trail by 209 runs", isoDate: nil, venueName: "Basin Reserve, Wellington",
        tournamentName: "India tour of New Zealand 2026/27", round: "1st Test",
        scoreboardExtras: ScoreboardExtras(cricket: CricketMatchExtras(
            format: .test,
            innings: [
                CricketInnings(side: .home, number: 1, runs: 368, wickets: 10, overs: 121),
                CricketInnings(side: .away, number: 2, runs: 159, wickets: 1, overs: 39),
            ],
            summary: "India trail by 209 runs", session: "Day 2", statusDetail: "Stumps", matchLabel: "1st Test"
        ))
    )
    NavigationStack {
        CricketMatchDetailView(game: game)
    }
    .environment(SubscriptionManager.shared)
    .environment(UserDefaultStorage())
    .environment(Favorites())
    .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
}
