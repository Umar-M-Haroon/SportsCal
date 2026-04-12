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
    let game: Game

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    @State private var expandedPlayers: Set<Int> = []
    @State private var comparingPlayerIndex: Int?
    @State private var comparisonPair: (LeaderboardEntry, LeaderboardEntry)?

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
                scorecardSection
                courseDifficultySection
            }
            .padding()
        }
        .navigationTitle(league?.leagueName ?? "Tournament")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            set: { if !$0 { comparisonPair = nil; comparingPlayerIndex = nil } }
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

            if let progress = game.strProgress {
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
    @ViewBuilder
    private var roundProgressBar: some View {
        let entries = game.resolvedLeaderboard
        let maxRounds = entries.map(\.rounds.count).max() ?? 0
        if maxRounds > 0 {
            let currentRound = detectCurrentRound(entries: entries, maxRounds: maxRounds)
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(0..<maxRounds, id: \.self) { i in
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
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func detectCurrentRound(entries: [LeaderboardEntry], maxRounds: Int) -> Int {
        guard let leader = entries.first else { return 0 }
        let leaderRounds = leader.rounds.count
        if leader.thruHole != nil && leader.thruHole != "F" {
            return max(0, leaderRounds - 1)
        }
        return max(0, leaderRounds - 1)
    }

    private func roundColor(index: Int, current: Int) -> Color {
        if index < current { return .green }
        if index == current { return .accentColor }
        return Color.gray.opacity(0.4)
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
                let hasRounds = entries.contains(where: { !$0.rounds.isEmpty })
                let hasThru = entries.contains(where: { $0.thruHole != nil })
                let hasMovement = entries.contains(where: { $0.movement != nil && $0.movement != 0 })
                let hasTeeTime = entries.contains(where: { $0.teeTime != nil })
                let cutIndex = entries.firstIndex(where: { $0.isCut == true })

                // Header row
                HStack(spacing: 0) {
                    Text("Pos")
                        .frame(width: 32, alignment: .leading)
                    // Headshot + flag column spacer
                    Color.clear.frame(width: 48)
                    Text("Player")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hasMovement {
                        Text("+/-")
                            .frame(width: 36, alignment: .trailing)
                    }
                    if hasThru || hasTeeTime {
                        Text("Thru")
                            .frame(width: 48, alignment: .trailing)
                    }
                    Text("Score")
                        .frame(width: 50, alignment: .trailing)
                    if hasRounds {
                        Color.clear.frame(width: 24)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                // Comparison mode banner
                if comparingPlayerIndex != nil {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Tap another player to compare")
                            .font(.caption)
                        Spacer()
                        Button("Cancel") {
                            comparingPlayerIndex = nil
                        }
                        .font(.caption.bold())
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }

                // Player rows
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    let isExpanded = expandedPlayers.contains(index)
                    let isFavPlayer = favorites.containsPlayer(entry.name)

                    // Cut line divider
                    if let cutIdx = cutIndex, cutIdx == index, cutIdx > 0 {
                        HStack(spacing: 8) {
                            Rectangle().fill(Color.red.opacity(0.4)).frame(height: 1)
                            Text("CUT")
                                .font(.caption2.bold())
                                .foregroundColor(.red.opacity(0.7))
                            Rectangle().fill(Color.red.opacity(0.4)).frame(height: 1)
                        }
                        .padding(.vertical, 4)
                    }

                    VStack(spacing: 0) {
                        Button {
                            if comparingPlayerIndex != nil {
                                // In comparison mode — select second player
                                if comparingPlayerIndex != index {
                                    let playerA = entries[comparingPlayerIndex!]
                                    comparisonPair = (playerA, entry)
                                }
                            } else if !entry.rounds.isEmpty {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedPlayers.contains(index) {
                                        expandedPlayers.remove(index)
                                    } else {
                                        expandedPlayers.insert(index)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 0) {
                                Text("\(entry.position)")
                                    .frame(width: 32, alignment: .leading)
                                HeadshotView(url: entry.headshot, size: 28)
                                    .padding(.trailing, 2)
                                // Country flag
                                if let flagURL = entry.flagURL {
                                    AsyncImage(url: URL(string: flagURL)) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        EmptyView()
                                    }
                                    .frame(width: 16, height: 11)
                                    .padding(.trailing, 2)
                                }
                                // Favorite star
                                if isFavPlayer {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.yellow)
                                        .padding(.trailing, 2)
                                }
                                Text(entry.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                // CUT badge
                                if entry.isCut == true {
                                    Text("CUT")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red.opacity(0.8))
                                        .clipShape(Capsule())
                                        .padding(.trailing, 2)
                                }
                                // Movement indicator
                                if hasMovement {
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
                                // Tee time or thru hole
                                if let teeTime = entry.teeTime, entry.thruHole == nil {
                                    Text(teeTime)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .frame(width: 48, alignment: .trailing)
                                } else if hasThru || hasTeeTime {
                                    Text(entry.thruHole ?? "-")
                                        .frame(width: 48, alignment: .trailing)
                                        .foregroundColor(.secondary)
                                }
                                Text(entry.score)
                                    .frame(width: 50, alignment: .trailing)
                                if hasRounds && !entry.rounds.isEmpty {
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24)
                                } else if hasRounds {
                                    Color.clear.frame(width: 24)
                                }
                            }
                            .font(.caption)
                            .fontWeight(isLeader || isFavPlayer ? .bold : .regular)
                            .foregroundColor(isLeader || isFavPlayer ? .primary : .secondary)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(entry.isCut == true ? 0.5 : 1.0)
                        .background(comparingPlayerIndex == index ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                        .contextMenu {
                            if favorites.containsPlayer(entry.name) {
                                Button("Remove from Favorites", systemImage: "star.slash") {
                                    favorites.removePlayer(entry.name)
                                }
                            } else {
                                Button("Add to Favorites", systemImage: "star") {
                                    favorites.addPlayer(entry.name)
                                }
                            }
                            if !entry.rounds.isEmpty {
                                Button("Compare", systemImage: "arrow.left.arrow.right") {
                                    comparingPlayerIndex = index
                                }
                            }
                        }

                        // Inline stats (visible without expanding)
                        if let details = entry.roundDetails, !details.isEmpty {
                            let totalBirdies = details.compactMap(\.stats?.birdies).reduce(0, +)
                            let totalBogeys = details.compactMap(\.stats?.bogeys).reduce(0, +)
                            let totalEagles = details.compactMap(\.stats?.eagles).reduce(0, +)
                            let holesInOne = details.flatMap { $0.holeScores ?? [] }.filter { $0.score == 1 }.count
                            HStack(spacing: 4) {
                                Color.clear.frame(width: 62) // align under name
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
                            .font(.system(size: 9))
                            .padding(.bottom, 2)
                        }

                        // Expanded round details
                        if isExpanded && !entry.rounds.isEmpty {
                            expandedRoundDetail(entry: entry)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Expanded Round Detail

    @ViewBuilder
    private func expandedRoundDetail(entry: LeaderboardEntry) -> some View {
        let scores = entry.rounds.compactMap { Int($0) }
        let par = game.coursePar
        let hasEnrichment = entry.roundDetails != nil && !(entry.roundDetails?.isEmpty ?? true)

        VStack(spacing: 8) {
            // Sparkline
            GolfScoreSparkline(rounds: entry.rounds, coursePar: par)

            // Round pills
            HStack(spacing: 6) {
                ForEach(Array(entry.rounds.enumerated()), id: \.offset) { rIndex, round in
                    let score = Int(round)
                    let isBest = score != nil && score == scores.min()

                    VStack(spacing: 2) {
                        Text("R\(rIndex + 1)")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                        Text(round)
                            .font(.caption.bold())
                        if let p = par, let s = score {
                            let diff = s - p
                            Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                                .font(.system(size: 9))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(roundPillColor(score: score, par: par))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isBest ? Color.white.opacity(0.6) : Color.clear, lineWidth: 1.5)
                    )
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
                        .font(.system(size: 9))
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
                            .font(.system(size: 9))
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
                            .font(.system(size: 9))
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

    private func inlineStatBadge(count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(color)
        }
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .medium))
        }
    }

    private func scoringPill(count: Int, label: String, color: Color) -> some View {
        Text("\(count) \(count == 1 ? label : label + "s")")
            .font(.system(size: 8, weight: .medium))
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
        let hasRounds = entries.contains(where: { !$0.rounds.isEmpty })
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
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 4)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}
