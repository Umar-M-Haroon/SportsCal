//
//  BrowseComponents.swift
//  SportsCal (iOS)
//
//  Pieces shared by Home (DayPage) and Browse: the Live / Your Teams sections and the
//  collapsible section header, the chip strip every Browse sport opens with, the
//  preview-then-"Show all" group used for event lists, and the racing cards.
//

import SwiftUI
import NukeUI
import WidgetKit
import SportsCalModel

// MARK: - Day sections

/// Games in play right now, under the animated LIVE header. Renders nothing when empty.
struct LiveGamesSection<Row: View>: View {
    let games: [GameWithTeams]
    @ViewBuilder let row: (GameWithTeams) -> Row

    var body: some View {
        if !games.isEmpty {
            Section {
                ForEach(games) { row($0) }
            } header: {
                LiveAnimatedView()
            }
        }
    }
}

/// The day's games involving followed teams. Renders nothing when empty.
struct YourTeamsSection<Row: View>: View {
    let games: [GameWithTeams]
    @ViewBuilder let row: (GameWithTeams) -> Row

    var body: some View {
        if !games.isEmpty {
            Section {
                ForEach(games) { row($0) }
            } header: {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Your Teams")
                        .font(.headline)
                }
            }
        }
    }
}

/// Tappable section header with a count and a disclosure chevron — Home's per-sport
/// sections and Browse's per-league sections.
struct CollapsibleSectionHeader: View {
    let title: String
    var systemImage: String?
    var tint: Color = .primary
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { toggle() }
        } label: {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundColor(tint)
                }
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text("(\(count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

// MARK: - Chips

/// One chip in a Browse header: a league, tour or series, or "All".
struct BrowseChipItem: Identifiable, Hashable {
    let id: String
    let title: String
    /// The competition behind the chip; enables the long-press show/hide menu.
    var league: Leagues?

    static let all = BrowseChipItem(id: "all", title: "All")

    init(id: String, title: String, league: Leagues? = nil) {
        self.id = id
        self.title = title
        self.league = league
    }

    init(league: Leagues, title: String? = nil) {
        self.init(id: String(league.rawValue),
                  title: title ?? league.racingShortName ?? league.golfTourShortName ?? league.leagueName,
                  league: league)
    }
}

/// The chip row every Browse sport opens with. A chip whose competition is hidden from
/// the schedule wears an eye-slash, and long-pressing a competition chip shows or hides
/// it — the same switch as Settings › Manage Sports › Leagues.
struct BrowseChipStrip: View {
    let items: [BrowseChipItem]
    let selectedID: String?
    let sport: SportType
    let onSelect: (BrowseChipItem) -> Void

    @Environment(UserDefaultStorage.self) private var storage
    @Environment(GameViewModel.self) private var viewModel

    var body: some View {
        // hiddenCompetitions is AppStorage-backed (not observed); the version bump is.
        let _ = storage.preferenceVersion
        let hidden = Set(storage.hiddenCompetitions)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        chip(item, isHidden: item.league.map { hidden.contains($0.leagueName) } ?? false)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
            }
            // A chip picked at the strip's edge would otherwise stay half off-screen.
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func chip(_ item: BrowseChipItem, isHidden: Bool) -> some View {
        let isSelected = item.id == selectedID
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { onSelect(item) }
        } label: {
            HStack(spacing: 4) {
                if isHidden {
                    Image(systemName: "eye.slash")
                        .font(.caption2)
                }
                Text(item.title)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(isSelected ? Color.app(sport).opacity(0.2) : Color.gray.opacity(0.12)))
            .overlay(Capsule().strokeBorder(isSelected ? Color.app(sport) : .clear, lineWidth: 1.5))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isHidden ? "Hidden from your schedule" : "")
        .contextMenu {
            if let league = item.league {
                if isHidden {
                    Button {
                        WhatsNewAction.showCompetition(league, sport: sport)
                            .apply(storage: storage, viewModel: viewModel)
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        Label("Show in My Schedule", systemImage: "eye")
                    }
                } else {
                    Button {
                        storage.hiddenCompetitions.append(league.leagueName)
                        storage.syncHiddenCompetitions()
                        viewModel.filterSports(force: true)
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        Label("Hide from My Schedule", systemImage: "eye.slash")
                    }
                }
            }
        }
    }
}

/// The chip each Browse sport was last left on, so the page reopens where it was.
enum BrowseChipMemory {
    private static func key(_ sport: SportType) -> String { "browse.chip.\(sport.rawValue)" }

    static func chipID(for sport: SportType) -> String? {
        UserDefaults.standard.string(forKey: key(sport))
    }

    static func remember(_ id: String?, for sport: SportType) {
        if let id {
            UserDefaults.standard.set(id, forKey: key(sport))
        } else {
            UserDefaults.standard.removeObject(forKey: key(sport))
        }
    }

    /// The remembered chip as a league, when it still names one.
    static func league(for sport: SportType) -> Leagues? {
        chipID(for: sport).flatMap(Int.init).flatMap(Leagues.init(rawValue:))
    }
}

// MARK: - Preview groups

/// A section showing its first `preview` items, then a "Show all" toggle. A zero preview
/// starts collapsed behind the header (older seasons, past results).
struct PreviewGroupSection<Item: Identifiable, Row: View, Header: View>: View {
    let items: [Item]
    let preview: Int
    /// "races", "tournaments" — finishes "Show 12 races" on a collapsed group.
    let noun: String
    @Binding var isExpanded: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        let shown = isExpanded ? items : Array(items.prefix(preview))
        Section {
            ForEach(shown) { row($0) }
            if items.count > preview {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Show fewer"
                         : (preview == 0 ? "Show \(items.count) \(noun)" : "Show all \(items.count)"))
                        .font(.subheadline)
                }
            }
        } header: {
            header()
        }
    }
}

// MARK: - Racing

/// The next race weekend, in full: where it is, every session in local time with the
/// next one counting down, and the circuit map when we have one (F1).
struct RaceWeekendCard: View {
    let game: Game

    private var sessions: [EventSession] {
        (game.sessions ?? []).sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    /// The live session, else the first one yet to start.
    private var focusSession: EventSession? {
        sessions.first { $0.status == "in" }
            ?? sessions.first { $0.status != "post" && ($0.startDate ?? .distantPast) > Date() }
    }

    private var location: String? {
        if let circuit = game.circuitInfo {
            return "\(circuit.circuitName) · \(circuit.locality), \(circuit.country)"
        }
        return game.venueName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.strHomeTeam)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    if let location {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let url = game.circuitInfo?.circuitImageURL.flatMap(URL.init(string:)) {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 72, height: 52)
                    .accessibilityHidden(true)
                }
            }

            if let focus = focusSession, let start = focus.startDate {
                HStack(spacing: 6) {
                    if focus.status == "in" {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text("\(focus.displayName) is live")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Image(systemName: "timer")
                            .foregroundStyle(Color.app(.racing))
                        Text("\(focus.displayName) in ")
                            .font(.subheadline.weight(.semibold))
                        + Text(start, style: .relative)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            if !sessions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                        sessionRow(session, isFocused: session.sessionType == focusSession?.sessionType)
                    }
                }
            } else if let date = game.standardDate {
                Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func sessionRow(_ session: EventSession, isFocused: Bool) -> some View {
        let isDone = session.status == "post"
        return HStack(spacing: 8) {
            Group {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                } else if session.status == "in" {
                    Circle().fill(.red).frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(isFocused ? Color.app(.racing) : Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 14)
            Text(session.displayName)
                .font(.subheadline.weight(isFocused ? .semibold : .regular))
            Spacer()
            if isDone, let winner = session.leaderboard.first {
                Text(winner.name.split(separator: " ").last.map(String.init) ?? winner.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let start = session.startDate {
                Text(start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isFocused ? .primary : .secondary)
            }
        }
        .foregroundStyle(isDone ? Color.secondary : Color.primary)
    }
}

/// One row of a championship table shown inline on racing browse.
struct RacingStandingRow: Identifiable, Hashable {
    var id: Int { position }
    let position: Int
    let name: String
    let detail: String?
    let points: String
}

/// The championship's top three, inline above the calendar; the full table is a tap away.
struct RacingStandingsPreview: View {
    let title: String
    let rows: [RacingStandingRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.prefix(3)) { row in
                HStack(spacing: 8) {
                    Text("\(row.position)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.position == 1 ? Color.app(.racing) : .secondary)
                        .frame(width: 20, alignment: .leading)
                    Text(row.name)
                        .font(.subheadline.weight(row.position == 1 ? .semibold : .regular))
                        .lineLimit(1)
                    if let detail = row.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(row.points)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    static func rows(f1: F1Standings) -> [RacingStandingRow] {
        f1.driverStandings.map {
            RacingStandingRow(position: $0.position, name: $0.driverName, detail: $0.constructorName,
                              points: "\(Int($0.points)) pts")
        }
    }

    static func rows(series: NetworkHandler.SeriesStandings) -> [RacingStandingRow] {
        let drivers: [NASCARStandingsEntry]
        switch series {
        case .drivers(let table): drivers = table.drivers
        // Endurance racing runs several classes; the top class leads the preview.
        case .classes(let tables): drivers = tables.classes.first?.drivers ?? []
        }
        return drivers.sorted { $0.position < $1.position }.map {
            RacingStandingRow(position: $0.position, name: $0.name,
                              detail: $0.carNumber.isEmpty ? nil : "#\($0.carNumber)",
                              points: "\($0.points) pts")
        }
    }
}

// MARK: - Previews

#Preview("Race weekend") {
    let now = Date()
    let iso = ISO8601DateFormatter()
    func session(_ type: String, hours: Double, status: String?, winner: String? = nil) -> EventSession {
        EventSession(sessionType: type, sessionName: type, status: status,
                     date: iso.string(from: now.addingTimeInterval(hours * 3600)),
                     leaderboard: winner.map { [LeaderboardEntry(name: $0, score: "1", position: 1)] } ?? [])
    }
    let game = Game(strHomeTeam: "United States Grand Prix", strAwayTeam: "TBD",
                    isoDate: now.addingTimeInterval(50 * 3600),
                    sessions: [
                        session("FP1", hours: -20, status: "post"),
                        session("SS", hours: -16, status: "post", winner: "Lando Norris"),
                        session("SR", hours: 4, status: "pre"),
                        session("Qual", hours: 8, status: "pre"),
                        session("Race", hours: 50, status: "pre"),
                    ],
                    circuitInfo: F1CircuitInfo(circuitName: "Circuit of the Americas",
                                               locality: "Austin", country: "USA"))
    return List {
        Section("Next Up") { RaceWeekendCard(game: game) }
        Section("Championship") {
            RacingStandingsPreview(title: "F1 Standings", rows: [
                RacingStandingRow(position: 1, name: "Lando Norris", detail: "McLaren", points: "341 pts"),
                RacingStandingRow(position: 2, name: "Oscar Piastri", detail: "McLaren", points: "327 pts"),
                RacingStandingRow(position: 3, name: "Max Verstappen", detail: "Red Bull", points: "306 pts"),
            ])
        }
    }
}
