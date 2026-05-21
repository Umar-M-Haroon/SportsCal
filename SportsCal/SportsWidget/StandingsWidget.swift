//
//  StandingsWidget.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 4/12/26.
//

#if os(iOS)
import SwiftUI
import WidgetKit
import AppIntents
import SportsCalModel

// MARK: - Intent

enum StandingsLeagueSelection: String, AppEnum {
    case nba, nfl, nhl, mlb
    case premierLeague, laLiga, bundesliga, serieA, ligue1, mls

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "League" }

    static var caseDisplayRepresentations: [StandingsLeagueSelection: DisplayRepresentation] {
        [
            .nba: "NBA",
            .nfl: "NFL",
            .nhl: "NHL",
            .mlb: "MLB",
            .premierLeague: "Premier League",
            .laLiga: "La Liga",
            .bundesliga: "Bundesliga",
            .serieA: "Serie A",
            .ligue1: "Ligue 1",
            .mls: "MLS",
        ]
    }

    var leagueID: String {
        switch self {
        case .nba: return "4387"
        case .nfl: return "4391"
        case .nhl: return "4380"
        case .mlb: return "4424"
        case .premierLeague: return "4328"
        case .laLiga: return "4335"
        case .bundesliga: return "4331"
        case .serieA: return "4332"
        case .ligue1: return "4334"
        case .mls: return "4346"
        }
    }

    var leagueName: String {
        switch self {
        case .nba: return "NBA"
        case .nfl: return "NFL"
        case .nhl: return "NHL"
        case .mlb: return "MLB"
        case .premierLeague: return "Premier League"
        case .laLiga: return "La Liga"
        case .bundesliga: return "Bundesliga"
        case .serieA: return "Serie A"
        case .ligue1: return "Ligue 1"
        case .mls: return "MLS"
        }
    }

    /// Whether this league uses points (soccer) vs W-L record (US sports)
    var usesPoints: Bool {
        switch self {
        case .nba, .nfl, .nhl, .mlb: return false
        case .premierLeague, .laLiga, .bundesliga, .serieA, .ligue1, .mls: return true
        }
    }
}

struct StandingsWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Standings"
    static var description: IntentDescription = "Show league standings"

    @Parameter(title: "League", default: .premierLeague)
    var league: StandingsLeagueSelection

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$league) standings")
    }
}

// MARK: - Timeline Entry

struct StandingsEntry: TimelineEntry {
    let date: Date
    let leagueName: String
    let teams: [StandingsTeamRow]
    let usesPoints: Bool
}

struct StandingsTeamRow: Identifiable {
    let id = UUID()
    let rank: Int
    let name: String
    let abbreviation: String
    let wins: String
    let losses: String
    let draws: String?
    let points: String?
    let extra: String? // PCT, GB, GD, etc.
}

// MARK: - Standings Cache

private enum StandingsCache {
    private static let suiteName = "group.Komodo.SportsCal"

    struct CachedStandings: Codable {
        let data: Data
        let cachedAt: Date
    }

    static func read(leagueID: String) -> Standing? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let cacheData = defaults.data(forKey: "standings-cache-\(leagueID)"),
              let cached = try? JSONDecoder().decode(CachedStandings.self, from: cacheData) else {
            return nil
        }
        // 1 hour TTL
        guard Date().timeIntervalSince(cached.cachedAt) < 3600 else { return nil }
        return try? JSONDecoder().decode(Standing.self, from: cached.data)
    }

    static func write(_ standing: Standing, leagueID: String) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(standing) else { return }
        let cached = CachedStandings(data: data, cachedAt: Date())
        if let cacheData = try? JSONEncoder().encode(cached) {
            defaults.set(cacheData, forKey: "standings-cache-\(leagueID)")
        }
    }
}

// MARK: - Provider

struct StandingsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StandingsEntry {
        StandingsEntry(date: .now, leagueName: "League", teams: [], usesPoints: true)
    }

    func snapshot(for configuration: StandingsWidgetIntent, in context: Context) async -> StandingsEntry {
        StandingsEntry(date: .now, leagueName: configuration.league.leagueName, teams: [], usesPoints: configuration.league.usesPoints)
    }

    func timeline(for configuration: StandingsWidgetIntent, in context: Context) async -> Timeline<StandingsEntry> {
        let league = configuration.league
        let maxTeams = context.family == .systemLarge ? 20 : 8

        var rows: [StandingsTeamRow] = []

        // Try cache first, then network
        var standing = StandingsCache.read(leagueID: league.leagueID)
        if standing == nil {
            standing = try? await NetworkHandler.getStandings(for: league.leagueID)
            if let standing {
                StandingsCache.write(standing, leagueID: league.leagueID)
            }
        }

        if let standing {
            rows = parseStandings(standing, maxTeams: maxTeams, usesPoints: league.usesPoints)
        }

        let entry = StandingsEntry(
            date: Date().addingTimeInterval(3600),
            leagueName: league.leagueName,
            teams: rows,
            usesPoints: league.usesPoints
        )

        return Timeline(entries: [entry], policy: .after(entry.date))
    }

    private func parseStandings(_ standing: Standing, maxTeams: Int, usesPoints: Bool) -> [StandingsTeamRow] {
        // Collect all entries from all divisions/conferences
        // Use fully qualified type to avoid conflict with StandingsEntry
        var allEntries: [(standingsEntry: SportsCalModel.Entry, division: String?)] = []

        if let children = standing.standings.children {
            for child in children {
                if let entries = child.standings?.entries {
                    for e in entries {
                        allEntries.append((e, child.name))
                    }
                }
            }
        }

        // Sort by standings order
        if usesPoints {
            allEntries.sort { (lhs: (standingsEntry: SportsCalModel.Entry, division: String?), rhs: (standingsEntry: SportsCalModel.Entry, division: String?)) in
                let lhsPoints = lhs.standingsEntry.stats?.first(where: { $0.name == "points" })?.value ?? 0
                let rhsPoints = rhs.standingsEntry.stats?.first(where: { $0.name == "points" })?.value ?? 0
                return lhsPoints > rhsPoints
            }
        } else {
            allEntries.sort { (lhs: (standingsEntry: SportsCalModel.Entry, division: String?), rhs: (standingsEntry: SportsCalModel.Entry, division: String?)) in
                let lhsWins = lhs.standingsEntry.stats?.first(where: { $0.name == "wins" })?.value ?? 0
                let rhsWins = rhs.standingsEntry.stats?.first(where: { $0.name == "wins" })?.value ?? 0
                if lhsWins != rhsWins { return lhsWins > rhsWins }
                let lhsLosses = lhs.standingsEntry.stats?.first(where: { $0.name == "losses" })?.value ?? 0
                let rhsLosses = rhs.standingsEntry.stats?.first(where: { $0.name == "losses" })?.value ?? 0
                return lhsLosses < rhsLosses
            }
        }

        return allEntries.prefix(maxTeams).enumerated().map { index, item in
            let e = item.standingsEntry
            let stats = e.stats ?? []

            let wins = stats.first(where: { $0.name == "wins" })?.displayValue ?? "-"
            let losses = stats.first(where: { $0.name == "losses" })?.displayValue ?? "-"
            let draws = stats.first(where: { $0.name == "ties" || $0.name == "draws" })?.displayValue
            let points = stats.first(where: { $0.name == "points" })?.displayValue

            let extra: String?
            if usesPoints {
                extra = stats.first(where: { $0.name == "goalDifference" || $0.name == "pointDifferential" })?.displayValue
            } else {
                extra = stats.first(where: { $0.name == "winPercent" || $0.name == "gamesBehind" })?.displayValue
            }

            return StandingsTeamRow(
                rank: index + 1,
                name: e.team?.displayName ?? e.team?.name ?? "Unknown",
                abbreviation: e.team?.abbreviation ?? "???",
                wins: wins,
                losses: losses,
                draws: draws,
                points: points,
                extra: extra
            )
        }
    }
}

// MARK: - View

struct StandingsWidgetView: View {
    let entry: StandingsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(entry.leagueName)
                    .font(.system(size: 12, weight: .semibold))
                Text("Standings")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            // Column headers
            columnHeaders
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

            if entry.teams.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No standings available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                // Standings rows — fill available space evenly
                VStack(spacing: 0) {
                    ForEach(entry.teams) { team in
                        teamRow(team)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(8)
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    @ViewBuilder
    private var columnHeaders: some View {
        let isLarge = family == .systemLarge

        HStack(spacing: 0) {
            Text("#")
                .frame(width: 18, alignment: .leading)
            Text("Team")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W")
                .frame(width: isLarge ? 28 : 24, alignment: .trailing)
            if entry.usesPoints {
                Text("D")
                    .frame(width: isLarge ? 28 : 24, alignment: .trailing)
            }
            Text("L")
                .frame(width: isLarge ? 28 : 24, alignment: .trailing)
            if entry.usesPoints {
                Text("Pts")
                    .frame(width: isLarge ? 32 : 28, alignment: .trailing)
            }
            if isLarge, let _ = entry.teams.first?.extra {
                Text(entry.usesPoints ? "GD" : "PCT")
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func teamRow(_ team: StandingsTeamRow) -> some View {
        let isLarge = family == .systemLarge

        HStack(spacing: 0) {
            Text(verbatim: "\(team.rank)")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .leading)

            Text(team.abbreviation)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(team.wins)
                .font(.system(size: 9))
                .frame(width: isLarge ? 28 : 24, alignment: .trailing)

            if entry.usesPoints {
                Text(team.draws ?? "-")
                    .font(.system(size: 9))
                    .frame(width: isLarge ? 28 : 24, alignment: .trailing)
            }

            Text(team.losses)
                .font(.system(size: 9))
                .frame(width: isLarge ? 28 : 24, alignment: .trailing)

            if entry.usesPoints {
                Text(team.points ?? "-")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: isLarge ? 32 : 28, alignment: .trailing)
            }

            if isLarge, let extra = team.extra {
                Text(extra)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 1.5)
    }
}

// MARK: - Widget

struct StandingsWidget: Widget {
    let kind = "StandingsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StandingsWidgetIntent.self, provider: StandingsProvider()) { entry in
            StandingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Standings")
        .description("League standings table")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
#endif
