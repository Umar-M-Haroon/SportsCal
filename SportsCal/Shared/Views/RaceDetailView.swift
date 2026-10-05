//
//  RaceDetailView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
#if os(iOS)
import EventKit
import EventKitUI
#endif

struct RaceDetailView: View {
    let game: Game

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    @State private var selectedSessionIndex: Int = 0
    /// Lap chart / tyres / safety cars for the selected Race or Sprint, fetched on demand.
    @State private var sessionDetail: F1SessionDetail?
    @State private var showStandings = false
    @State private var standingsTab: StandingsTab = .drivers

    private enum StandingsTab: String, CaseIterable {
        case drivers = "Drivers"
        case constructors = "Constructors"
    }

    private var isLive: Bool {
        game.strStatus == "in"
    }

    private var hasSessions: Bool {
        guard let sessions = game.sessions else { return false }
        return !sessions.isEmpty
    }

    // MARK: - Body
    var body: some View {
        // NASCAR has its own page (car numbers, stages, cautions, the Chase); the
        // favourite/follow/calendar/notify actions are shared.
        if game.isNASCAR {
            NASCARRaceDetailView(game: game) { actionsRow }
                .sheet(item: $sheetType, content: sheetContent)
        } else {
            f1Body
        }
    }

    private var f1Body: some View {
        ScrollView {
            VStack(spacing: 24) {
                circuitImageSection
                raceHeader
                if hasSessions {
                    F1SessionPicker(sessions: game.sessions ?? [], selectedIndex: $selectedSessionIndex)
                }
                gameInfo
                actionsRow
                NASCARPromoCard()
                if hasSessions {
                    gapRibbonSection
                    if let sessionDetail, !sessionDetail.lapPositions.isEmpty {
                        F1LapChartView(detail: sessionDetail)
                    }
                    sessionLeaderboard
                    raceTimingSection
                    weekendSchedule
                } else {
                    gapRibbonSection
                    legacyLeaderboard
                    raceTimingSection
                }
                if let standings = viewModel.f1Standings {
                    F1TitleFightCard(standings: standings)
                }
                standingsSection
            }
            .padding()
        }
        .navigationTitle("Formula 1")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: detailRequestStart) {
            sessionDetail = nil
            guard let start = detailRequestStart else { return }
            sessionDetail = try? await NetworkHandler.fetchF1SessionDetail(start: start)
        }
        .onAppear {
            selectDefaultSession()
        }
        .sheet(item: $sheetType, content: sheetContent)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SheetType) -> some View {
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

    /// Start time of the selected session when it's a finished Race or Sprint (the only
    /// sessions the server builds a detail for); nil otherwise.
    private var detailRequestStart: Date? {
        guard let sessions = game.sessions, selectedSessionIndex < sessions.count else { return nil }
        let session = sessions[selectedSessionIndex]
        guard session.status == "post", !session.isTimedLapSession else { return nil }
        return session.startDate
    }

    // MARK: - Default Session Selection
    private func selectDefaultSession() {
        guard let sessions = game.sessions, !sessions.isEmpty else { return }
        // Pick live session first, else highest-priority completed, else last
        if let liveIndex = sessions.firstIndex(where: { $0.status == "in" }) {
            selectedSessionIndex = liveIndex
        } else {
            var bestIndex = sessions.count - 1
            var bestPriority = -1
            for (i, session) in sessions.enumerated() where session.status == "post" && session.importance > bestPriority {
                bestPriority = session.importance
                bestIndex = i
            }
            selectedSessionIndex = bestIndex
        }
    }

    // MARK: - Race Header
    private var raceHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title2)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.strHomeTeam)
                        .font(.title2)
                        .fontWeight(.bold)
                    if let circuit = game.circuitInfo {
                        Text("\(circuit.circuitName) — \(circuit.locality), \(circuit.country)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if let venue = game.venueName {
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

            if let progress = game.displayStatus {
                Text(progress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Leader highlight
            if let leader = game.resolvedLeaderboard.first {
                HStack(spacing: 8) {
                    HeadshotView(url: leader.headshot, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Leader")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text(leader.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let constructor = leader.constructor {
                                Text("(\(constructor))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
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

    private func sessionStatusColor(_ status: String?) -> Color {
        switch status {
        case "post": return .green
        case "in": return .red
        default: return .gray
        }
    }

    // MARK: - Game Info
    private var gameInfo: some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.checkered.2.crossed")
                .foregroundColor(.red)
            Text("Formula 1")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
            liveFollowAction
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

    // MARK: - Live Activity (session in progress)
    #if canImport(ActivityKit) && os(iOS)
    /// Follow a session that's already running. Before the weekend goes live,
    /// `autoFollowAction` covers it by asking the server for a push-to-start.
    @ViewBuilder
    private var liveFollowAction: some View {
        if isLive, let teams = viewModel.getTeams(for: game) {
            let isFollowing = Activity<LiveSportActivityAttributes>.activities.contains { $0.attributes.eventID == game.idEvent }
            Menu {
                LiveActivityFollowMenu(game: game, homeTeam: teams.home, awayTeam: teams.away)
                    .environment(viewModel)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isFollowing ? "clock.badge.checkmark.fill" : "clock.badge")
                        .font(.title3)
                        .foregroundColor(isFollowing ? .accentColor : .secondary)
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

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

    // MARK: - Gap Ribbon Chart

    private var gapRibbonEntries: [LeaderboardEntry] {
        if hasSessions, let sessions = game.sessions {
            let session = selectedSessionIndex < sessions.count ? sessions[selectedSessionIndex] : nil
            return session?.leaderboard ?? []
        } else {
            return game.resolvedLeaderboard
        }
    }

    private var gapRibbonSessionName: String? {
        guard hasSessions, let sessions = game.sessions, selectedSessionIndex < sessions.count else { return nil }
        return sessions[selectedSessionIndex].displayName
    }

    @ViewBuilder
    private var gapRibbonSection: some View {
        let entries = gapRibbonEntries
        if entries.contains(where: { $0.gap != nil }), entries.count >= 3 {
            F1GapRibbonView(entries: entries, sessionName: gapRibbonSessionName, standings: viewModel.f1Standings)
        }
    }

    // MARK: - Session Leaderboard (new: per-session)
    private var sessionLeaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sessions = game.sessions ?? []
            let session = selectedSessionIndex < sessions.count ? sessions[selectedSessionIndex] : nil
            let sessionName = session?.displayName ?? "Standings"

            HStack {
                Text(sessionName)
                    .font(.headline)
                Spacer()
                if let progress = session?.progress, session?.status == "in" {
                    Text(progress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if let session, !session.leaderboard.isEmpty {
                // Header row
                HStack(spacing: 0) {
                    Text("Pos")
                        .frame(width: 32, alignment: .leading)
                    Color.clear.frame(width: 34)
                    Text("Driver")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Constructor")
                        .frame(width: 90, alignment: .leading)
                    Text("Time/Gap")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                let gained = sessions.positionsGainedVsQualifying(in: session)
                ForEach(Array(session.leaderboard.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    NavigationLink { F1DriverView(driverName: viewModel.f1Standings?.driverStanding(matching: entry.name)?.driverName ?? entry.name) } label: {
                    HStack(spacing: 0) {
                        Text("\(entry.position)")
                            .frame(width: 32, alignment: .leading)
                        HeadshotView(url: entry.headshot, size: 28)
                            .padding(.trailing, 6)
                        HStack(spacing: 4) {
                            Text(entry.name)
                                .lineLimit(1)
                            if let change = gained[entry.name], change != 0 {
                                PositionChangeBadge(change: change)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.constructor ?? "")
                            .frame(width: 90, alignment: .leading)
                            .lineLimit(1)
                            .font(.caption)
                        Text(entry.gap ?? "--")
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption)
                    .fontWeight(isLeader ? .bold : .regular)
                    .foregroundColor(isLeader ? .primary : .secondary)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !gained.isEmpty, let grid = sessions.gridSession(for: session) {
                    Text("▲▼ places vs \(grid.displayName.lowercased()); grid penalties not included")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(session.flatMap { $0.status == "pre" || $0.status == nil ? $0.startDate : nil }
                    .map { "Starts \($0.formatted(.dateTime.weekday(.wide).hour().minute()))" }
                    ?? "No standings available for this session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Weekend Schedule
    private var weekendSchedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekend Schedule")
                .font(.headline)

            if let sessions = game.sessions {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                    HStack {
                        Circle()
                            .fill(sessionStatusColor(session.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.displayName)
                                .font(.subheadline)
                            if let sessionDate = parseSessionDate(session.date) {
                                GameTimeLabel(date: sessionDate, includeDate: true)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if let status = session.status {
                            Text(status == "post" ? "Complete" : (status == "in" ? "In Progress" : "Upcoming"))
                                .font(.caption)
                                .foregroundColor(sessionStatusColor(status))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private static let sessionDateFormatters: [DateFormatter] = {
        let formats = ["yyyy-MM-dd'T'HH:mm:ssX", "yyyy-MM-dd'T'HH:mmX"]
        return formats.map { format in
            let df = DateFormatter()
            df.dateFormat = format
            df.locale = Locale(identifier: "en_US_POSIX")
            return df
        }
    }()

    private func parseSessionDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        for formatter in Self.sessionDateFormatters {
            if let date = formatter.date(from: dateString) { return date }
        }
        return nil
    }

    // MARK: - Legacy Leaderboard (fallback when no sessions)
    private var legacyLeaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Race Standings")
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
                    Text("Detailed standings not available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                // Header row
                HStack(spacing: 0) {
                    Text("Pos")
                        .frame(width: 32, alignment: .leading)
                    Color.clear.frame(width: 34)
                    Text("Driver")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Constructor")
                        .frame(width: 90, alignment: .leading)
                    Text("Time/Gap")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    HStack(spacing: 0) {
                        Text("\(entry.position)")
                            .frame(width: 32, alignment: .leading)
                        HeadshotView(url: entry.headshot, size: 28)
                            .padding(.trailing, 6)
                        Text(entry.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.constructor ?? "")
                            .frame(width: 90, alignment: .leading)
                            .lineLimit(1)
                            .font(.caption)
                        Text(entry.gap ?? "--")
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption)
                    .fontWeight(isLeader ? .bold : .regular)
                    .foregroundColor(isLeader ? .primary : .secondary)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Circuit Image
    @ViewBuilder
    private var circuitImageSection: some View {
        if let imageURL = game.circuitInfo?.circuitImageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    EmptyView()
                default:
                    ProgressView()
                        .frame(height: 100)
                }
            }
        }
    }

    // MARK: - Race Timing (laps / tires / pit stops)
    @ViewBuilder
    private var raceTimingSection: some View {
        if let timing = sessionDetail?.timing ?? game.raceTiming, !timing.drivers.isEmpty {
            let leaders = Array(timing.drivers.prefix(10))
            let maxLap = timing.drivers.map { $0.totalLaps }.max() ?? 0
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(timing.sessionType) Pace")
                        .font(.headline)
                    Spacer()
                    if let fastest = timing.drivers.compactMap({ $0.fastestLapTime }).min() {
                        Text("Fastest: \(formatLapTime(fastest))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(leaders, id: \.driverNumber) { driver in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(driver.nameAcronym.isEmpty ? driver.name : driver.nameAcronym)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .frame(width: 44, alignment: .leading)
                                if let fastest = driver.fastestLapTime {
                                    Text(formatLapTime(fastest))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 64, alignment: .leading)
                                }
                                Text("\(driver.pitStops.count) stop\(driver.pitStops.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(driver.totalLaps) laps")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            stintBar(stints: driver.stints, maxLap: maxLap)
                        }
                    }
                }

                if timing.drivers.count > leaders.count {
                    Text("+\(timing.drivers.count - leaders.count) more drivers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func stintBar(stints: [F1Stint], maxLap: Int) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(stints, id: \.stintNumber) { stint in
                    let laps = max(0, stint.lapEnd - stint.lapStart + 1)
                    let width = maxLap > 0 ? geo.size.width * CGFloat(laps) / CGFloat(maxLap) : 0
                    Rectangle()
                        .fill(tireColor(stint.compound))
                        .frame(width: width, height: 8)
                        .overlay(
                            Text(stint.compound.prefix(1))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .frame(height: 8)
        .cornerRadius(2)
    }

    private func tireColor(_ compound: String) -> Color {
        switch compound.uppercased() {
        case "SOFT": return .red
        case "MEDIUM": return .yellow
        case "HARD": return Color(white: 0.85)
        case "INTERMEDIATE": return .green
        case "WET": return .blue
        default: return .gray
        }
    }

    private func formatLapTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%06.3f", mins, secs)
    }

    // MARK: - Championship Standings
    @ViewBuilder
    private var standingsSection: some View {
        if let standings = viewModel.f1Standings,
           (!standings.driverStandings.isEmpty || !standings.constructorStandings.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation { showStandings.toggle() }
                } label: {
                    HStack {
                        Text("Championship Standings")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: showStandings ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showStandings {
                    Picker("Standings", selection: $standingsTab) {
                        ForEach(StandingsTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch standingsTab {
                    case .drivers:
                        driverStandingsView(standings.driverStandings)
                    case .constructors:
                        constructorStandingsView(standings.constructorStandings)
                    }
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func driverStandingsView(_ standings: [F1DriverStanding]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Pos")
                    .frame(width: 32, alignment: .leading)
                Text("Driver")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Team")
                    .frame(width: 90, alignment: .leading)
                Text("Pts")
                    .frame(width: 50, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.bottom, 6)

            ForEach(standings, id: \.position) { standing in
                NavigationLink { F1DriverView(driverName: standing.driverName) } label: {
                HStack(spacing: 0) {
                    Text("\(standing.position)")
                        .frame(width: 32, alignment: .leading)
                        .fontWeight(standing.position <= 3 ? .bold : .regular)
                    Text(standing.driverName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(standing.constructorName)
                        .frame(width: 90, alignment: .leading)
                        .lineLimit(1)
                    Text(standing.points.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(standing.points))" : "\(standing.points, specifier: "%.1f")")
                        .frame(width: 50, alignment: .trailing)
                        .fontWeight(standing.position <= 3 ? .bold : .regular)
                }
                .font(.caption)
                .foregroundColor(standing.position <= 3 ? .primary : .secondary)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func constructorStandingsView(_ standings: [F1ConstructorStanding]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Pos")
                    .frame(width: 32, alignment: .leading)
                Text("Constructor")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Wins")
                    .frame(width: 40, alignment: .trailing)
                Text("Pts")
                    .frame(width: 50, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.bottom, 6)

            ForEach(standings, id: \.position) { standing in
                HStack(spacing: 0) {
                    Text("\(standing.position)")
                        .frame(width: 32, alignment: .leading)
                        .fontWeight(standing.position <= 3 ? .bold : .regular)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(F1GapRibbonView.colorForConstructorName(standing.constructorName, standings: viewModel.f1Standings))
                            .frame(width: 6, height: 6)
                        Text(standing.constructorName)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(standing.wins)")
                        .frame(width: 40, alignment: .trailing)
                    Text(standing.points.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(standing.points))" : "\(standing.points, specifier: "%.1f")")
                        .frame(width: 50, alignment: .trailing)
                        .fontWeight(standing.position <= 3 ? .bold : .regular)
                }
                .font(.caption)
                .foregroundColor(standing.position <= 3 ? .primary : .secondary)
                .padding(.vertical, 2)
            }
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
            event.endDate = gameDate.afterHoursFromNow(hours: 3)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}

/// Segmented row of session tiles. Each tile carries its own state so the weekend
/// reads at a glance: finished sessions name the winner, the live one pulses,
/// upcoming ones show when they start.
struct F1SessionPicker: View {
    let sessions: [EventSession]
    @Binding var selectedIndex: Int
    @Namespace private var namespace

    var body: some View {
        let tiles = HStack(spacing: 4) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                tile(session, index: index)
            }
        }
        .padding(4)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .sensoryFeedback(.selection, trigger: selectedIndex)

        // Equal-width tiles normally; scroll only when Dynamic Type won't fit them.
        return ViewThatFits(in: .horizontal) {
            tiles
            ScrollView(.horizontal, showsIndicators: false) {
                tiles.fixedSize()
            }
        }
    }

    private func tile(_ session: EventSession, index: Int) -> some View {
        let isSelected = index == selectedIndex
        let isUpcoming = session.status != "post" && session.status != "in"
        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedIndex = index
            }
        } label: {
            VStack(spacing: 3) {
                Text(session.shortName)
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : (isUpcoming ? .secondary : .primary))
                    .minimumScaleFactor(0.8)
                tileDetail(session)
                    .font(.caption2)
                    .minimumScaleFactor(0.7)
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondaryGroupedBackground)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "sessionSelection", in: namespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(session))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func tileDetail(_ session: EventSession) -> some View {
        switch session.status {
        case "in":
            HStack(spacing: 3) {
                Circle().fill(.red).frame(width: 5, height: 5)
                    .phaseAnimator([1.0, 0.3]) { dot, opacity in dot.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
                Text("LIVE").fontWeight(.bold).foregroundStyle(.red)
            }
        case "post":
            if let winner = session.leaderboard.first(where: { $0.position == 1 }) ?? session.leaderboard.first {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark").font(.system(size: 7, weight: .bold))
                    Text(Self.driverCode(winner.name))
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Done").foregroundStyle(.secondary)
            }
        default:
            if let start = session.startDate {
                Text(Self.startText(start)).foregroundStyle(.secondary)
            } else {
                Text("TBC").foregroundStyle(.tertiary)
            }
        }
    }

    /// "Sat 4:30" style: weekday when not today, time always.
    private static func startText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private static func driverCode(_ name: String) -> String {
        let last = name.split(separator: " ").last.map(String.init) ?? name
        return String(last.prefix(3)).uppercased()
    }

    private func accessibilityLabel(_ session: EventSession) -> String {
        var label = session.displayName
        switch session.status {
        case "in": label += ", live"
        case "post":
            if let winner = session.leaderboard.first { label += ", finished, \(session.isTimedLapSession ? "fastest" : "won by") \(winner.name)" }
            else { label += ", finished" }
        default:
            if let start = session.startDate { label += ", starts \(start.formatted(date: .abbreviated, time: .shortened))" }
        }
        return label
    }
}

#Preview("Session picker") {
    @Previewable @State var selected = 2
    // Real Dutch GP sprint weekend sessions from prod, statuses rewritten to show done / live / upcoming.
    let json = #"{"idLiveScore":"600057441","strStatus":"in","intAwayScore":"P1","leaderboardEntries":[{"score":"P1","name":"Lando Norris","constructor":"McLaren","position":1,"gap":"2:04:44.859","rounds":[]},{"position":2,"name":"Kimi Antonelli","rounds":[],"score":"P2","constructor":"Mercedes","gap":"+11.536"},{"gap":"+15.906","score":"P3","name":"George Russell","rounds":[],"position":3,"constructor":"Mercedes"},{"rounds":[],"gap":"+16.755","score":"P4","name":"Lewis Hamilton","constructor":"Ferrari","position":4},{"score":"P5","constructor":"Ferrari","name":"Charles Leclerc","gap":"+17.258","rounds":[],"position":5},{"constructor":"McLaren","score":"P6","position":6,"name":"Oscar Piastri","gap":"+32.332","rounds":[]},{"score":"P7","rounds":[],"name":"Liam Lawson","position":7,"constructor":"Red Bull","gap":"+1:19.915"},{"score":"P8","position":8,"name":"Nico Hülkenberg","rounds":[]},{"rounds":[],"name":"Fernando Alonso","constructor":"Aston Martin","position":9,"score":"P9"},{"name":"Pierre Gasly","score":"P10","constructor":"Alpine","position":10,"rounds":[]},{"score":"P11","rounds":[],"position":11,"name":"Yuki Tsunoda","constructor":"Racing Bulls"},{"score":"P12","name":"Arvid Lindblad","position":12,"rounds":[]},{"name":"Gabriel Bortoleto","score":"P13","position":13,"rounds":[]},{"score":"P14","name":"Franco Colapinto","rounds":[],"position":14},{"position":15,"score":"P15","name":"Sergio Pérez","rounds":[]},{"constructor":"Williams","score":"P16","position":16,"name":"Carlos Sainz","rounds":[]},{"score":"P17","position":17,"constructor":"Williams","rounds":[],"name":"Alexander Albon"},{"score":"P18","rounds":[],"name":"Valtteri Bottas","position":18},{"rounds":[],"score":"P19","position":19,"constructor":"Haas","name":"Esteban Ocon"},{"score":"P20","rounds":[],"constructor":"Aston Martin","position":20,"name":"Lance Stroll"},{"constructor":"Haas","name":"Oliver Bearman","rounds":[],"score":"P21","position":21},{"constructor":"Red Bull","name":"Max Verstappen","score":"P22","rounds":[],"position":22}],"strTimestamp":"2026-08-21T10:30Z","isoDate":809001000,"sessions":[{"date":"2026-08-21T10:30Z","sessionName":"Free Practice 1","progress":"Final","leaderboard":[{"rounds":[],"name":"Kimi Antonelli","constructor":"Mercedes","gap":"1:12.949","position":1,"score":"P1"},{"rounds":[],"constructor":"McLaren","position":2,"name":"Lando Norris","gap":"+0.121","score":"P2"},{"score":"P3","position":3,"rounds":[],"name":"George Russell","constructor":"Mercedes","gap":"+0.125"},{"rounds":[],"name":"Lewis Hamilton","score":"P4","constructor":"Ferrari","gap":"+0.190","position":4},{"rounds":[],"score":"P5","position":5,"gap":"+0.289","name":"Charles Leclerc","constructor":"Ferrari"},{"position":6,"rounds":[],"name":"Oscar Piastri","gap":"+0.659","score":"P6","constructor":"McLaren"}],"sessionType":"FP1","status":"post"},{"progress":"Final","sessionName":"SS","leaderboard":[{"name":"George Russell","score":"P1","rounds":[],"position":1,"constructor":"Mercedes","gap":"1:11.567"},{"rounds":[],"constructor":"McLaren","score":"P2","name":"Lando Norris","gap":"+1:11.608","position":2},{"constructor":"Ferrari","gap":"+1:11.622","rounds":[],"position":3,"score":"P3","name":"Charles Leclerc"},{"position":4,"score":"P4","name":"Oscar Piastri","rounds":[],"constructor":"McLaren","gap":"+1:11.666"},{"constructor":"Mercedes","score":"P5","gap":"+1:11.794","name":"Kimi Antonelli","position":5,"rounds":[]},{"constructor":"Red Bull","score":"P6","rounds":[],"position":6,"gap":"+1:12.094","name":"Max Verstappen"}],"sessionType":"SS","status":"post","date":"2026-08-21T14:30Z"},{"progress":"Final","date":"2026-08-22T10:00Z","sessionType":"SR","leaderboard":[{"score":"P1","gap":"30:25.318","position":1,"rounds":[],"name":"George Russell","constructor":"Mercedes"},{"rounds":[],"name":"Charles Leclerc","constructor":"Ferrari","score":"P2","position":2,"gap":"+1.360"},{"rounds":[],"constructor":"McLaren","score":"P3","position":3,"gap":"+5.196","name":"Lando Norris"},{"position":4,"name":"Kimi Antonelli","constructor":"Mercedes","gap":"+5.581","score":"P4","rounds":[]},{"score":"P5","position":5,"name":"Oscar Piastri","constructor":"McLaren","rounds":[],"gap":"+10.185"},{"position":6,"gap":"+10.529","name":"Max Verstappen","rounds":[],"score":"P6","constructor":"Red Bull"}],"sessionName":"SR","status":"in"},{"date":"2026-08-22T14:00Z","sessionName":"Qualifying","progress":null,"leaderboard":[],"sessionType":"Qual","status":"pre"},{"leaderboard":[],"date":"2026-08-23T13:00Z","progress":null,"sessionName":"Race","status":"pre","sessionType":"Race"}],"lastPlay":"Lando Norris|P1|2:04:44.859|McLaren\nKimi Antonelli|P2|+11.536|Mercedes\nGeorge Russell|P3|+15.906|Mercedes\nLewis Hamilton|P4|+16.755|Ferrari\nCharles Leclerc|P5|+17.258|Ferrari\nOscar Piastri|P6|+32.332|McLaren\nLiam Lawson|P7|+1:19.915|Red Bull\nNico Hülkenberg|P8||\nFernando Alonso|P9||Aston Martin\nPierre Gasly|P10||Alpine\nYuki Tsunoda|P11||Racing Bulls\nArvid Lindblad|P12||\nGabriel Bortoleto|P13||\nFranco Colapinto|P14||\nSergio Pérez|P15||\nCarlos Sainz|P16||Williams\nAlexander Albon|P17||Williams\nValtteri Bottas|P18||\nEsteban Ocon|P19||Haas\nLance Stroll|P20||Aston Martin\nOliver Bearman|P21||Haas\nMax Verstappen|P22||Red Bull","circuitInfo":null,"isCompleted":true,"strAwayTeam":"Lando Norris","idLeague":"4370","idEvent":"600057441","strHomeTeam":"Heineken Dutch Grand Prix","strProgress":"Final"}"#
    let game = try! JSONDecoder().decode(Game.self, from: Data(json.utf8))
    VStack(spacing: 24) {
        F1SessionPicker(sessions: game.sessions ?? [], selectedIndex: $selected)
        F1SessionPicker(sessions: Array((game.sessions ?? []).prefix(3)), selectedIndex: .constant(0))
    }
    .padding()
}

/// "▲3" / "▼2" places gained or lost.
struct PositionChangeBadge: View {
    let change: Int

    var body: some View {
        Text("\(change > 0 ? "▲" : "▼")\(abs(change))")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(change > 0 ? .green : .red)
            .accessibilityLabel(change > 0 ? "gained \(change) places" : "lost \(-change) places")
    }
}
