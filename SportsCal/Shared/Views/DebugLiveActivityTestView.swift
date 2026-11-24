//
//  DebugLiveActivityTestView.swift
//  SportsCal (iOS)
//
//  Dedicated test dashboard for the auto-follow → push-to-start live activity flow.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

struct DebugLiveActivityTestView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var appStorage
    @State private var selectedSport: SportType = .basketball
    @State private var serverStatus: NetworkHandler.DeviceRegistrationStatus?
    @State private var serverStatusLoading = false
    @State private var serverStatusError: String?

    var body: some View {
        Form {
            // MARK: - Create Fake Game
            Section("Create Fake Game") {
                Picker("Sport", selection: $selectedSport) {
                    ForEach(SportType.allCases, id: \.self) { sport in
                        Text(sport.displayName).tag(sport)
                    }
                }

                Button("Create Fake Upcoming Game") {
                    viewModel.injectFakeUpcomingGame(sport: selectedSport)
                }
            }

            // MARK: - Fake Games
            if !viewModel.debugFakeGames.isEmpty {
                Section("Fake Games") {
                    ForEach(viewModel.debugFakeGames, id: \.id) { game in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(game.strHomeTeam)
                                    .font(.subheadline.bold())
                                Text("vs")
                                    .foregroundColor(.secondary)
                                Text(game.strAwayTeam)
                                    .font(.subheadline.bold())
                            }
                            HStack(spacing: 6) {
                                Text(game.idEvent ?? "")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                if let eventID = game.idEvent, appStorage.isAutoFollowing(eventID) {
                                    Text("AUTO-FOLLOW")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 4))
                                }
                            }

                            if let eventID = game.idEvent, !appStorage.isAutoFollowing(eventID) {
                                Button("Auto-Follow") {
                                    appStorage.addAutoFollow(eventID)
                                    #if os(iOS)
                    viewModel.sendAutoFollowRegistration()
                    #endif
                                    AutoFollowLogger.shared.log("Auto-follow added: \(eventID)")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // MARK: - Auto-Follow State
            Section("Auto-Follow State") {
                Text("Auto-follow event IDs: \(appStorage.autoFollowEventIDs.count)")
                if !appStorage.autoFollowEventIDs.isEmpty {
                    ForEach(Array(appStorage.autoFollowEventIDs), id: \.self) { id in
                        Text(id)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                Toggle("Auto-follow favorites", isOn: Bindable(appStorage).autoFollowFavorites)
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
                            .foregroundColor(.secondary)
                    }
                }
            }
            #endif

            // MARK: - Pipeline Checklist
            Section("Pipeline Checklist") {
                pipelineRow(step: "Push-to-start token obtained", ok: viewModel.currentPushToStartToken != nil, detail: viewModel.currentPushToStartToken.map { String($0.prefix(12)) + "..." } ?? "No token")
                pipelineRow(step: "Token registered with server", ok: serverStatus?.registered == true, detail: serverStatus?.registered == true ? "Registered" : "Not registered")
                pipelineRow(step: "Event IDs sent to server", ok: (serverStatus?.eventIDs.count ?? 0) > 0, detail: "\(serverStatus?.eventIDs.count ?? 0) event(s)")
                pipelineRow(step: "Server has APNS ready", ok: serverStatus?.apnsConfigured == true, detail: serverStatus?.apnsConfigured == true ? "Configured" : "Not configured")
                pipelineRow(step: "Notification delivered", ok: (serverStatus?.sentNotifications.count ?? 0) > 0, detail: "\(serverStatus?.sentNotifications.count ?? 0) sent")
                #if canImport(ActivityKit) && os(iOS)
                // Distinct from "Token registered" above: that's the push-to-start
                // install (starts activities). THIS verifies the per-activity update
                // token the server pushes live score updates to. A running activity
                // missing here = a Lock Screen that won't advance server-side.
                activityUpdateTokenRow()
                #endif

                Button("Refresh Pipeline Status") {
                    fetchServerStatus()
                }
                .disabled(viewModel.currentPushToStartToken == nil)

                if serverStatusLoading {
                    ProgressView("Checking server...")
                } else if let error = serverStatusError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // MARK: - Server Registration Details
            if let status = serverStatus, status.registered {
                Section("Server Registration Details") {
                    LabeledContent("APNS Configured", value: status.apnsConfigured ? "Yes" : "No")
                    if !status.favorites.isEmpty {
                        LabeledContent("Favorites") {
                            Text(status.favorites.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !status.eventIDs.isEmpty {
                        LabeledContent("Event IDs") {
                            VStack(alignment: .trailing) {
                                ForEach(status.eventIDs, id: \.self) { id in
                                    Text(id).font(.caption.monospaced())
                                }
                            }
                        }
                    }
                    LabeledContent("Sent Notifications", value: "\(status.sentNotifications.count)")
                }
            }

            // MARK: - Event Log
            Section("Event Log") {
                let logger = AutoFollowLogger.shared
                if logger.entries.isEmpty {
                    Text("No events yet")
                        .foregroundColor(.secondary)
                } else {
                    Button("Clear Log") { logger.clear() }
                    ForEach(logger.entries.reversed()) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.level.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .font(.caption)
                                Text(entry.date.formatted(.dateTime.hour().minute().second()))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: - Cleanup
            Section {
                Button("Clear All Debug Games", role: .destructive) {
                    viewModel.clearDebugFakeGames()
                }
            }

            // MARK: - Test Instructions
            Section("How to Test Push-to-Start") {
                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(step: 1, text: "Create a fake game and tap Auto-Follow")
                    instructionRow(step: 2, text: "Refresh Pipeline — all steps should be green")
                    instructionRow(step: 3, text: "Force-quit the app")
                    instructionRow(step: 4, text: "Open admin dashboard > Debug Tools")
                    instructionRow(step: 5, text: "Click the event ID, then Send Push-to-Start")
                    instructionRow(step: 6, text: "Live Activity appears on lock screen")
                }
                .font(.caption)
            }
        }
        .navigationTitle("Live Activity Testing")
    }

    // MARK: - Helpers

    #if canImport(ActivityKit) && os(iOS)
    /// Cross-checks each running activity's event ID against the per-activity
    /// update-token registrations the server reports. Red when an activity is live
    /// on the device but the server has no update token for it — the exact state
    /// that leaves a Lock Screen activity frozen at its start value.
    @ViewBuilder
    private func activityUpdateTokenRow() -> some View {
        let runningEventIDs = Set(Activity<LiveSportActivityAttributes>.activities.map { $0.attributes.eventID })
        let registeredUpdateIDs = Set(serverStatus?.activityUpdateEventIDs ?? [])
        let covered = runningEventIDs.intersection(registeredUpdateIDs)
        pipelineRow(
            step: "Activity update token registered",
            ok: !runningEventIDs.isEmpty && covered.count == runningEventIDs.count,
            detail: runningEventIDs.isEmpty ? "No running activities" : "\(covered.count)/\(runningEventIDs.count) on server"
        )
    }
    #endif

    private func pipelineRow(step: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(step)
                .font(.subheadline)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fetchServerStatus() {
        guard let token = viewModel.currentPushToStartToken else { return }
        let prefix = String(token.prefix(32))
        serverStatusLoading = true
        serverStatusError = nil
        Task {
            do {
                let status = try await NetworkHandler.getDeviceRegistrationStatus(tokenPrefix: prefix)
                serverStatus = status
            } catch {
                serverStatusError = error.localizedDescription
            }
            serverStatusLoading = false
        }
    }

    private func instructionRow(step: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step).")
                .fontWeight(.bold)
                .frame(width: 20, alignment: .trailing)
            Text(text)
        }
    }
}

#if canImport(ActivityKit) && os(iOS)
/// Starts a real, local Live Activity from a canned game and drives it by hand, so
/// the Lock Screen, Dynamic Island and StandBy looks can be tried on a device.
/// "Team colours" off starts it without colours: the look before the colour pass.
struct LiveActivityPlaygroundView: View {
    enum Scenario: String, CaseIterable, Identifiable {
        case nba = "NBA", nfl = "NFL", mlb = "MLB", nhl = "NHL", soccer = "Soccer"
        var id: String { rawValue }

        var attributes: (home: String, away: String, homeShort: String, awayShort: String, homeHex: String, awayHex: String) {
            switch self {
            case .nba: return ("Boston Celtics", "Los Angeles Lakers", "BOS", "LAL", "007A33", "552583")
            case .nfl: return ("Kansas City Chiefs", "Buffalo Bills", "KC", "BUF", "E31837", "00338D")
            case .mlb: return ("Cleveland Guardians", "Detroit Tigers", "CLE", "DET", "E31937", "0C2340")
            case .nhl: return ("Vegas Golden Knights", "Edmonton Oilers", "VGK", "EDM", "B4975A", "041E42")
            case .soccer: return ("Arsenal", "Chelsea", "ARS", "CHE", "EF0107", "034694")
            }
        }

        /// ESPN logo URLs: starting the playground fetches these exactly as a
        /// push-started activity does (see `cacheBadgesForActivity`).
        var logos: (home: String, away: String) {
            let base = "https://a.espncdn.com/i/teamlogos"
            switch self {
            case .nba: return ("\(base)/nba/500/bos.png", "\(base)/nba/500/lal.png")
            case .nfl: return ("\(base)/nfl/500/kc.png", "\(base)/nfl/500/buf.png")
            case .mlb: return ("\(base)/mlb/500/cle.png", "\(base)/mlb/500/det.png")
            case .nhl: return ("\(base)/nhl/500/vgk.png", "\(base)/nhl/500/edm.png")
            case .soccer: return ("\(base)/soccer/500/359.png", "\(base)/soccer/500/363.png")
            }
        }

        var points: Int {
            switch self {
            case .nba: return 2
            case .nfl: return 7
            default: return 1
            }
        }

        /// Progress that makes the start state a clutch moment; nil where it already is
        /// one (MLB, NFL) or the sport has none (soccer).
        var clutchProgress: String? {
            switch self {
            case .nba: return "1:48 - 4th"
            case .nhl: return "1:52 - 3rd"
            case .nfl: return "1:55 - 4th"
            case .mlb, .soccer: return nil
            }
        }

        var startState: LiveSportActivityAttributes.ContentState {
            switch self {
            case .nba:
                return .init(homeScore: 108, awayScore: 106, status: "in", progress: "4th 2:14",
                             lastPlay: "Tatum makes 18-foot pullup jumper")
            case .nfl:
                return .init(homeScore: 20, awayScore: 17, status: "in", progress: "4th 2:31", lastPlay: nil,
                             situation: LiveActivitySituation(downDistance: "3rd & 4 at KC 12", possession: .away, redZone: true,
                                                              homeWinPct: 58, homeTimeouts: 2, awayTimeouts: 1))
            case .mlb:
                return .init(homeScore: 3, awayScore: 5, status: "in", progress: "Bot 9th",
                             lastPlay: "Kwan singled to left.",
                             situation: LiveActivitySituation(outs: 1, bases: 3, homeWinPct: 21))
            case .nhl:
                return .init(homeScore: 2, awayScore: 2, status: "in", progress: "5:40 - 3rd", lastPlay: "Goal by Eichel (PP)")
            case .soccer:
                return .init(homeScore: 1, awayScore: 1, status: "in", progress: "67'",
                             soccer: LiveActivitySoccer(awayRedCards: 1, lastGoal: "Palmer 58'", lastGoalSide: .away))
            }
        }
    }

    @State private var scenario: Scenario = .nfl
    @State private var teamColors = true
    @State private var activity: Activity<LiveSportActivityAttributes>?
    @State private var state = Scenario.nfl.startState
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Picker("Game", selection: $scenario) {
                    ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Team colours", isOn: $teamColors)
                Button(activity == nil ? "Start Live Activity" : "Restart Live Activity") { start() }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            } footer: {
                Text("Lock the phone to see the Lock Screen card; go home for the Dynamic Island (long-press it to expand). Turn Team colours off and restart to see the look before the colour pass. Picks apply on restart.")
            }

            if activity != nil {
                Section("Score") {
                    HStack {
                        Button("+ \(scenario.attributes.awayShort)") { score(home: false) }
                        Spacer()
                        Text("\(scenario.attributes.awayShort) \(state.awayScore) – \(state.homeScore) \(scenario.attributes.homeShort)")
                            .monospacedDigit().foregroundStyle(.secondary)
                        Spacer()
                        Button("+ \(scenario.attributes.homeShort)") { score(home: true) }
                    }
                    .buttonStyle(.bordered)
                    if state.situation?.homeWinPct != nil {
                        Button("Swing win probability") {
                            let current = state.situation?.homeWinPct ?? 50
                            state.situation?.homeWinPct = current >= 50 ? 24 : 81
                            push()
                        }
                    }
                }
                Section("Game state") {
                    Button("Live") { setProgress(scenario.startState.progress, status: "in") }
                    Button(scenario == .nhl ? "Intermission" : "Halftime") {
                        setProgress(scenario == .nhl ? "End of 2nd" : (scenario == .soccer ? "HT" : "Halftime"), status: "in")
                    }
                    // Close and late (amber): the 4th / 3rd under two minutes; MLB and
                    // NFL start in a clutch spot already (tying run on, red zone).
                    if let clutch = scenario.clutchProgress {
                        Button("Clutch") { setProgress(clutch, status: "in") }
                    }
                    Button(scenario == .mlb ? "Rain delay" : "End of period") {
                        setProgress(scenario == .mlb ? "Rain Delay" : (scenario == .nhl ? "0:00 - 2nd" : "End of 3rd"), status: "in")
                    }
                    Button("Final") { setProgress(scenario == .nba ? "Final/OT" : "Final", status: "post") }
                }
                Section {
                    Button("End Live Activity", role: .destructive) { end() }
                }
            }
        }
        .navigationTitle("Live Activity Playground")
        .onChange(of: scenario) { state = scenario.startState }
    }

    private func start() {
        Task { @MainActor in
            if let activity { await activity.end(nil, dismissalPolicy: .immediate) }
            let info = scenario.attributes
            let attributes = LiveSportActivityAttributes(
                homeTeam: info.home, awayTeam: info.away, eventID: "playground-\(scenario.rawValue)",
                homeTeamShort: info.homeShort, awayTeamShort: info.awayShort,
                displaysHomeFirst: scenario == .soccer ? true : nil,
                homeColorHex: teamColors ? info.homeHex : nil,
                awayColorHex: teamColors ? info.awayHex : nil,
                homeBadgeURL: scenario.logos.home,
                awayBadgeURL: scenario.logos.away
            )
            state = scenario.startState
            do {
                activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
                error = nil
            } catch {
                activity = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func score(home: Bool) {
        if home { state.homeScore += scenario.points } else { state.awayScore += scenario.points }
        if scenario == .soccer {
            state.soccer?.lastGoal = home ? "Saka \(70 + state.homeScore)'" : "Palmer \(70 + state.awayScore)'"
            state.soccer?.lastGoalSide = home ? .home : .away
        }
        push()
    }

    private func setProgress(_ progress: String?, status: String) {
        state.progress = progress
        state.status = status
        push()
    }

    private func push() {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    private func end() {
        guard let activity else { return }
        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
}
#endif
