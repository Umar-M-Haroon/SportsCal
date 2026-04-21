//
//  RaceDetailView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel
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
        ScrollView {
            VStack(spacing: 24) {
                circuitImageSection
                raceHeader
                if hasSessions {
                    sessionPicker
                }
                gameInfo
                actionsRow
                if hasSessions {
                    gapRibbonSection
                    sessionLeaderboard
                    raceTimingSection
                    weekendSchedule
                } else {
                    gapRibbonSection
                    legacyLeaderboard
                    raceTimingSection
                }
                standingsSection
            }
            .padding()
        }
        .navigationTitle("Formula 1")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            selectDefaultSession()
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
    }

    // MARK: - Default Session Selection
    private func selectDefaultSession() {
        guard let sessions = game.sessions, !sessions.isEmpty else { return }
        // Pick live session first, else highest-priority completed, else last
        if let liveIndex = sessions.firstIndex(where: { $0.status == "in" }) {
            selectedSessionIndex = liveIndex
        } else {
            let priorities = ["Race": 6, "Sprint": 5, "Qual": 4, "FP3": 3, "FP2": 2, "FP1": 1]
            var bestIndex = sessions.count - 1
            var bestPriority = -1
            for (i, session) in sessions.enumerated() where session.status == "post" {
                let p = priorities[session.sessionType] ?? 0
                if p > bestPriority {
                    bestPriority = p
                    bestIndex = i
                }
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

    // MARK: - Session Picker
    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let sessions = game.sessions {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSessionIndex = index
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(sessionStatusColor(session.status))
                                    .frame(width: 6, height: 6)
                                Text(session.sessionType.isEmpty ? session.sessionName : session.sessionType)
                                    .font(.caption)
                                    .fontWeight(index == selectedSessionIndex ? .bold : .regular)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(index == selectedSessionIndex ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(index == selectedSessionIndex ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
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

    // MARK: - Gap Ribbon Chart

    private var gapRibbonEntries: [LeaderboardEntry] {
        if hasSessions, let sessions = game.sessions {
            let session = selectedSessionIndex < sessions.count ? sessions[selectedSessionIndex] : nil
            return session?.leaderboard ?? []
        } else {
            return game.resolvedLeaderboard
        }
    }

    @ViewBuilder
    private var gapRibbonSection: some View {
        let entries = gapRibbonEntries
        if entries.contains(where: { $0.gap != nil }), entries.count >= 3 {
            F1GapRibbonView(entries: entries)
        }
    }

    // MARK: - Session Leaderboard (new: per-session)
    private var sessionLeaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sessions = game.sessions ?? []
            let session = selectedSessionIndex < sessions.count ? sessions[selectedSessionIndex] : nil
            let sessionName = session?.sessionName ?? "Standings"

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

                ForEach(Array(session.leaderboard.enumerated()), id: \.offset) { index, entry in
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
            } else {
                Text("No standings available for this session")
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
                            Text(session.sessionName)
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
        if let timing = game.raceTiming, !timing.drivers.isEmpty {
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
                            .fill(F1GapRibbonView.colorForConstructorName(standing.constructorName))
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
