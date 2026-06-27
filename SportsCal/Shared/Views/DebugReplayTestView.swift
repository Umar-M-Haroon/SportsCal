//
//  DebugReplayTestView.swift
//  SportsCal (iOS)
//
//  Developer-only dashboard for "replay a game as live": pick a completed team-sport
//  game and stream its recorded play-by-play back through the live pipeline so the live
//  UI and Live Activities behave as if the game were happening now.
//
//  Requires the app to be pointed at a local/dev server (Settings → Developer → server
//  environment) — the `/replay` endpoint is dev-gated. Only games currently in the
//  schedule can be replayed, since the game "shell" is supplied by the client.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

struct DebugReplayTestView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var appStorage

    @State private var speed: Double = 8.0
    @State private var filterText: String = ""
    /// Per-game play-by-play availability, keyed by event ID. Probed lazily as rows appear.
    @State private var availability: [String: RowAvailability] = [:]

    /// Cap on how many completed games we probe/show, to bound network usage.
    private let gameLimit = 40

    private enum RowAvailability {
        case checking
        case available(GameViewModel.ReplayAvailability)
        case unavailable
    }

    private let speedOptions: [(label: String, value: Double)] = [
        ("1×", 1), ("4×", 4), ("8×", 8), ("20×", 20), ("Instant", 1000)
    ]

    var body: some View {
        Form {
            // MARK: - Replay status
            Section("Replay") {
                Picker("Speed (plays/sec)", selection: $speed) {
                    ForEach(speedOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isReplaying)

                if let phase = viewModel.replayPhase {
                    statusBlock(phase: phase)
                }

                if viewModel.isReplaying, let game = viewModel.replayingGame {
                    LabeledContent("Game") {
                        Text("\(game.strHomeTeam) vs \(game.strAwayTeam)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Stop Replay", role: .destructive) {
                        viewModel.stopReplay()
                    }
                    #if canImport(ActivityKit) && os(iOS)
                    Button("Start Live Activity for Replay") {
                        startLiveActivity(for: game)
                    }
                    #endif
                } else if viewModel.replayPhase != nil {
                    Button("Dismiss") { viewModel.clearReplayStatus() }
                } else {
                    Text("Not replaying")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Completed games to replay
            Section {
                TextField("Filter by team", text: $filterText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                let games = replayableGames
                if games.isEmpty {
                    Text("No completed team-sport games in the current schedule.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(games, id: \.id) { game in
                        gameRow(game)
                    }
                }
            } header: {
                Text("Completed Games")
            } footer: {
                Text("NBA / NFL / NHL / MLB / soccer only. Only games with play-by-play can be replayed; the rest are disabled. Replay needs a local/dev server.")
            }

            // MARK: - Live Activities
            #if canImport(ActivityKit) && os(iOS)
            Section("Live Activities") {
                let activities = Activity<LiveSportActivityAttributes>.activities
                Text("Active: \(activities.count)")
                ForEach(Array(activities), id: \.id) { activity in
                    VStack(alignment: .leading) {
                        Text("\(activity.attributes.homeTeam) vs \(activity.attributes.awayTeam)")
                            .font(.subheadline)
                        Text("Event: \(activity.attributes.eventID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #endif

            // MARK: - Event Log
            Section("Event Log") {
                let logger = AutoFollowLogger.shared
                if logger.entries.isEmpty {
                    Text("No events yet").foregroundStyle(.secondary)
                } else {
                    Button("Clear Log") { logger.clear() }
                    ForEach(logger.entries.reversed()) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.level.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message).font(.caption)
                                Text(entry.date.formatted(.dateTime.hour().minute().second()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: - Instructions
            Section("How to Test Replay") {
                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(step: 1, text: "Point the app at a local/dev server (Developer → server)")
                    instructionRow(step: 2, text: "Pick a completed game and tap Replay")
                    instructionRow(step: 3, text: "Watch it appear in the Live section with advancing score/clock")
                    instructionRow(step: 4, text: "Tap Start Live Activity to drive the lock screen / Dynamic Island")
                    instructionRow(step: 5, text: "Tap Stop Replay to return to normal live")
                }
                .font(.caption)
            }
        }
        .navigationTitle("Replay Testing")
    }

    // MARK: - Status

    @ViewBuilder
    private func statusBlock(phase: GameViewModel.ReplayPhase) -> some View {
        HStack(spacing: 8) {
            statusDot(phase)
            Text(phase.rawValue)
                .font(.subheadline.bold())
            Spacer()
            if let source = viewModel.replaySource {
                Text(source.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(source == .production ? Color.orange : Color.blue,
                                in: Capsule())
            }
        }

        if viewModel.replayTotalPlays > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(
                    value: Double(viewModel.replayFramesReceived),
                    total: Double(viewModel.replayTotalPlays)
                )
                Text("\(viewModel.replayFramesReceived) / \(viewModel.replayTotalPlays) frames")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } else if phase == .fetching {
            HStack(spacing: 6) {
                ProgressView()
                Text("Fetching play-by-play…").font(.caption).foregroundStyle(.secondary)
            }
        }

        // Diagnostic: where the streamed game landed. `all-live` is unfiltered; `live`
        // respects the per-sport toggles and is what the Today section renders. If
        // all-live > 0 but live == 0, the game's sport is toggled off.
        Text("live: \(viewModel.liveEvents.count) · all-live: \(viewModel.allLiveEvents.count)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
    }

    private func statusDot(_ phase: GameViewModel.ReplayPhase) -> some View {
        let color: Color = {
            switch phase {
            case .fetching: return .yellow
            case .streaming: return .green
            case .ended: return .gray
            case .failed: return .red
            }
        }()
        return Circle().fill(color).frame(width: 10, height: 10)
    }

    // MARK: - Game row

    @ViewBuilder
    private func gameRow(_ game: Game) -> some View {
        let state = game.idEvent.flatMap { availability[$0] }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(game.strHomeTeam) vs \(game.strAwayTeam)")
                    .font(.subheadline.bold())
                Spacer()
                if let h = game.intHomeScore, let a = game.intAwayScore {
                    Text("\(h)–\(a)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                if let league = game.strLeague {
                    Text(league)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let date = game.standardDate {
                    Text(date.formatted(.dateTime.month().day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            availabilityFooter(game: game, state: state)
        }
        .padding(.vertical, 2)
        .task { await probeAvailability(game) }
    }

    @ViewBuilder
    private func availabilityFooter(game: Game, state: RowAvailability?) -> some View {
        switch state {
        case .none, .checking:
            HStack(spacing: 6) {
                ProgressView()
                Text("Checking play-by-play…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .available(let avail):
            HStack(spacing: 8) {
                Button("Replay") {
                    viewModel.startReplay(game: game, speed: speed, availability: avail)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isReplaying)

                Text("\(avail.plays.count) plays · \(avail.source.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            Label("No play-by-play", systemImage: "slash.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    /// Completed team-sport games from the loaded schedule, newest first, filtered by text,
    /// capped at `gameLimit` to bound per-row availability probing.
    private var replayableGames: [Game] {
        let all = viewModel.totalGames ?? []
        let filtered = all.filter { game in
            guard isCompletedTeamSport(game), game.idEvent?.isEmpty == false else { return false }
            guard !filterText.isEmpty else { return true }
            return game.strHomeTeam.localizedCaseInsensitiveContains(filterText)
                || game.strAwayTeam.localizedCaseInsensitiveContains(filterText)
        }
        return Array(
            filtered.sorted { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }
                .prefix(gameLimit)
        )
    }

    /// Probes a game's play-by-play availability once, caching the result by event ID.
    private func probeAvailability(_ game: Game) async {
        guard let id = game.idEvent, availability[id] == nil else { return }
        availability[id] = .checking
        let result = await viewModel.checkReplayAvailability(for: game)
        availability[id] = result.map { .available($0) } ?? .unavailable
    }

    private func isCompletedTeamSport(_ game: Game) -> Bool {
        guard game.isCompleted == true || game.strStatus == "post" else { return false }
        guard let idLeague = game.idLeague, let leagueInt = Int(idLeague),
              let league = Leagues(rawValue: leagueInt) else { return false }
        return league.isBasketball || league == .nfl || league == .nhl || league == .mlb || league.isSoccer
    }

    #if canImport(ActivityKit) && os(iOS)
    private func startLiveActivity(for game: Game) {
        guard let teams = viewModel.getTeams(for: game) else {
            AutoFollowLogger.shared.log("Replay: couldn't resolve teams for Live Activity", level: .error)
            return
        }
        viewModel.requestActivity(game: game, homeTeam: teams.home, awayTeam: teams.away)
        AutoFollowLogger.shared.log("Replay: requested Live Activity for \(game.strHomeTeam) vs \(game.strAwayTeam)", level: .info)
    }
    #endif

    private func instructionRow(step: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step).")
                .fontWeight(.bold)
                .frame(width: 20, alignment: .trailing)
            Text(text)
        }
    }
}
