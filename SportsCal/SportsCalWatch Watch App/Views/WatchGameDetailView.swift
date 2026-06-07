//
//  WatchGameDetailView.swift
//  SportsCalWatch
//
//  Full detail view for team sports on Watch.
//  Shows scores, linescore table, last play, and stat leaders.
//  Sets NSUserActivity for Handoff to iPhone.
//

import SwiftUI
import SportsCalModel
import WatchKit

struct WatchGameDetailView: View {
    let game: Game
    let teams: [Team]

    @State private var isTracking = false
    @State private var crownOffset: Double = 0
    @State private var plays: [Play] = []
    @State private var playsAvailable = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Score Header
                scoreHeader

                // Double-tap hint (Series 9 / Ultra 2)
                if isLive {
                    HStack(spacing: 4) {
                        Image(systemName: isTracking ? "checkmark.circle.fill" : "hand.tap")
                            .font(.system(size: 10))
                        Text(isTracking ? "Tracking" : "Double-tap to track")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(isTracking ? .green : .secondary)
                }

                // Linescore with Digital Crown scrubbing
                if let homeLine = game.homeLinescores, let awayLine = game.awayLinescores,
                   !homeLine.isEmpty {
                    linescoreView(homeLine: homeLine, awayLine: awayLine)
                        .focusable()
                        .digitalCrownRotation(
                            $crownOffset,
                            from: 0,
                            through: Double(max(homeLine.count, awayLine.count) - 1),
                            by: 1,
                            sensitivity: .low
                        )
                }

                // Last Play
                if let lastPlay = game.lastPlay, !lastPlay.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LAST PLAY")
                            .font(.system(size: 10, design: .monospaced).weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(WatchTokens.inkFaint)
                        Text(lastPlay)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(WatchTokens.ink)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Play-by-Play (latest 10 plays for NBA/NFL/NHL/MLB)
                if supportsPlayByPlay, !plays.isEmpty {
                    playByPlayCompact
                }

                // Stat Leaders
                if let homeLeaders = game.homeLeaders, let awayLeaders = game.awayLeaders {
                    leadersView(homeLeaders: homeLeaders, awayLeaders: awayLeaders)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(statusTitle)
        .toolbar {
            if isLive {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        toggleTracking()
                    } label: {
                        Image(systemName: isTracking ? "bell.slash" : "bell")
                    }
                    .handGestureShortcut(.primaryAction)
                }
            }
        }
        .userActivity("com.komodo.SportsCal.gameDetail") { activity in
            activity.title = "\(game.strAwayTeam) vs \(game.strHomeTeam)"
            activity.isEligibleForHandoff = true
            if let eventID = game.idEvent {
                activity.userInfo = ["eventID": eventID]
                activity.webpageURL = URL(string: "sportscal://game/\(eventID)")
            }
        }
        .onAppear {
            // Check if already tracking
            if let eventID = game.idEvent {
                let ids = UserDefaults.standard.stringArray(forKey: "autoFollowEventIDs") ?? []
                isTracking = ids.contains(eventID)
            }
        }
        .task(id: game.idEvent) {
            await loadPlays()
        }
        .onChange(of: game.lastPlay) { _, _ in
            Task { await loadPlays() }
        }
    }

    // MARK: - Play-by-Play

    private var supportsPlayByPlay: Bool {
        switch game.sportType {
        case .basketball, .nfl, .hockey, .mlb, .soccer: return true
        default: return false
        }
    }

    /// A period's worth of plays — wrapper struct so ForEach can use its `Identifiable`
    /// overload (tuples won't work there).
    private struct PeriodGroup: Identifiable {
        let id: Int
        let plays: [Play]
    }

    /// Plays grouped by period, with the periods in descending order so the most recent
    /// period is at the top. Within each period, plays run chronologically (first → last).
    private var playsGroupedByPeriod: [PeriodGroup] {
        let groups = Dictionary(grouping: plays, by: { $0.period?.number ?? 0 })
        return groups
            .map { PeriodGroup(id: $0.key, plays: $0.value) }
            .sorted { $0.id > $1.id }
    }

    @ViewBuilder
    private var playByPlayCompact: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Play-by-Play")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(plays.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            ForEach(playsGroupedByPeriod) { group in
                periodGroupRow(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func periodGroupRow(_ group: PeriodGroup) -> some View {
        Text(periodAbbreviation(group.id))
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.top, 2)
        ForEach(Array(group.plays.enumerated()), id: \.offset) { _, play in
            watchPlayRow(play)
        }
    }

    @ViewBuilder
    private func watchPlayRow(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let clock = play.clock?.displayValue, !clock.isEmpty {
                Text(clock)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let text = play.text {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(play.scoringPlay == true ? .primary : .secondary)
                    .fontWeight(play.scoringPlay == true ? .semibold : .regular)
            }
            if play.scoringPlay == true,
               let away = play.awayScore, let home = play.homeScore {
                Text("\(away)–\(home)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func periodAbbreviation(_ period: Int) -> String {
        switch game.sportType {
        case .basketball, .nfl: return "Q\(period)"
        case .hockey: return period > 3 ? (period == 4 ? "OT" : "SO") : "P\(period)"
        case .mlb: return "\(period)"
        case .soccer:
            switch period {
            case 1: return "1H"
            case 2: return "2H"
            case 3: return "ET1"
            case 4: return "ET2"
            case 5: return "PEN"
            default: return "\(period)"
            }
        default: return "\(period)"
        }
    }

    private func loadPlays() async {
        guard supportsPlayByPlay, let eventID = game.idEvent else { return }
        let sportPath: String?
        let leagueSlug: String?
        switch game.sportType {
        case .basketball: (sportPath, leagueSlug) = ("basketball", "nba")
        case .nfl:        (sportPath, leagueSlug) = ("football", "nfl")
        case .hockey:     (sportPath, leagueSlug) = ("hockey", "nhl")
        case .mlb:        (sportPath, leagueSlug) = ("baseball", "mlb")
        case .soccer:
            let soccerLeague = game.idLeague.flatMap { Int($0) }.flatMap { Leagues(rawValue: $0) }?.espnSlug
            (sportPath, leagueSlug) = ("soccer", soccerLeague)
        default:          (sportPath, leagueSlug) = (nil, nil)
        }
        do {
            let cached = try await NetworkHandler.fetchPlayByPlay(
                eventID: eventID,
                sport: sportPath,
                league: leagueSlug
            )
            plays = cached.plays
            playsAvailable = true
        } catch is NetworkHandler.PlayByPlayNotAvailable {
            plays = []
            playsAvailable = false
        } catch {
            // Keep any existing plays
        }
    }

    private func toggleTracking() {
        guard let eventID = game.idEvent else { return }
        var ids = UserDefaults.standard.stringArray(forKey: "autoFollowEventIDs") ?? []
        if isTracking {
            ids.removeAll { $0 == eventID }
        } else {
            ids.append(eventID)
        }
        UserDefaults.standard.set(ids, forKey: "autoFollowEventIDs")
        isTracking.toggle()
        WKInterfaceDevice.current().play(isTracking ? .success : .stop)
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        let homeWon = (Int(game.intHomeScore ?? "") ?? 0) > (Int(game.intAwayScore ?? "") ?? 0)
        let awayWon = (Int(game.intAwayScore ?? "") ?? 0) > (Int(game.intHomeScore ?? "") ?? 0)
        return VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(spacing: 2) {
                    Text(awayAbbr)
                        .font(.system(size: 14, design: .rounded).weight(.semibold))
                        .foregroundStyle(awayWon ? WatchTokens.ink : WatchTokens.inkSoft)
                    if isLive || game.isCompleted == true {
                        Text(game.intAwayScore ?? "0")
                            .font(.system(size: 28, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(awayWon ? WatchTokens.ink : WatchTokens.inkSoft)
                    }
                }
                Spacer()
                VStack(spacing: 4) {
                    if isLive {
                        WatchLiveTag(period: game.displayStatus)
                    } else if let progress = game.displayStatus {
                        Text(progress)
                            .font(.system(size: 11, design: .monospaced).weight(.semibold))
                            .foregroundStyle(WatchTokens.inkFaint)
                    }
                    if let date = game.standardDate, !isLive && game.isCompleted != true {
                        Text(date, style: .time)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(WatchTokens.inkSoft)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(homeAbbr)
                        .font(.system(size: 14, design: .rounded).weight(.semibold))
                        .foregroundStyle(homeWon ? WatchTokens.ink : WatchTokens.inkSoft)
                    if isLive || game.isCompleted == true {
                        Text(game.intHomeScore ?? "0")
                            .font(.system(size: 28, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(homeWon ? WatchTokens.ink : WatchTokens.inkSoft)
                    }
                }
            }
        }
    }

    // MARK: - Linescore

    private func linescoreView(homeLine: [Double], awayLine: [Double]) -> some View {
        let periodCount = max(homeLine.count, awayLine.count)
        let highlightedPeriod = Int(crownOffset.rounded())

        return VStack(spacing: 2) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 1) {
                        // Header
                        HStack(spacing: 0) {
                            Text("")
                                .frame(width: 30)
                            ForEach(0..<periodCount, id: \.self) { i in
                                Text(periodLabel(i, total: periodCount))
                                    .font(.system(size: 8, weight: highlightedPeriod == i ? .bold : .semibold))
                                    .foregroundStyle(highlightedPeriod == i ? .primary : .secondary)
                                    .frame(width: 20)
                                    .id("period-\(i)")
                            }
                            Text("T")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 24)
                        }
                        // Away row
                        HStack(spacing: 0) {
                            Text(awayAbbr)
                                .font(.system(size: 9, weight: .medium))
                                .frame(width: 30, alignment: .leading)
                            ForEach(0..<periodCount, id: \.self) { i in
                                Text(i < awayLine.count ? "\(Int(awayLine[i]))" : "-")
                                    .font(.system(size: 9, weight: highlightedPeriod == i ? .bold : .regular, design: .monospaced))
                                    .foregroundStyle(highlightedPeriod == i ? .primary : .secondary)
                                    .frame(width: 20)
                            }
                            Text(game.intAwayScore ?? "0")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .frame(width: 24)
                        }
                        // Home row
                        HStack(spacing: 0) {
                            Text(homeAbbr)
                                .font(.system(size: 9, weight: .medium))
                                .frame(width: 30, alignment: .leading)
                            ForEach(0..<periodCount, id: \.self) { i in
                                Text(i < homeLine.count ? "\(Int(homeLine[i]))" : "-")
                                    .font(.system(size: 9, weight: highlightedPeriod == i ? .bold : .regular, design: .monospaced))
                                    .foregroundStyle(highlightedPeriod == i ? .primary : .secondary)
                                    .frame(width: 20)
                            }
                            Text(game.intHomeScore ?? "0")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .frame(width: 24)
                        }
                    }
                }
                .onChange(of: highlightedPeriod) { _, newPeriod in
                    withAnimation {
                        proxy.scrollTo("period-\(newPeriod)", anchor: .center)
                    }
                }
            }
        }
    }

    private func periodLabel(_ index: Int, total: Int) -> String {
        let sport = game.sportType
        if sport == .hockey { return "P\(index + 1)" }
        if sport == .mlb { return "\(index + 1)" }
        if sport == .nfl { return "Q\(index + 1)" }
        if sport == .basketball { return "Q\(index + 1)" }
        return "\(index + 1)"
    }

    // MARK: - Leaders

    private func leadersView(homeLeaders: [GameLeader], awayLeaders: [GameLeader]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Leaders")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(homeLeaders.prefix(3).enumerated()), id: \.offset) { idx, leader in
                HStack {
                    Text(leader.categoryDisplay)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading) {
                        Text(leader.playerName)
                            .font(.system(size: 10, weight: .medium))
                        Text(leader.displayValue)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if idx < awayLeaders.count {
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(awayLeaders[idx].playerName)
                                .font(.system(size: 10, weight: .medium))
                            Text(awayLeaders[idx].displayValue)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil && game.intAwayScore != nil
    }

    private var statusTitle: String {
        if isLive { return "Live" }
        if game.isCompleted == true { return "Final" }
        return "Upcoming"
    }

    private var homeAbbr: String {
        abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)
    }

    private var awayAbbr: String {
        abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
    }

    private func abbreviation(teamID: String?, name: String) -> String {
        if let team = Team.getTeamInfoFrom(teams: teams, teamID: teamID, teamName: name),
           let short = team.strTeamShort {
            return short
        }
        return Team.shortCode(strTeamShort: nil, name: name)
    }
}
