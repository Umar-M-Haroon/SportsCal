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
    case premierLeague, laLiga, bundesliga, serieA, ligue1, mls, aLeague

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
            .aLeague: "A-League",
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
        case .aLeague: return "4356"
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
        case .aLeague: return "A-League"
        }
    }

    var league: Leagues? {
        Int(leagueID).flatMap(Leagues.init(rawValue:))
    }

    /// Ranking and columns, shared with the app's standings tables.
    var style: StandingsStyle {
        league.map(StandingsStyle.init(league:)) ?? .soccer
    }

    /// The widget's narrow columns: the app's minus games played and the wide ones,
    /// which move to `largeExtra`.
    var columns: [StandingsColumn] {
        switch style {
        case .soccer: return [.wins, .draws, .losses, .points]
        case .hockey: return [.wins, .losses, .otLosses, .points]
        default: return [.wins, .losses]
        }
    }

    var largeExtra: StandingsColumn? {
        switch style {
        case .soccer: return .goalDifference
        case .hockey: return nil
        default: return .winPercent
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
    /// Stat columns every size shows, after rank and team (e.g. W L OTL PTS for the NHL).
    let columns: [StandingsColumn]
    /// One more column the large size has room for (PCT, GD).
    let largeExtra: StandingsColumn?
}

struct StandingsTeamRow: Identifiable {
    let id = UUID()
    let rank: Int
    let name: String
    let abbreviation: String
    /// Cell text for `StandingsEntry.columns`, in order.
    let values: [String]
    /// Cell text for `StandingsEntry.largeExtra`.
    let extra: String?
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
        StandingsEntry(date: .now, leagueName: "League", teams: [], columns: StandingsLeagueSelection.premierLeague.columns,
                       largeExtra: StandingsLeagueSelection.premierLeague.largeExtra)
    }

    func snapshot(for configuration: StandingsWidgetIntent, in context: Context) async -> StandingsEntry {
        StandingsEntry(date: .now, leagueName: configuration.league.leagueName, teams: [],
                       columns: configuration.league.columns, largeExtra: configuration.league.largeExtra)
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
            rows = parseStandings(standing, maxTeams: maxTeams, league: league)
        }

        // Date the entry now so it displays immediately; refresh hourly via the policy.
        let now = Date()
        let entry = StandingsEntry(
            date: now,
            leagueName: league.leagueName,
            teams: rows,
            columns: league.columns,
            largeExtra: league.largeExtra
        )

        return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3600)))
    }

    private func parseStandings(_ standing: Standing, maxTeams: Int, league: StandingsLeagueSelection) -> [StandingsTeamRow] {
        // Every conference/division in one league-wide list, ordered the way the app's
        // tables order them (the NHL by points, not wins).
        let allEntries = standing.groups.flatMap(\.entries)
        let ranked = league.style.ranked(allEntries, combined: true)
        return ranked.prefix(maxTeams).map { row in
            let e = row.entry
            return StandingsTeamRow(
                rank: row.rank,
                name: e.team?.displayName ?? e.team?.name ?? "Unknown",
                abbreviation: e.team?.abbreviation ?? "???",
                values: league.columns.map { $0.value(for: e) },
                extra: league.largeExtra.map { $0.value(for: e) }
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
            ForEach(entry.columns, id: \.self) { column in
                Text(column.title)
                    .frame(width: columnWidth(column), alignment: .trailing)
            }
            if isLarge, let extra = entry.largeExtra {
                Text(extra.title)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundColor(.secondary)
    }

    private func columnWidth(_ column: StandingsColumn) -> CGFloat {
        let isLarge = family == .systemLarge
        if column == .points || column == .otLosses { return isLarge ? 32 : 28 }
        return isLarge ? 28 : 24
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

            ForEach(Array(entry.columns.enumerated()), id: \.offset) { index, column in
                Text(index < team.values.count ? team.values[index] : "-")
                    .font(.system(size: 9, weight: column == .points ? .medium : .regular))
                    .frame(width: columnWidth(column), alignment: .trailing)
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
