//
//  TournamentDetailView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2/7/26.
//

import SwiftUI
import SportsCalModel
#if os(iOS)
import EventKit
import EventKitUI
#endif

struct TournamentDetailView: View {
    private let scheduledGame: Game
    /// The whole field with scorecards, for a finished golf tournament: the schedule
    /// keeps only its top five (see the server's `ScheduleSlimming`).
    @State private var fullGame: Game?

    init(game: Game) {
        self.scheduledGame = game
    }

    /// The fetched full field, with the live feed's (fresher, top-of-board) rows on top
    /// while the tournament is being played.
    private var game: Game {
        guard let fullGame else { return scheduledGame }
        guard scheduledGame.strStatus == "in" else { return fullGame }
        var merged = scheduledGame
        let top = scheduledGame.leaderboardEntries ?? []
        let names = Set(top.map(\.name))
        let lastPosition = top.map(\.position).max() ?? 0
        let rest = (fullGame.leaderboardEntries ?? []).filter { !names.contains($0.name) && $0.position > lastPosition }
        merged.leaderboardEntries = top + rest
        merged.golfCourseInfo = (scheduledGame.golfCourseInfo ?? fullGame.golfCourseInfo)?.withContext(from: fullGame.golfCourseInfo)
        return merged
    }

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    /// Keyed by player name, not row: rows move as the board updates.
    @State private var expandedPlayers: Set<String> = []
    @State private var comparingPlayerName: String?
    @State private var comparisonPair: (LeaderboardEntry, LeaderboardEntry)?
    @ScaledMetric(relativeTo: .caption) private var positionWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var todayWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var thruWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var scoreWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var headshotSize: CGFloat = 28

    private var league: Leagues? {
        guard let id = game.idLeague, let intID = Int(id) else { return nil }
        return Leagues(rawValue: intID)
    }

    private var sportType: SportType? {
        guard let league else { return nil }
        return SportType(league: league)
    }

    private var isLive: Bool {
        game.strStatus == "in"
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                tournamentHeader
                roundProgressBar
                gameInfo
                actionsRow
                leaderboardSection
                roundHeatmapSection
                scorecardSection
                courseDifficultySection
            }
            .padding()
        }
        .navigationTitle(league?.leagueName ?? "Tournament")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: scheduledGame.idEvent) {
            // PGA TOUR rows carry TheSportsDB's ID; the ESPN merge records ESPN's alongside.
            guard let league, league.isGolf,
                  let eventID = scheduledGame.lastPlayScoreboardID ?? scheduledGame.idEvent else { return }
            // The schedule keeps a finished event's top five and a live one's top
            // `golfFieldLimit`: the whole field (favourites below the cut-off, the cut
            // line) comes from `/golf/tournament`, refreshed while play is on.
            let isLiveNow = scheduledGame.strStatus == "in"
            let isSlimmed = scheduledGame.hasDoneStatus && (scheduledGame.leaderboardEntries?.count ?? 0) <= 5
            guard isLiveNow || isSlimmed else { return }
            while !Task.isCancelled {
                if let fetched = try? await NetworkHandler.fetchGolfTournament(league: league, eventID: eventID) {
                    fullGame = fetched
                }
                guard scheduledGame.strStatus == "in" else { break }
                try? await Task.sleep(for: .seconds(90))
            }
        }
        .sheet(item: $sheetType) { sheet in
            switch sheet {
            case .calendar(let eventGame):
                #if os(iOS)
                if let game = eventGame {
                    makeCalendarEvent(game: game)
                }
                #else
                EmptyView()
                #endif
            default:
                EmptyView()
            }
        }
        .sheet(isPresented: Binding(
            get: { comparisonPair != nil },
            set: { if !$0 { comparisonPair = nil; comparingPlayerName = nil } }
        )) {
            if let pair = comparisonPair {
                GolfPlayerComparisonView(playerA: pair.0, playerB: pair.1, coursePar: game.coursePar)
            }
        }
    }

    // MARK: - Tournament Header
    private var tournamentHeader: some View {
        VStack(spacing: 12) {
            HStack {
                if let sport = sportType {
                    Image(systemName: sport.systemImage)
                        .font(.title2)
                        .foregroundColor(sport.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(game.strHomeTeam)
                            .font(.title2)
                            .fontWeight(.bold)
                        if game.isMajor {
                            Text("MAJOR")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.gradient)
                                .clipShape(Capsule())
                        }
                    }
                    if let venue = game.venueName {
                        Text(venue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let context = tournamentContextLine {
                        Text(context)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }

            if let stoppage = game.golfStoppageText {
                Label(stoppage, systemImage: "cloud.bolt.rain.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Play \(stoppage.lowercased())")
            } else if let progress = game.displayStatus {
                Text(progress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Leader highlight
            if let leader = game.resolvedLeaderboard.first {
                HStack(spacing: 8) {
                    HeadshotView(url: leader.headshot, size: 32)
                    if let flagURL = leader.flagURL {
                        AsyncImage(url: URL(string: flagURL)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            EmptyView()
                        }
                        .frame(width: 20, height: 14)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Leader")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(leader.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Text(leader.score)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Round Progress Bar
    /// Every scheduled round: played ones filled, the current one highlighted, the rest dimmed.
    @ViewBuilder
    private var roundProgressBar: some View {
        let entries = game.resolvedLeaderboard
        let totalRounds = game.golfScheduledRounds
        if !entries.isEmpty, totalRounds > 0 {
            let currentRound = detectCurrentRound(entries: entries)
            HStack(spacing: 0) {
                ForEach(0..<totalRounds, id: \.self) { i in
                    if i > 0 {
                        Rectangle()
                            .fill(i <= currentRound ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                    ZStack {
                        Circle()
                            .fill(roundColor(index: i, current: currentRound))
                            .frame(width: 24, height: 24)
                        Text("R\(i + 1)")
                            .font(.caption2)
                            .fontWeight(i == currentRound ? .bold : .regular)
                            .foregroundColor(.white)
                    }
                    .opacity(i > currentRound ? 0.5 : 1)
                }
            }
            .padding(.horizontal)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Round \(currentRound + 1) of \(totalRounds)")
        }
    }

    /// Zero-based index of the round in play (or last played). ESPN's "Round N" status
    /// first; otherwise the most rounds anyone has finished, plus one if someone is out
    /// on the course.
    private func detectCurrentRound(entries: [LeaderboardEntry]) -> Int {
        if let round = game.golfCurrentRound { return max(0, round - 1) }
        let finished = entries.map(\.rounds.count).max() ?? 0
        let onCourse = entries.contains(where: \.isOnCourse)
        return max(0, onCourse ? finished : finished - 1)
    }

    private func roundColor(index: Int, current: Int) -> Color {
        if index < current { return .green }
        if index == current { return game.hasDoneStatus && game.strStatus != "pre" ? .green : .accentColor }
        return Color.gray.opacity(0.4)
    }

    /// "$6,000,000 purse · Defending: Ben Griffin".
    private var tournamentContextLine: String? {
        guard let info = game.golfCourseInfo else { return nil }
        var parts: [String] = []
        if let purse = info.purse, !purse.isEmpty { parts.append("\(purse) purse") }
        if let champion = info.defendingChampion { parts.append("Defending: \(champion)") }
        if let yards = info.yardage { parts.append("\(yards.formatted()) yds · Par \(info.par)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Game Info
    private var gameInfo: some View {
        HStack(spacing: 12) {
            if let sport = sportType {
                Image(systemName: sport.systemImage)
                    .foregroundColor(sport.color)
            }
            if let leagueName = league?.leagueName {
                Text(leagueName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let date = game.standardDate {
                GameTimeLabel(date: date, includeDate: true)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Actions Row
    private var actionsRow: some View {
        HStack(spacing: 16) {
            Menu {
                FavoriteMenu(game: game)
                    .environment(favorites)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: favorites.contains(game) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundColor(favorites.contains(game) ? .yellow : .secondary)
                    Text("Favorite")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            #if canImport(ActivityKit) && os(iOS)
            autoFollowAction
            #endif

            #if os(iOS)
            Button {
                EKEventStore().requestAccess(to: .event) { _, _ in
                    sheetType = .calendar(game: game)
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            #endif

            Menu {
                NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Notify")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Auto-Follow Action
    #if canImport(ActivityKit) && os(iOS)
    @ViewBuilder
    private var autoFollowAction: some View {
        if let eventID = game.idEvent, !isGameCompleted(game), !isLive {
            let isFollowing = viewModel.appStorage.isAutoFollowing(eventID)
            Button {
                if isFollowing {
                    viewModel.appStorage.removeAutoFollow(eventID)
                } else {
                    viewModel.appStorage.addAutoFollow(eventID)
                    if let (home, away) = viewModel.getTeams(for: game) {
                        viewModel.preCacheBadges(homeTeam: home, awayTeam: away)
                    }
                }
                #if os(iOS)
                viewModel.sendAutoFollowRegistration()
                #endif
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isFollowing ? "clock.badge.fill" : "clock.badge")
                        .font(.title3)
                        .foregroundColor(isFollowing ? .accentColor : .secondary)
                    Text(isFollowing ? "Following" : "Auto-Follow")
                        .font(.caption2)
                        .foregroundColor(isFollowing ? .accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

    // MARK: - Leaderboard
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .font(.headline)

            let entries = game.resolvedLeaderboard
            if entries.isEmpty {
                VStack(spacing: 8) {
                    if game.strAwayTeam != "TBD" {
                        HStack {
                            Text(game.strAwayTeam)
                                .font(.subheadline)
                            Spacer()
                            if let score = game.intAwayScore {
                                Text(score)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    Text("Detailed leaderboard not available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                let columns = LeaderboardColumns(entries: entries)
                let labels = entries.golfPositionLabels()
                let cutIndex = entries.firstIndex(where: { $0.isCut == true })
                let projectedCutIndex = cutIndex == nil ? projectedCutIndex(entries: entries) : nil

                leaderboardHeader(columns: columns)

                // Comparison mode banner
                if comparingPlayerName != nil {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Tap another player to compare")
                            .font(.caption)
                        Spacer()
                        Button("Cancel") {
                            comparingPlayerName = nil
                        }
                        .font(.caption.bold())
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }

                // Player rows, identified by name so expansion follows the player.
                ForEach(Array(entries.enumerated()), id: \.element.name) { index, entry in
                    if let cutIdx = cutIndex, cutIdx == index, cutIdx > 0 {
                        cutDivider(text: "CUT", color: .red)
                    } else if let projected = projectedCutIndex, projected.index == index {
                        cutDivider(text: "PROJECTED CUT \(GolfScore.format(toPar: projected.score))", color: .orange)
                    }
                    leaderboardRow(entry: entry, index: index, label: labels[index], columns: columns, entries: entries)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    /// Which optional columns the board has data for.
    private struct LeaderboardColumns {
        let hasRounds: Bool
        let hasThru: Bool
        let hasToday: Bool
        let hasMovement: Bool

        init(entries: [LeaderboardEntry]) {
            hasRounds = entries.contains(where: { !$0.rounds.isEmpty || $0.isOnCourse })
            hasThru = entries.contains(where: { $0.thruHole != nil || $0.teeTime != nil })
            hasToday = entries.contains(where: { $0.today != nil })
            hasMovement = entries.contains(where: { $0.movement != nil && $0.movement != 0 })
        }
    }

    private func leaderboardHeader(columns: LeaderboardColumns) -> some View {
        HStack(spacing: 0) {
            Text("Pos")
                .frame(width: positionWidth, alignment: .leading)
            Color.clear.frame(width: headshotSize + 20)
            Text("Player")
                .frame(maxWidth: .infinity, alignment: .leading)
            if columns.hasMovement {
                Text("+/-")
                    .frame(width: 36, alignment: .trailing)
            }
            if columns.hasToday {
                Text("Today")
                    .frame(width: todayWidth, alignment: .trailing)
            }
            if columns.hasThru {
                Text("Thru")
                    .frame(width: thruWidth, alignment: .trailing)
            }
            Text("Score")
                .frame(width: scoreWidth, alignment: .trailing)
            if columns.hasRounds {
                Color.clear.frame(width: 24)
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private func cutDivider(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(color.opacity(0.4)).frame(height: 1)
            Text(text)
                .font(.caption2.bold())
                .foregroundColor(color.opacity(0.8))
            Rectangle().fill(color.opacity(0.4)).frame(height: 1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// While the cut round is being played: the first row outside ESPN's projected cut.
    private func projectedCutIndex(entries: [LeaderboardEntry]) -> (index: Int, score: Int)? {
        guard let info = game.golfCourseInfo, let cutScore = info.cutScore, let cutRound = info.cutRound,
              game.strStatus == "in", (game.golfCurrentRound ?? 1) <= cutRound else { return nil }
        guard let index = entries.firstIndex(where: { (GolfScore.toPar($0.score) ?? .min) > cutScore }), index > 0 else { return nil }
        return (index, cutScore)
    }

    @ViewBuilder
    private func leaderboardRow(entry: LeaderboardEntry, index: Int, label: String, columns: LeaderboardColumns, entries: [LeaderboardEntry]) -> some View {
        let isLeader = index == 0
        let isExpanded = expandedPlayers.contains(entry.name)
        let isFavPlayer = favorites.containsPlayer(entry.name)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    handleRowTap(entry: entry, entries: entries)
                } label: {
                    rowContent(entry: entry, label: label, isLeader: isLeader, isFavPlayer: isFavPlayer,
                               isExpanded: isExpanded, columns: columns)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibilityLabel(entry: entry, label: label, isFavorite: isFavPlayer))
                .accessibilityHint(entry.rounds.isEmpty ? "" : (isExpanded ? "Collapses round details" : "Shows round details"))
                .accessibilityAction(named: isFavPlayer ? "Remove from Favorites" : "Add to Favorites") {
                    toggleFavorite(entry.name)
                }
                favoriteButton(name: entry.name, isFavorite: isFavPlayer)
            }
            .opacity(entry.isCut == true ? 0.5 : 1.0)
            .background(comparingPlayerName == entry.name ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            .contextMenu {
                Button(isFavPlayer ? "Remove from Favorites" : "Add to Favorites",
                       systemImage: isFavPlayer ? "star.slash" : "star") {
                    toggleFavorite(entry.name)
                }
                if !entry.rounds.isEmpty {
                    Button("Compare", systemImage: "arrow.left.arrow.right") {
                        comparingPlayerName = entry.name
                    }
                }
            }

            inlineStats(entry: entry)

            if isExpanded && (!entry.rounds.isEmpty || entry.isOnCourse) {
                expandedRoundDetail(entry: entry)
            }
        }
    }

    private func handleRowTap(entry: LeaderboardEntry, entries: [LeaderboardEntry]) {
        if let comparing = comparingPlayerName {
            if comparing != entry.name, let playerA = entries.first(where: { $0.name == comparing }) {
                comparisonPair = (playerA, entry)
            }
        } else if !entry.rounds.isEmpty || entry.isOnCourse {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedPlayers.contains(entry.name) {
                    expandedPlayers.remove(entry.name)
                } else {
                    expandedPlayers.insert(entry.name)
                }
            }
        }
    }

    private func toggleFavorite(_ name: String) {
        if favorites.containsPlayer(name) {
            favorites.removePlayer(name)
        } else {
            favorites.addPlayer(name)
        }
    }

    /// One tap to follow a player — the long-press menu was the only way before.
    private func favoriteButton(name: String, isFavorite: Bool) -> some View {
        Button {
            toggleFavorite(name)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary.opacity(0.5))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove \(name) from favorites" : "Add \(name) to favorites")
        .sensoryFeedback(.selection, trigger: isFavorite)
    }

    @ViewBuilder
    private func rowContent(entry: LeaderboardEntry, label: String, isLeader: Bool, isFavPlayer: Bool,
                            isExpanded: Bool, columns: LeaderboardColumns) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .frame(width: positionWidth, alignment: .leading)
            HeadshotView(url: entry.headshot, size: headshotSize)
                .padding(.trailing, 2)
            Group {
                if let flagURL = entry.flagURL {
                    AsyncImage(url: URL(string: flagURL)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        EmptyView()
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 11)
            .padding(.trailing, 2)
            Text(entry.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            if entry.isCut == true {
                Text("CUT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.trailing, 2)
            }
            if columns.hasMovement {
                if let movement = entry.movement, movement != 0 {
                    HStack(spacing: 1) {
                        Image(systemName: movement < 0 ? "arrow.up" : "arrow.down")
                        Text("\(abs(movement))")
                    }
                    .font(.caption2)
                    .foregroundColor(movement < 0 ? .green : .red)
                    .frame(width: 36, alignment: .trailing)
                } else {
                    Color.clear.frame(width: 36)
                }
            }
            if columns.hasToday {
                Text(entry.today ?? "-")
                    .foregroundColor(entry.today == nil ? .secondary : GolfScoreStyle.color(toPar: entry.today))
                    .frame(width: todayWidth, alignment: .trailing)
            }
            if columns.hasThru {
                if entry.thruHole == nil, let tee = GolfScoreStyle.teeTimeText(entry) {
                    Text(tee)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: thruWidth, alignment: .trailing)
                } else {
                    Text(entry.thruHole ?? "-")
                        .frame(width: thruWidth, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
            }
            Text(entry.score)
                .foregroundColor(isLeader || isFavPlayer ? GolfScoreStyle.color(toPar: entry.score) : .secondary)
                .frame(width: scoreWidth, alignment: .trailing)
            if columns.hasRounds {
                if !entry.rounds.isEmpty || entry.isOnCourse {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                } else {
                    Color.clear.frame(width: 24)
                }
            }
        }
        .font(.caption)
        .fontWeight(isLeader || isFavPlayer ? .bold : .regular)
        .foregroundColor(isLeader || isFavPlayer ? .primary : .secondary)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// "Tied 3rd, Scottie Scheffler, 12 under, today 3 under, through 14."
    private func rowAccessibilityLabel(entry: LeaderboardEntry, label: String, isFavorite: Bool) -> String {
        var parts = [GolfScoreStyle.spokenPosition(label), entry.name]
        if isFavorite { parts.append("favorite") }
        parts.append(spokenToPar(entry.score))
        if let today = entry.today { parts.append("today \(spokenToPar(today))") }
        if let thru = entry.thruHole {
            parts.append(thru == "F" ? "finished round" : "through \(thru.replacingOccurrences(of: "*", with: ""))")
        } else if let tee = GolfScoreStyle.teeTimeText(entry) {
            parts.append("tees off \(tee)")
        }
        if entry.isCut == true { parts.append("missed the cut") }
        return parts.joined(separator: ", ")
    }

    private func spokenToPar(_ text: String) -> String {
        guard let value = GolfScore.toPar(text) else { return text }
        if value == 0 { return "even par" }
        return value < 0 ? "\(-value) under" : "\(value) over"
    }

    @ViewBuilder
    private func inlineStats(entry: LeaderboardEntry) -> some View {
        if let details = entry.roundDetails, !details.isEmpty {
            let totalBirdies = details.compactMap(\.stats?.birdies).reduce(0, +)
            let totalBogeys = details.compactMap(\.stats?.bogeys).reduce(0, +)
            let totalEagles = details.compactMap(\.stats?.eagles).reduce(0, +)
            let holesInOne = details.flatMap { $0.holeScores ?? [] }.filter { $0.score == 1 }.count
            HStack(spacing: 4) {
                Color.clear.frame(width: positionWidth + headshotSize + 20) // align under name
                if holesInOne > 0 {
                    Text("\(holesInOne) hole-in-one\(holesInOne > 1 ? "s" : "")")
                        .foregroundColor(.yellow)
                        .fontWeight(.bold)
                    Text("·").foregroundColor(.secondary)
                }
                if totalEagles > 0 {
                    Text("\(totalEagles) \(totalEagles == 1 ? "eagle" : "eagles")")
                        .foregroundColor(Color(red: 0, green: 0.5, blue: 0.7))
                    Text("·").foregroundColor(.secondary)
                }
                Text("\(totalBirdies) \(totalBirdies == 1 ? "birdie" : "birdies")")
                    .foregroundColor(.green)
                Text("·").foregroundColor(.secondary)
                Text("\(totalBogeys) \(totalBogeys == 1 ? "bogey" : "bogeys")")
                    .foregroundColor(.red)
                Spacer()
            }
            .font(.caption2)
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Expanded Round Detail

    @ViewBuilder
    private func expandedRoundDetail(entry: LeaderboardEntry) -> some View {
        let scores = entry.rounds.compactMap { Int($0) }
        let par = game.coursePar
        let hasEnrichment = entry.roundDetails != nil && !(entry.roundDetails?.isEmpty ?? true)

        VStack(spacing: 8) {
            // Sparkline (finished rounds only)
            if !entry.rounds.isEmpty {
                GolfScoreSparkline(rounds: entry.rounds, coursePar: par)
            }

            // Round pills: finished rounds, then the one being played.
            HStack(spacing: 6) {
                ForEach(Array(entry.rounds.enumerated()), id: \.offset) { rIndex, round in
                    let score = Int(round)
                    let isBest = score != nil && score == scores.min()
                    roundPill(title: "R\(rIndex + 1)", value: round,
                              detail: par.flatMap { p in score.map { GolfScore.format(toPar: $0 - p) } },
                              fill: roundPillColor(score: score, par: par), isBest: isBest)
                }
                if entry.isOnCourse, let today = entry.today {
                    roundPill(title: "R\(entry.rounds.count + 1)", value: today,
                              detail: entry.thruHole.map { "Thru \($0)" }, fill: Color.gray.opacity(0.35), isBest: false)
                        .accessibilityLabel("Round \(entry.rounds.count + 1) in progress, \(spokenToPar(today))")
                }
            }

            // Enriched per-round stats + hole grid (when available)
            if hasEnrichment, let details = entry.roundDetails {
                ForEach(details, id: \.roundNumber) { detail in
                    VStack(alignment: .leading, spacing: 4) {
                        // Round header with stats
                        if let stats = detail.stats {
                            HStack(spacing: 12) {
                                Text("R\(detail.roundNumber)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                if let fw = stats.fairways {
                                    statPill(label: "FW", value: fw)
                                }
                                if let gir = stats.greensInRegulation {
                                    statPill(label: "GIR", value: gir)
                                }
                                if let putts = stats.putts {
                                    statPill(label: "Putts", value: "\(putts)")
                                }
                                Spacer()
                                if let b = stats.birdies, b > 0 {
                                    scoringPill(count: b, label: "Birdie", color: .green)
                                }
                                if let e = stats.eagles, e > 0 {
                                    scoringPill(count: e, label: "Eagle", color: Color(red: 0, green: 0.5, blue: 0.7))
                                }
                                if let bog = stats.bogeys, bog > 0 {
                                    scoringPill(count: bog, label: "Bogey", color: .red)
                                }
                            }
                        }

                        // Hole-by-hole grid
                        if let holeScores = detail.holeScores, !holeScores.isEmpty {
                            GolfHoleGridView(holeScores: holeScores)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Summary row
            HStack(spacing: 0) {
                let total = scores.reduce(0, +)
                VStack(spacing: 1) {
                    Text("Total")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let p = par {
                        let totalDiff = total - (p * scores.count)
                        Text("\(total) (\(totalDiff == 0 ? "E" : (totalDiff > 0 ? "+\(totalDiff)" : "\(totalDiff)")))")
                            .font(.caption.bold())
                    } else {
                        Text("\(total)")
                            .font(.caption.bold())
                    }
                }
                .frame(maxWidth: .infinity)

                if let best = scores.min(), let bestIdx = scores.firstIndex(of: best) {
                    VStack(spacing: 1) {
                        Text("Best")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let p = par {
                            let diff = best - p
                            Text("R\(bestIdx + 1) (\(best), \(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")))")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        } else {
                            Text("R\(bestIdx + 1) (\(best))")
                                .font(.caption.bold())
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if !scores.isEmpty {
                    let total = scores.reduce(0, +)
                    let avg = Double(total) / Double(scores.count)
                    VStack(spacing: 1) {
                        Text("Avg")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f", avg))
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func roundPill(title: String, value: String, detail: String?, fill: Color, isBest: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.caption.bold())
            if let detail {
                Text(detail)
                    .font(.caption2)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isBest ? Color.white.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }

    private func inlineStatBadge(count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundColor(color)
        }
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption2.weight(.medium))
        }
    }

    private func scoringPill(count: Int, label: String, color: Color) -> some View {
        Text("\(count) \(count == 1 ? label : label + "s")")
            .font(.caption2.weight(.medium))
            .foregroundColor(color)
    }

    /// Par-relative color for round score pills
    private func roundPillColor(score: Int?, par: Int?) -> Color {
        guard let score, let par else { return Color.gray.opacity(0.4) }
        let diff = score - par
        switch diff {
        case ...(-3): return Color(red: 0.1, green: 0.65, blue: 0.2)
        case -2:      return Color(red: 0.3, green: 0.7, blue: 0.35)
        case -1:      return Color(red: 0.45, green: 0.72, blue: 0.45)
        case 0:       return Color.gray.opacity(0.5)
        case 1:       return Color(red: 0.85, green: 0.55, blue: 0.2)
        case 2:       return Color(red: 0.85, green: 0.35, blue: 0.15)
        default:      return Color(red: 0.8, green: 0.15, blue: 0.15)
        }
    }

    // MARK: - Scorecard
    @ViewBuilder
    private var scorecardSection: some View {
        let entries = game.resolvedLeaderboard
        let hasDetails = entries.contains(where: { $0.roundDetails != nil && !($0.roundDetails?.isEmpty ?? true) })
        if hasDetails {
            GolfScorecardView(
                entries: entries,
                coursePar: game.coursePar,
                holePars: game.golfCourseInfo?.holePars
            )
        }
    }

    // MARK: - Course Difficulty
    @ViewBuilder
    private var courseDifficultySection: some View {
        let entries = game.resolvedLeaderboard
        if let holePars = game.golfCourseInfo?.holePars, !holePars.isEmpty {
            GolfCourseDifficultyView(
                entries: entries,
                holePars: holePars
            )
        }
    }

    // MARK: - Round Heatmap
    @ViewBuilder
    private var roundHeatmapSection: some View {
        let entries = game.resolvedLeaderboard
        // Worth a grid once there's more than one round to compare.
        let hasRounds = entries.contains(where: { $0.rounds.count >= 2 })
        if hasRounds {
            RoundHeatmapView(entries: entries, coursePar: game.coursePar)
        }
    }

    #if os(iOS)
    // MARK: - Calendar Event
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = game.strHomeTeam
        event.location = game.golfCourseInfo?.courseName ?? game.venueName
        if let gameDate = game.standardDate {
            // A tournament runs Thursday to Sunday: one all-day event across the span.
            // ESPN's dates are day markers (midnight Eastern, as UTC), so read their UTC
            // calendar day rather than shifting them into the viewer's zone.
            let end = game.endDateParsed.map { max($0, gameDate) } ?? gameDate.addingTimeInterval(3 * 24 * 3600)
            event.isAllDay = true
            event.startDate = Self.localDay(matching: gameDate)
            event.endDate = Self.localDay(matching: end).addingTimeInterval(12 * 3600)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }

    /// Midnight, in the viewer's calendar, of `date`'s day as written in UTC.
    private static func localDay(matching date: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: parts) ?? date
    }
    #endif
}
