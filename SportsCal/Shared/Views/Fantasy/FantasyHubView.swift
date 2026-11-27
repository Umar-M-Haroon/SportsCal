//
//  FantasyHubView.swift
//  SportsCal
//
//  The Fantasy hub: a week's player lines scored with the user's scoring. Studs (most
//  points), Stinkers (well short of their pace-adjusted season average) and My Team
//  (an imported league roster plus followed players). Data is `/fantasy/nfl/slate`;
//  scoring happens here, so switching scoring never refetches.
//
//  NFL only for now. Another sport slots in once `FantasyScoring.supports` says so and
//  the server serves its slate.
//

import SwiftUI
import NukeUI
import SportsCalModel

// MARK: - Model

@Observable
@MainActor
final class FantasyHubModel {
    var slate: FantasySlate?
    var isLoading = false
    var errorMessage: String?
    /// The week being shown; nil until the first load picks the current one.
    var week: Int?
    var lastLoaded: Date?

    init(slate: FantasySlate? = nil) {
        self.slate = slate
        week = slate?.week
        lastLoaded = slate == nil ? nil : Date()
    }

    var hasLiveGames: Bool {
        slate?.players.contains(where: \.isLive) == true || slate?.games?.contains { $0.state == "in" } == true
    }

    func load(week requested: Int? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await NetworkHandler.fetchFantasySlate(week: requested ?? week)
            slate = fresh
            week = fresh.week
            errorMessage = nil
            lastLoaded = Date()
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch NetworkHandler.FantasyError.notFound {
            errorMessage = "No fantasy stats for this week yet."
        } catch {
            // Keep a slate already on screen; say so only when there's nothing to show.
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't load fantasy stats."
        }
    }

    func select(week newWeek: Int) async {
        guard newWeek != week else { return }
        week = newWeek
        slate = nil
        await load(week: newWeek)
    }
}

// MARK: - Hub

struct FantasyHubView: View {
    var sport: SportType = .nfl

    @Environment(Favorites.self) private var favorites
    @Environment(FantasySettings.self) private var settings
    @State private var model: FantasyHubModel
    @State private var segment: Segment = .studs
    @State private var position: PositionFilter = .all
    @State private var showScoringPicker = false
    @State private var detail: FantasyEvaluation?

    init(sport: SportType = .nfl, model: FantasyHubModel = FantasyHubModel()) {
        self.sport = sport
        _model = State(initialValue: model)
    }

    enum Segment: String, CaseIterable, Identifiable {
        case studs = "Studs", stinkers = "Stinkers", myTeam = "My Team"
        var id: String { rawValue }
    }

    enum PositionFilter: String, CaseIterable, Identifiable {
        case all = "All", qb = "QB", rb = "RB", wr = "WR", te = "TE", k = "K", dst = "DST"
        var id: String { rawValue }

        func matches(_ line: FantasyPlayerLine) -> Bool {
            switch self {
            case .all: return true
            case .dst: return line.isDST || line.position == "DST"
            default: return line.position == rawValue
            }
        }
    }

    private var scoring: FantasyScoring {
        settings.scoring(for: sport) ?? .nflHalfPPR
    }

    private var evaluations: [FantasyEvaluation] {
        (model.slate?.evaluations(scoring: scoring) ?? []).filter { position.matches($0.line) }
    }

    /// Followed players (this sport) and the user's league rosters, in ESPN athlete IDs.
    private var myIDs: Set<String> {
        let followed = favorites.followedPlayers.filter { $0.sport == sport }.map(\.athleteID)
        return Set(followed).union(settings.myRosterIDs(for: sport))
    }

    var body: some View {
        let evaluations = evaluations
        List {
            Section {
                controls
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if model.slate == nil {
                Section { loadingOrError }
            } else {
                switch segment {
                case .studs: studsSection(evaluations)
                case .stinkers: stinkersSection(evaluations)
                case .myTeam: myTeamSections(evaluations)
                }
            }

            if let slate = model.slate {
                Section {
                } footer: {
                    Text(footer(slate))
                }
            }
        }
        .navigationTitle("Fantasy")
        .refreshable { await model.load() }
        .task {
            if model.slate == nil { await model.load() }
        }
        .task {
            // Live games move every play; check about once a minute while any is on.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if model.hasLiveGames, !model.isLoading { await model.load() }
            }
        }
        .sheet(isPresented: $showScoringPicker) {
            FantasyScoringPicker(sport: sport)
                .environment(settings)
        }
        .sheet(item: $detail) { evaluation in
            FantasyBreakdownSheet(evaluation: evaluation, scoring: scoring)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                weekMenu
                Spacer(minLength: 8)
                FantasyScoringChip(name: scoring.name, sport: sport) { showScoringPicker = true }
            }
            Picker("Show", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PositionFilter.allCases) { filter in
                        FantasyFilterChip(title: filter.rawValue, isSelected: position == filter, tint: Color.app(sport)) {
                            position = filter
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var weekMenu: some View {
        let weeks = model.slate?.availableWeeks ?? model.slate?.week.map { [$0] } ?? []
        Menu {
            ForEach(weeks.reversed(), id: \.self) { week in
                Button {
                    Task { await model.select(week: week) }
                } label: {
                    if week == model.week {
                        Label("Week \(week)", systemImage: "checkmark")
                    } else {
                        Text("Week \(week)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.slate?.label ?? model.week.map { "Week \($0)" } ?? "This week")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                if weeks.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(weeks.count < 2)
        .accessibilityLabel("Week")
    }

    // MARK: Segments

    @ViewBuilder
    private func studsSection(_ evaluations: [FantasyEvaluation]) -> some View {
        let studs = FantasySlate.studs(evaluations, limit: 50)
        Section {
            if studs.isEmpty {
                emptyRow("No points yet", systemImage: "hourglass",
                         message: "Players show up here once their games kick off.")
            } else {
                ForEach(Array(studs.enumerated()), id: \.element.id) { index, evaluation in
                    row(evaluation, rank: index + 1)
                }
            }
        }
    }

    @ViewBuilder
    private func stinkersSection(_ evaluations: [FantasyEvaluation]) -> some View {
        let stinkers = FantasySlate.stinkers(evaluations, limit: 50)
        Section {
            if stinkers.isEmpty {
                emptyRow("No stinkers", systemImage: "hand.thumbsup",
                         message: "Nobody's well short of their usual output. Players are judged once their game is half done.")
            } else {
                ForEach(stinkers) { row($0) }
            }
        } footer: {
            Text("Compared with what the player usually has by this point of a game, from their season average.")
        }
    }

    @ViewBuilder
    private func myTeamSections(_ evaluations: [FantasyEvaluation]) -> some View {
        let ids = myIDs
        let mine = evaluations.filter { ids.contains($0.line.athleteID) }
            .sorted { $0.points > $1.points }
        let starters = settings.myStarterIDs(for: sport)
        let playedIDs = Set(model.slate?.players.map(\.athleteID) ?? [])
        let waiting = favorites.followedPlayers.filter { $0.sport == sport && !playedIDs.contains($0.athleteID) }
        let unnamedWaiting = settings.myRosterIDs(for: sport)
            .subtracting(playedIDs)
            .subtracting(waiting.map(\.athleteID))
            .count

        if ids.isEmpty {
            Section {
                emptyRow("No players yet", systemImage: "person.crop.circle.badge.plus",
                         message: "Import your fantasy league from the scoring menu, or follow players from a game's box score.")
                Button("Import a league…") { showScoringPicker = true }
            }
        } else if !starters.isEmpty {
            let starting = mine.filter { starters.contains($0.line.athleteID) }
            let bench = mine.filter { !starters.contains($0.line.athleteID) }
            Section {
                if starting.isEmpty {
                    Text("No starters have played yet.").foregroundStyle(.secondary)
                }
                ForEach(starting) { row($0) }
            } header: {
                HStack {
                    Text("Starters")
                    Spacer()
                    Text(FantasyScoring.format(starting.reduce(0) { $0 + $1.points }) + " pts")
                        .monospacedDigit()
                }
            }
            if !bench.isEmpty {
                Section("Bench & followed") { ForEach(bench) { row($0) } }
            }
            waitingSection(waiting, unnamed: unnamedWaiting)
        } else {
            Section {
                if mine.isEmpty {
                    Text("None of your players have played yet.").foregroundStyle(.secondary)
                }
                ForEach(mine) { row($0) }
            }
            waitingSection(waiting, unnamed: unnamedWaiting)
        }
    }

    @ViewBuilder
    private func waitingSection(_ players: [PlayerRef], unnamed: Int) -> some View {
        if !players.isEmpty || unnamed > 0 {
            Section("Yet to play") {
                ForEach(players) { player in
                    HStack {
                        Text(player.name)
                        Spacer()
                        Text(kickoff(for: player) ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if unnamed > 0 {
                    Text("\(unnamed) more on your roster")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Sun 1:00 PM" from the slate's schedule, matched by the ESPN team the player follows.
    private func kickoff(for player: PlayerRef) -> String? {
        guard let game = model.slate?.games?.first(where: { $0.homeTeamID == player.teamID || $0.awayTeamID == player.teamID }),
              let date = game.date else { return nil }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func row(_ evaluation: FantasyEvaluation, rank: Int? = nil) -> some View {
        Button {
            detail = evaluation
        } label: {
            FantasyPlayerRow(evaluation: evaluation, rank: rank)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: States

    @ViewBuilder
    private var loadingOrError: some View {
        if model.isLoading {
            ForEach(0..<6, id: \.self) { _ in FantasyPlayerRow.placeholder }
        } else if let message = model.errorMessage {
            ContentUnavailableView {
                Label("Fantasy unavailable", systemImage: "football")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func emptyRow(_ title: String, systemImage: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity)
    }

    private func footer(_ slate: FantasySlate) -> String {
        var parts = ["Scored with \(scoring.name)."]
        if !settings.isSelectionInEffect(for: sport) {
            parts.append("Your custom or league scoring needs Scoreline Pro; showing \(scoring.name).")
        }
        parts.append("Updated \(slate.generatedAt.formatted(.relative(presentation: .named))).")
        return parts.joined(separator: " ")
    }
}

// MARK: - Row

struct FantasyPlayerRow: View {
    let evaluation: FantasyEvaluation
    var rank: Int? = nil

    private var line: FantasyPlayerLine { evaluation.line }

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 18)
            }
            FantasyHeadshot(url: line.headshot, isDST: line.isDST, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.matchup(line))
                    if let status = Self.status(line) {
                        Text(status)
                            .foregroundStyle(line.isLive ? Color.appLive : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                let summary = line.statSummary
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(FantasyScoring.format(evaluation.points))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let delta = evaluation.delta {
                    FantasyDeltaPill(delta: delta)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows the scoring breakdown")
    }

    private var accessibilityText: String {
        var text = "\(line.name), \(Self.matchup(line)). \(FantasyScoring.format(evaluation.points)) points"
        if let delta = evaluation.delta {
            text += ", \(FantasyScoring.format(abs(delta))) \(delta >= 0 ? "above" : "below") average"
        }
        if let status = Self.status(line) { text += ". \(status)" }
        return text
    }

    /// "WR · DET vs CHI", "DET @ GB" for a defense.
    static func matchup(_ line: FantasyPlayerLine) -> String {
        let team = line.teamAbbreviation ?? ""
        let versus = line.opponentAbbreviation.map { (line.isHome == false ? "@ " : "vs ") + $0 } ?? ""
        let matchup = [team, versus].filter { !$0.isEmpty }.joined(separator: " ")
        guard let position = line.position, !line.isDST else { return matchup }
        return matchup.isEmpty ? position : "\(position) · \(matchup)"
    }

    static func status(_ line: FantasyPlayerLine) -> String? {
        if let status = line.gameStatus, !status.isEmpty { return status }
        return line.isFinal ? "Final" : nil
    }

    /// A loading row the same height as a real one.
    static var placeholder: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.secondary.opacity(0.15)).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)).frame(width: 90, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)).frame(width: 36, height: 20)
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

/// "+6.2" in green, "−3.1" in red: points over or under the player's pace.
struct FantasyDeltaPill: View {
    let delta: Double

    var body: some View {
        let rounded = FantasyScoring.rounded(delta)
        let color: Color = rounded > 0 ? .appPositive : rounded < 0 ? .appNegative : .secondary
        Text((rounded > 0 ? "+" : rounded < 0 ? "−" : "±") + FantasyScoring.format(abs(rounded)))
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

struct FantasyHeadshot: View {
    let url: String?
    var isDST = false
    var size: CGFloat

    var body: some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                LazyImage(url: imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: isDST ? .fit : .fill)
                            .padding(isDST ? size * 0.12 : 0)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: isDST ? "shield.fill" : "person.fill")
            .font(.system(size: size * 0.45))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The active scoring's name; opens the scoring picker.
struct FantasyScoringChip: View {
    let name: String
    let sport: SportType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                Text(name).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.app(sport))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appTint(sport), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scoring: \(name)")
        .accessibilityHint("Change how fantasy points are scored")
    }
}

struct FantasyFilterChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? tint : Color.secondaryGroupedBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Breakdown

struct FantasyBreakdownSheet: View {
    let evaluation: FantasyEvaluation
    let scoring: FantasyScoring

    @Environment(\.dismiss) private var dismiss

    private var line: FantasyPlayerLine { evaluation.line }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        FantasyHeadshot(url: line.headshot, isDST: line.isDST, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name).font(.title3.weight(.semibold))
                            Text(FantasyPlayerRow.matchup(line)).font(.subheadline).foregroundStyle(.secondary)
                            if let status = FantasyPlayerRow.status(line) {
                                Text(status).font(.caption)
                                    .foregroundStyle(line.isLive ? Color.appLive : .secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(FantasyScoring.format(evaluation.points))
                                .font(.largeTitle.weight(.bold))
                                .monospacedDigit()
                            Text("pts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    let contributions = scoring.breakdown(line.stats)
                    if contributions.isEmpty {
                        Text("Nothing scored yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(contributions.enumerated()), id: \.offset) { _, item in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Self.title(item, scoring: scoring))
                                if !item.isRule, let weight = scoring.weights[item.stat] {
                                    Text("\(FantasyScoring.format(item.value)) × \(FantasyScoring.format(weight))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            Spacer()
                            Text(Self.signed(item.points))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(item.points < 0 ? Color.appNegative : .primary)
                        }
                    }
                } header: {
                    Text("Breakdown · \(scoring.name)")
                }

                Section("Season") {
                    if let average = evaluation.averagePoints {
                        LabeledContent("Average", value: FantasyScoring.format(average) + " pts")
                        if let games = line.seasonGames {
                            LabeledContent("Games", value: "\(games)")
                        }
                        if !line.isFinal, let expected = evaluation.expectedSoFar {
                            LabeledContent("Expected by now", value: FantasyScoring.format(expected) + " pts")
                        }
                        if let delta = evaluation.delta {
                            LabeledContent("Versus average") { FantasyDeltaPill(delta: delta) }
                        }
                    } else {
                        Text("No earlier games this season to compare with.").foregroundStyle(.secondary)
                    }
                }

                let summary = line.statSummary
                if !summary.isEmpty {
                    Section("Stat line") {
                        Text(summary).monospacedDigit()
                    }
                }
            }
            .navigationTitle("Fantasy points")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// "Rec yards", "Pass yards 300+ bonus", "Points allowed 7–13".
    static func title(_ item: FantasyScoring.Contribution, scoring: FantasyScoring) -> String {
        let label = FantasyStatKey.label(item.stat)
        guard item.isRule else { return label }
        guard let rule = scoring.rules.first(where: { $0.stat == item.stat && $0.applies(to: item.value) }) else {
            return label
        }
        if item.stat == FantasyStatKey.NFL.dstPointsAllowed {
            return "\(label) (\(FantasyScoring.format(item.value)))"
        }
        return "\(label) \(FantasyScoring.format(rule.min))+ bonus"
    }

    static func signed(_ points: Double) -> String {
        let rounded = FantasyScoring.rounded(points)
        return (rounded > 0 ? "+" : rounded < 0 ? "−" : "") + FantasyScoring.format(abs(rounded))
    }
}

// MARK: - Preview data

extension FantasySlate {
    /// A Week 13 slate for previews: a few live and final lines with season averages.
    static var preview: FantasySlate {
        typealias K = FantasyStatKey.NFL
        func line(_ id: String, _ name: String, _ position: String, _ team: String, _ opponent: String,
                  home: Bool, stats: [String: Double], average: [String: Double]?, state: String,
                  progress: Double, status: String) -> FantasyPlayerLine {
            FantasyPlayerLine(
                athleteID: id, name: name, position: position,
                headshot: nil, teamID: team, teamAbbreviation: team, opponentAbbreviation: opponent,
                isHome: home, eventID: "4017\(team)", stats: stats, gameState: state,
                gameProgress: progress, gameStatus: status, seasonAverage: average, seasonGames: average == nil ? nil : 11
            )
        }
        let players = [
            line("4430737", "Jahmyr Gibbs", "RB", "DET", "CHI", home: true,
                 stats: [K.rushingAttempts: 18, K.rushingYards: 121, K.rushingTouchdowns: 2, K.receptions: 4, K.targets: 5, K.receivingYards: 38],
                 average: [K.rushingYards: 82, K.rushingTouchdowns: 0.9, K.receptions: 3, K.receivingYards: 25],
                 state: "in", progress: 0.7, status: "Q3 4:12"),
            line("4241479", "Amon-Ra St. Brown", "WR", "DET", "CHI", home: true,
                 stats: [K.receptions: 3, K.targets: 7, K.receivingYards: 22],
                 average: [K.receptions: 7, K.receivingYards: 88, K.receivingTouchdowns: 0.7],
                 state: "in", progress: 0.7, status: "Q3 4:12"),
            line("3918298", "Josh Allen", "QB", "BUF", "KC", home: false,
                 stats: [K.completions: 24, K.passingAttempts: 33, K.passingYards: 287, K.passingTouchdowns: 3, K.interceptionsThrown: 1,
                         K.rushingAttempts: 6, K.rushingYards: 41],
                 average: [K.passingYards: 240, K.passingTouchdowns: 1.8, K.rushingYards: 35, K.rushingTouchdowns: 0.5],
                 state: "post", progress: 1, status: "Final"),
            line("4362628", "Ja'Marr Chase", "WR", "CIN", "PIT", home: true,
                 stats: [K.receptions: 2, K.targets: 9, K.receivingYards: 19, K.fumblesLost: 1],
                 average: [K.receptions: 8, K.receivingYards: 105, K.receivingTouchdowns: 0.9],
                 state: "post", progress: 1, status: "Final"),
            line("4372016", "Travis Kelce", "TE", "KC", "BUF", home: true,
                 stats: [K.receptions: 6, K.targets: 8, K.receivingYards: 64],
                 average: nil, state: "post", progress: 1, status: "Final"),
            line("15683", "Brandon Aubrey", "K", "DAL", "NYG", home: true,
                 stats: [K.fieldGoalsMade: 3, K.fieldGoalAttempts: 3, K.fieldGoals50plus: 1, K.extraPointsMade: 2, K.extraPointAttempts: 2],
                 average: [K.fieldGoalsMade: 2, K.fieldGoalAttempts: 2.3, K.extraPointsMade: 2.4, K.extraPointAttempts: 2.5],
                 state: "post", progress: 1, status: "Final"),
        ]
        return FantasySlate(sport: .nfl, season: 2026, week: 13, label: "Week 13",
                            generatedAt: Date().addingTimeInterval(-90), players: players,
                            availableWeeks: Array(1...13))
    }
}

#Preview("Fantasy hub") {
    NavigationStack {
        FantasyHubView(model: FantasyHubModel(slate: .preview))
    }
    .environment(Favorites())
    .environment(FantasySettings(defaults: UserDefaults(suiteName: "fantasy.preview")!, observesCloud: false))
}

#Preview("Breakdown") {
    FantasyBreakdownSheet(evaluation: FantasyEvaluation(line: FantasySlate.preview.players[0], scoring: .nflHalfPPR),
                          scoring: .nflHalfPPR)
}
