//
//  NASCARViews.swift
//  SportsCal
//
//  NASCAR Cup race weekends: the detail page (running order, stages, lap chart, lap-by-lap
//  notes, cautions, pit stops, Chase standings) and the small pieces the list rows share.
//  Data comes from the game's sessions plus `/racing/nascar/race` and
//  `/racing/nascar/standings`, all built server-side from NASCAR's own feeds.
//

import SwiftUI
import Charts
import SportsCalModel

// MARK: - Shared pieces

/// Car number on the manufacturer's colour, the way NASCAR graphics show it.
struct CarNumberBadge: View {
    let number: String
    var manufacturer: String?
    var size: CGFloat = 26

    private var color: Color {
        Color(hex: NASCARVocabulary.manufacturerColorHex(manufacturer)) ?? .gray
    }

    var body: some View {
        Text(number)
            .font(.system(size: size * 0.5, weight: .heavy, design: .rounded).monospacedDigit())
            .italic()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * 1.15, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityLabel("Car \(number)\(manufacturer.map { ", \($0)" } ?? "")")
    }
}

extension RaceState.Flag {
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .white: .white
        case .checkered: .primary
        case .none: .gray
        }
    }

    var label: String {
        switch self {
        case .green: "Green"
        case .yellow: "Caution"
        case .red: "Red Flag"
        case .white: "White Flag"
        case .checkered: "Checkered"
        case .none: "—"
        }
    }

    var symbol: String {
        self == .checkered ? "flag.checkered" : "flag.fill"
    }
}

/// Lap progress with the stage ends marked, the flag, and the race's running stats.
struct NASCARRaceStateBar: View {
    let state: RaceState
    let isLive: Bool

    private var progress: Double {
        guard state.totalLaps > 0 else { return 0 }
        return min(Double(state.lap) / Double(state.totalLaps), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.flag.label, systemImage: state.flag.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.flag == .white ? Color.primary : state.flag.color)
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text(state.lap > 0 ? state.lapLabel : "\(state.totalLaps) laps")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if isLive, state.lap > 0 {
                    Text("\(state.lapsToGo) to go")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(isLive ? state.flag.color.opacity(state.flag == .white ? 0.5 : 0.85) : Color.app(.racing))
                        .frame(width: proxy.size.width * progress)
                    ForEach(Array((state.stageEndLaps ?? []).dropLast().enumerated()), id: \.offset) { _, lap in
                        Rectangle()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 2)
                            .offset(x: proxy.size.width * Double(lap) / Double(max(state.totalLaps, 1)) - 1)
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            if let ends = state.stageEndLaps, ends.count > 1 {
                HStack(spacing: 0) {
                    ForEach(Array(ends.enumerated()), id: \.offset) { index, end in
                        let isCurrent = isLive && state.stage == index + 1
                        Text(index == ends.count - 1 ? "Final · L\(end)" : "Stage \(index + 1) · L\(end)")
                            .font(.caption2.weight(isCurrent ? .bold : .regular))
                            .foregroundStyle(isCurrent ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == ends.count - 1 ? .trailing : .center))
                    }
                }
            }

            let stats: [(String, String)] = [
                state.cautions.map { ("Cautions", "\($0)") },
                state.leadChanges.map { ("Lead changes", "\($0)") },
                state.leaders.map { ("Leaders", "\($0)") },
            ].compactMap { $0 }
            if !stats.isEmpty {
                HStack {
                    ForEach(stats, id: \.0) { stat in
                        VStack(spacing: 1) {
                            Text(stat.1).font(.headline.monospacedDigit())
                            Text(stat.0).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(state.flag.label), \(state.lap > 0 ? state.lapLabel : "\(state.totalLaps) laps")")
    }
}

// MARK: - Detail

struct NASCARRaceDetailView<Actions: View>: View {
    let game: Game
    @ViewBuilder var actions: () -> Actions

    @State private var selectedSessionIndex = 0
    @State private var detail: NASCARRaceDetail?
    @State private var standings: NASCARStandings?
    @State private var showAllNotes = false
    @State private var showAllStandings = false

    /// The game's sessions, with full results swapped in from the race endpoint: the
    /// schedule copy carries only the top of each leaderboard. A session in progress
    /// keeps the game's copy, which the socket updates faster than the endpoint.
    private var sessions: [EventSession] {
        let base = game.sessions ?? []
        guard let full = detail?.sessions, full.count == base.count else { return base }
        return zip(base, full).map { scheduled, complete in
            scheduled.status != "in" && complete.leaderboard.count > scheduled.leaderboard.count ? complete : scheduled
        }
    }
    private var isLive: Bool { game.strStatus == "in" }
    private var raceSession: EventSession? { sessions.first { $0.sessionType == "race" } }
    private var selectedSession: EventSession? {
        selectedSessionIndex < sessions.count ? sessions[selectedSessionIndex] : nil
    }
    private var raceID: Int? {
        game.idEvent.flatMap { id in id.hasPrefix("nascar-") ? Int(id.dropFirst("nascar-".count)) : nil }
    }
    /// Lap chart, notes and pit stops exist once the race has gone green.
    private var raceHasStarted: Bool {
        raceSession?.status == "in" || raceSession?.status == "post"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if let state = raceSession?.raceState, raceHasStarted {
                    NASCARRaceStateBar(state: state, isLive: raceSession?.status == "in")
                }
                actions()
                if sessions.count > 1 {
                    F1SessionPicker(sessions: sessions, selectedIndex: $selectedSessionIndex)
                }
                if let selectedSession {
                    NASCARLeaderboard(session: selectedSession)
                }
                if selectedSession?.sessionType == "race", let detail {
                    if !detail.stages.isEmpty { NASCARStagesCard(stages: detail.stages) }
                    if !detail.lapPositions.isEmpty { NASCARLapChart(detail: detail) }
                    if !detail.notes.isEmpty { notesCard(detail.notes) }
                    if !detail.cautions.isEmpty { NASCARCautionsCard(cautions: detail.cautions) }
                    if !detail.pitStops.isEmpty { NASCARPitStopsCard(stops: detail.pitStops) }
                }
                if let standings {
                    NASCARStandingsCard(standings: standings, showAll: $showAllStandings)
                }
                weekendSchedule
            }
            .padding()
        }
        .navigationTitle("NASCAR Cup Series")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: selectDefaultSession)
        .task {
            standings = try? await NetworkHandler.fetchNASCARStandings()
        }
        .task(id: game.idEvent) {
            // Always fetched: besides the race story it carries every session's full results.
            guard let raceID else { return }
            // While the race runs, the server rebuilds the detail every 30s.
            repeat {
                if let fresh = try? await NetworkHandler.fetchNASCARRaceDetail(raceID: raceID) {
                    detail = fresh
                }
                guard isLive else { break }
                try? await Task.sleep(for: .seconds(30))
            } while !Task.isCancelled
        }
    }

    private func selectDefaultSession() {
        guard !sessions.isEmpty else { return }
        if let live = sessions.firstIndex(where: { $0.status == "in" }) {
            selectedSessionIndex = live
        } else if let best = sessions.indices.filter({ sessions[$0].status == "post" && !sessions[$0].leaderboard.isEmpty })
                    .max(by: { sessions[$0].importance < sessions[$1].importance }) {
            selectedSessionIndex = best
        } else {
            selectedSessionIndex = sessions.count - 1
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NASCAR CUP SERIES")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.app(.racing))
                    Text(game.strHomeTeam)
                        .font(.title2.bold())
                    if let venue = game.venueName {
                        Text(venue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red, in: Capsule())
                }
            }

            if game.seasonPhase == .postseason {
                Label("The Chase", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            let facts = raceFacts
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let progress = game.strProgress, isLive || game.strStatus == "post" {
                Text(progress)
                    .font(.subheadline.weight(.semibold))
            } else if let date = game.standardDate {
                GameTimeLabel(date: date, includeDate: true)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    /// "267 laps · 400.5 mi · TV: USA".
    private var raceFacts: [String] {
        guard let state = raceSession?.raceState else { return [] }
        var facts: [String] = []
        if state.totalLaps > 0 { facts.append("\(state.totalLaps) laps") }
        if let miles = state.distanceMiles, miles > 0 {
            facts.append("\(miles.formatted(.number.precision(.fractionLength(0...1)))) mi")
        }
        if let tv = state.broadcast { facts.append("TV: \(tv)") }
        return facts
    }

    // MARK: Notes

    private func notesCard(_ notes: [NASCARLapNote]) -> some View {
        let ordered = notes.reversed()
        let shown = showAllNotes ? Array(ordered) : Array(ordered.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Lap by Lap")
                .font(.headline)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(note.lap == 0 ? "Pre" : "L\(note.lap)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 36, alignment: .leading)
                    Circle()
                        .fill(note.flag == .none ? Color.gray : note.flag.color)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: note.flag == .white ? 1 : 0))
                    Text(note.note)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if notes.count > 8 {
                Button(showAllNotes ? "Show Less" : "Show All \(notes.count)") {
                    withAnimation { showAllNotes.toggle() }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: Weekend schedule

    @ViewBuilder
    private var weekendSchedule: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weekend Schedule")
                    .font(.headline)
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                    HStack {
                        Text(session.displayName)
                            .font(.subheadline)
                        Spacer()
                        if session.progress == "Canceled" {
                            Text("Canceled").font(.caption).foregroundStyle(.secondary)
                        } else if let start = session.startDate {
                            GameTimeLabel(date: start, includeDate: true)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }
}

// MARK: - Leaderboard

struct NASCARLeaderboard: View {
    let session: EventSession
    @State private var showAll = false

    private var isRace: Bool { session.sessionType == "race" }
    private var title: String {
        if isRace {
            switch session.status {
            case "post": return "Results"
            case "in": return "Running Order"
            default: return "Starting Lineup"
            }
        }
        return session.displayName
    }

    var body: some View {
        let entries = session.leaderboard
        let shown = showAll ? entries : Array(entries.prefix(15))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if session.status == "in", let progress = session.progress {
                    Text(progress).font(.caption).foregroundStyle(.secondary)
                }
            }
            if entries.isEmpty {
                Text(session.progress == "Canceled" ? "Canceled" : (session.status == "post" ? "No results" : "Not started"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
                    row(entry)
                    if entry.position != shown.last?.position { Divider() }
                }
                if entries.count > 15 {
                    Button(showAll ? "Show Less" : "Show All \(entries.count)") {
                        withAnimation { showAll.toggle() }
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func row(_ entry: LeaderboardEntry) -> some View {
        let car = entry.stockCar
        return HStack(spacing: 10) {
            Text("\(entry.position)")
                .font(.subheadline.monospacedDigit().weight(entry.position <= 3 ? .bold : .regular))
                .frame(width: 24, alignment: .trailing)
            if let car {
                CarNumberBadge(number: car.carNumber, manufacturer: car.manufacturer)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.name)
                        .font(.subheadline.weight(entry.position == 1 ? .semibold : .regular))
                        .lineLimit(1)
                    if car?.inPlayoffs == true {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("in the Chase")
                    }
                    if isRace, let change = car?.positionsGained(finishing: entry.position), change != 0, session.status != "pre" {
                        PositionChangeBadge(change: change)
                    }
                }
                let detail = detailLine(entry)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(trailing(entry))
                .font(.subheadline.monospacedDigit())
                // A car out of the race shows why ("Accident") in red.
                .foregroundStyle(car?.isOut == true ? Color.red : (entry.position == 1 ? Color.primary : Color.secondary))
        }
        .accessibilityElement(children: .combine)
    }

    /// "Hendrick Motorsports · Led 235" for races; team and speed for timed sessions.
    private func detailLine(_ entry: LeaderboardEntry) -> String {
        var parts: [String] = []
        if let team = entry.constructor { parts.append(team) }
        if isRace {
            if let led = entry.stockCar?.lapsLed, led > 0 { parts.append("Led \(led)") }
            if session.status == "pre", let start = entry.stockCar?.startPosition { parts.append("Starts P\(start)") }
        } else if let speed = entry.stockCar?.bestLapSpeed {
            parts.append("\(speed.formatted(.number.precision(.fractionLength(3)))) mph")
        }
        return parts.joined(separator: " · ")
    }

    private func trailing(_ entry: LeaderboardEntry) -> String {
        if isRace {
            if entry.position == 1 { return session.status == "post" ? "Winner" : (session.status == "in" ? "Leader" : "Pole") }
            return entry.gap ?? ""
        }
        if entry.position == 1 { return entry.score }
        return entry.gap ?? entry.score
    }
}

// MARK: - Stages

struct NASCARStagesCard: View {
    let stages: [NASCARStageResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stage Results").font(.headline)
            HStack(alignment: .top, spacing: 12) {
                ForEach(stages, id: \.stage) { stage in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stage \(stage.stage)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(stage.finishers.prefix(5), id: \.position) { finisher in
                            HStack(spacing: 4) {
                                Text("\(finisher.position)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, alignment: .trailing)
                                Text(Self.surname(finisher.driver))
                                    .font(.caption.weight(finisher.position == 1 ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    static func surname(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }
}

// MARK: - Lap chart

/// Running position per lap for the top ten, coloured by make, cautions shaded.
struct NASCARLapChart: View {
    let detail: NASCARRaceDetail
    @State private var focused: String?

    private var lines: [NASCARLapPositions] {
        // The ten cars running at the front on the latest lap.
        detail.lapPositions
            .filter { ($0.positions.last ?? 0) > 0 }
            .sorted { ($0.positions.last ?? 99) < ($1.positions.last ?? 99) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lap Chart").font(.headline)
            Chart {
                ForEach(Array(detail.cautions.enumerated()), id: \.offset) { _, caution in
                    RectangleMark(xStart: .value("Lap", caution.startLap), xEnd: .value("Lap", caution.endLap))
                        .foregroundStyle(Color.yellow.opacity(0.18))
                }
                ForEach(lines, id: \.carNumber) { line in
                    let dimmed = focused != nil && focused != line.carNumber
                    let color = Color(hex: NASCARVocabulary.manufacturerColorHex(line.manufacturer)) ?? .gray
                    ForEach(Array(line.positions.enumerated()).filter { $0.element > 0 }, id: \.offset) { lap, position in
                        LineMark(
                            x: .value("Lap", lap),
                            y: .value("Position", -min(position, 20)),
                            series: .value("Car", line.carNumber)
                        )
                        .foregroundStyle(color.opacity(dimmed ? 0.12 : 0.9))
                        .lineStyle(StrokeStyle(lineWidth: focused == line.carNumber ? 3 : 1.5))
                    }
                }
            }
            .chartYScale(domain: -20.5...(-0.5))
            .chartYAxis {
                AxisMarks(values: [-1, -5, -10, -15, -20]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("P\(-v)") }
                    }
                }
            }
            .chartXAxisLabel("Lap")
            .frame(height: 220)
            .accessibilityLabel("Lap chart for the top ten")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(lines, id: \.carNumber) { line in
                        Button {
                            withAnimation { focused = focused == line.carNumber ? nil : line.carNumber }
                        } label: {
                            HStack(spacing: 4) {
                                CarNumberBadge(number: line.carNumber, manufacturer: line.manufacturer, size: 18)
                                Text(NASCARStagesCard.surname(line.driver)).font(.caption)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(focused == line.carNumber ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }
}

// MARK: - Cautions

struct NASCARCautionsCard: View {
    let cautions: [NASCARCaution]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cautions").font(.headline)
                Spacer()
                Text("\(cautions.count) for \(cautions.reduce(0) { $0 + $1.laps }) laps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(cautions.enumerated()), id: \.offset) { _, caution in
                HStack(alignment: .firstTextBaseline) {
                    Text("L\(caution.startLap)–\(caution.endLap)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 70, alignment: .leading)
                    Text(caution.reason)
                        .font(.subheadline)
                    Spacer()
                    if let car = caution.freePassCar {
                        Text("Free pass #\(car)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }
}

// MARK: - Pit stops

struct NASCARPitStopsCard: View {
    let stops: [NASCARPitStop]

    /// Quickest four-tire stops: the pit crew leaderboard fans look for.
    private var fastest: [NASCARPitStop] {
        stops.filter { $0.tires == 4 && ($0.stopDuration ?? 0) > 0 }
            .sorted { ($0.stopDuration ?? .infinity) < ($1.stopDuration ?? .infinity) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pit Stops").font(.headline)
                Spacer()
                Text("\(stops.count) stops")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !fastest.isEmpty {
                Text("Fastest four-tire stops")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(fastest.enumerated()), id: \.offset) { _, stop in
                    HStack {
                        Text(stop.driver).font(.subheadline)
                        Text("L\(stop.lap)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fs", stop.stopDuration ?? 0))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }
}

// MARK: - Standings

struct NASCARStandingsCard: View {
    let standings: NASCARStandings
    @Binding var showAll: Bool

    var body: some View {
        let drivers = showAll ? standings.drivers : Array(standings.drivers.prefix(standings.playoffSpots + 4))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(String(standings.season)) Standings").font(.headline)
                Spacer()
                if standings.hasPlayoffField {
                    Label("In the Chase", systemImage: "trophy.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(drivers) { driver in
                if standings.hasPlayoffField, driver.position == standings.playoffSpots + 1 {
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.orange.opacity(0.6)).frame(height: 1)
                        Text("Cut line").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        Rectangle().fill(Color.orange.opacity(0.6)).frame(height: 1)
                    }
                    .accessibilityLabel("Chase cut line")
                }
                row(driver)
            }
            if standings.drivers.count > drivers.count || showAll {
                Button(showAll ? "Show Less" : "Show All \(standings.drivers.count)") {
                    withAnimation { showAll.toggle() }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func row(_ driver: NASCARStandingsEntry) -> some View {
        HStack(spacing: 10) {
            Text("\(driver.position)")
                .font(.subheadline.monospacedDigit())
                .frame(width: 24, alignment: .trailing)
            CarNumberBadge(number: driver.carNumber, manufacturer: driver.manufacturer, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(driver.name).font(.subheadline).lineLimit(1)
                    if driver.movement != 0 { PositionChangeBadge(change: driver.movement) }
                }
                Text("\(driver.wins) W · \(driver.top5) T5 · \(driver.stageWins) stage wins")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(driver.points)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if let above = driver.aboveCutLine {
                    Text(above >= 0 ? "+\(above)" : "\(above)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(above >= 0 ? .green : .red)
                } else if driver.behindLeader < 0 {
                    Text("\(driver.behindLeader)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Discovery

/// Shown once to F1 fans who haven't turned NASCAR on: a card next to F1 content with a
/// one-tap "Turn On". Either button retires it for good; after that, NASCAR lives in
/// the racing league picker like any other competition.
enum NASCARPromo {
    static let dismissedKey = "promo.nascarCup.dismissed"

    static func isEligible(storage: UserDefaultStorage, dismissed: Bool) -> Bool {
        !dismissed && storage.hiddenCompetitions.contains(Leagues.nascarCup.leagueName)
    }
}

struct NASCARPromoCard: View {
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(GameViewModel.self) private var viewModel
    @AppStorage(NASCARPromo.dismissedKey) private var dismissed = false

    var body: some View {
        if NASCARPromo.isEligible(storage: storage, dismissed: dismissed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .font(.title2)
                        .foregroundStyle(Color.app(.racing))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("New: NASCAR Cup Series")
                            .font(.headline)
                        Text("Every race weekend with the live running order, stages, cautions, pit stops and the Chase.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Button("Turn On") {
                        WhatsNewAction.showCompetition(.nascarCup, sport: .racing)
                            .apply(storage: storage, viewModel: viewModel)
                        dismissed = true
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not Now") {
                        withAnimation { dismissed = true }
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }
}

/// The promo as its own list section (Browse > Racing), so an empty section never shows.
struct NASCARPromoSection: View {
    @Environment(UserDefaultStorage.self) private var storage
    @AppStorage(NASCARPromo.dismissedKey) private var dismissed = false

    var body: some View {
        if NASCARPromo.isEligible(storage: storage, dismissed: dismissed) {
            Section {
                NASCARPromoCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }
}

/// Browsing a series that's hidden from the schedule: say so, with a way to show it.
struct RacingSeriesHiddenNotice: View {
    let series: Leagues
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(GameViewModel.self) private var viewModel
    @AppStorage(NASCARPromo.dismissedKey) private var promoDismissed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(series.leagueName) isn't in your schedule yet.")
                .font(.subheadline)
            Button("Show in My Schedule") {
                WhatsNewAction.showCompetition(series, sport: .racing)
                    .apply(storage: storage, viewModel: viewModel)
                if series == .nascarCup { promoDismissed = true }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Previews

/// Las Vegas at lap 174 of 267 (2026-10-04), trimmed to the top five.
private enum NASCARPreviewData {
    static func entry(_ pos: Int, _ name: String, _ car: String, _ make: String, _ team: String, gap: String?, led: Int, start: Int, chase: Bool) -> LeaderboardEntry {
        LeaderboardEntry(name: name, score: "P\(pos)", position: pos, constructor: team, gap: gap,
                         stockCar: StockCarDetail(carNumber: car, manufacturer: make, startPosition: start, lapsLed: led,
                                                  status: "Running", inPlayoffs: chase))
    }

    static let board = [
        entry(1, "Chase Briscoe", "19", "Toyota", "Joe Gibbs Racing", gap: nil, led: 41, start: 6, chase: true),
        entry(2, "Austin Cindric", "2", "Ford", "Team Penske", gap: "+0.412", led: 38, start: 12, chase: true),
        entry(3, "Denny Hamlin", "11", "Toyota", "Joe Gibbs Racing", gap: "+1.907", led: 52, start: 1, chase: true),
        entry(4, "Kyle Larson", "5", "Chevrolet", "Hendrick Motorsports", gap: "+2.310", led: 0, start: 9, chase: true),
        entry(5, "Ross Chastain", "1", "Chevrolet", "Trackhouse Racing", gap: "+1 Lap", led: 0, start: 22, chase: false),
    ]

    static let state = RaceState(lap: 174, totalLaps: 267, flag: .green, stage: 3, stageEndLap: 267,
                                 cautions: 3, cautionLaps: 16, leadChanges: 9, leaders: 7,
                                 stageEndLaps: [80, 165, 267], distanceMiles: 400.5, broadcast: "USA")

    static let race = EventSession(sessionType: "race", sessionName: "Race", status: "in",
                                   progress: "Lap 174/267 · Final Stage", date: "2026-10-04T21:30:00Z",
                                   leaderboard: board, raceState: state)
}

#Preview("Race state") {
    NASCARRaceStateBar(state: NASCARPreviewData.state, isLive: true)
        .padding()
}

#Preview("Running order") {
    ScrollView {
        NASCARLeaderboard(session: NASCARPreviewData.race)
            .padding()
    }
}

#Preview("Stages & cautions") {
    ScrollView {
        VStack(spacing: 16) {
            NASCARStagesCard(stages: [
                NASCARStageResult(stage: 1, finishers: [.init(position: 1, driver: "Denny Hamlin", carNumber: "11", points: 10),
                                                        .init(position: 2, driver: "Kyle Larson", carNumber: "5", points: 9)]),
                NASCARStageResult(stage: 2, finishers: [.init(position: 1, driver: "Austin Cindric", carNumber: "2", points: 10),
                                                        .init(position: 2, driver: "Chase Briscoe", carNumber: "19", points: 9)]),
            ])
            NASCARCautionsCard(cautions: [
                NASCARCaution(startLap: 37, endLap: 40, reason: "Competition", freePassCar: "51"),
                NASCARCaution(startLap: 82, endLap: 86, reason: "Stage 1 Conclusion", freePassCar: "47"),
            ])
        }
        .padding()
    }
}
