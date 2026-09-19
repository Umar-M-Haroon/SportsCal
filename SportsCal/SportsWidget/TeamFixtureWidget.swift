//
//  TeamFixtureWidget.swift
//  SportsWidgetExtension
//
//  Lock screen widget pinned to one team: its next fixture on whatever day that
//  falls, and "likely live" once it kicks off. The "Upcoming Games" widget only looks at a single day
//  across every sport, so a team that isn't playing today never shows up there.
//

#if os(iOS)
import SwiftUI
import WidgetKit
import AppIntents
import SportsCalModel

// MARK: - Team Entity

/// Identified by TheSportsDB team ID (unlike Siri's name-keyed `TeamEntity`) so a
/// configured widget survives team renames in the teams cache.
struct WidgetTeamEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    static var defaultQuery = WidgetTeamQuery()

    var id: String
    var name: String
    var shortName: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String, shortName: String?) {
        self.id = id
        self.name = name
        self.shortName = shortName
    }

    init?(team: Team) {
        guard let id = team.idTeam, !id.isEmpty, let name = team.strTeam, !name.isEmpty else { return nil }
        self.init(id: id, name: name, shortName: team.strTeamShort)
    }
}

struct WidgetTeamQuery: EntityStringQuery {
    /// Cap on search results — the teams cache holds every league's teams.
    private static let searchLimit = 50

    func entities(for identifiers: [String]) async throws -> [WidgetTeamEntity] {
        identifiers.compactMap { id in
            TeamsManager.shared.team(byID: id).flatMap(WidgetTeamEntity.init(team:))
        }
    }

    func entities(matching string: String) async throws -> [WidgetTeamEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return try await suggestedEntities() }
        let matches = TeamsManager.shared.teams.filter { team in
            if team.strTeam?.localizedCaseInsensitiveContains(query) == true { return true }
            if team.strTeamShort?.localizedCaseInsensitiveContains(query) == true { return true }
            return team.strAlternate?.localizedCaseInsensitiveContains(query) == true
        }
        return uniqueEntities(matches.sorted { ($0.strTeam ?? "") < ($1.strTeam ?? "") })
            .prefix(Self.searchLimit)
            .map { $0 }
    }

    /// Favorites first, then teams playing in the cached upcoming schedule.
    func suggestedEntities() async throws -> [WidgetTeamEntity] {
        let manager = TeamsManager.shared
        let favoriteTeams = Favorites().teamIDs
            .compactMap { manager.team(byID: $0) }
            .sorted { ($0.strTeam ?? "") < ($1.strTeam ?? "") }

        let scheduledTeams = (WidgetDataStore.readSnapshot()?.games ?? [])
            .filter { !$0.isIndividualSport }
            .flatMap { [$0.strHomeTeam, $0.strAwayTeam] }
            .compactMap { manager.team(byNameOrAlias: $0) }

        return uniqueEntities(favoriteTeams + scheduledTeams)
    }

    private func uniqueEntities(_ teams: [Team]) -> [WidgetTeamEntity] {
        var seen = Set<String>()
        return teams.compactMap { team in
            guard let entity = WidgetTeamEntity(team: team), seen.insert(entity.id).inserted else { return nil }
            return entity
        }
    }
}

// MARK: - Intent

struct TeamFixtureIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Team Fixture"
    static var description: IntentDescription = "Follow one team's next game on your Lock Screen"

    @Parameter(title: "Team")
    var team: WidgetTeamEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$team)'s next game")
    }
}

// MARK: - Timeline

struct TeamFixtureEntry: TimelineEntry {
    let date: Date
    let team: WidgetTeamEntity?
    let game: Game?
    var phase: FixturePhase?
    /// The schedule couldn't be fetched, so "no upcoming games" would be a guess.
    var loadFailed = false
    var relevance: TimelineEntryRelevance?

    /// Whether the configured team is the home side of `game`.
    var isHome: Bool {
        guard let game, let team else { return true }
        return TeamFixtureProvider.name(game.strHomeTeam, refersTo: team)
    }

    var opponentName: String? {
        guard let game else { return nil }
        return isHome ? game.strAwayTeam : game.strHomeTeam
    }
}

/// Never shows a live score: a widget can't refresh often enough for one to be
/// trustworthy. Once kickoff passes it says the game is likely live and sends people
/// to the app or their Live Activity.
struct TeamFixtureProvider: AppIntentTimelineProvider {
    private static let refreshInterval: TimeInterval = 60 * 60
    private static let retryInterval: TimeInterval = 15 * 60
    /// How far ahead to pre-render phase changes (kickoff, likely full time).
    private static let lookahead: TimeInterval = 24 * 60 * 60

    func placeholder(in context: Context) -> TeamFixtureEntry {
        Self.sampleEntry
    }

    func snapshot(for configuration: TeamFixtureIntent, in context: Context) async -> TeamFixtureEntry {
        guard let team = configuration.team else { return Self.sampleEntry }
        let lookup = await Self.games(for: team)
        return Self.entry(at: Date(), team: team, lookup: lookup)
    }

    func timeline(for configuration: TeamFixtureIntent, in context: Context) async -> Timeline<TeamFixtureEntry> {
        let now = Date()
        guard let team = configuration.team else {
            return Timeline(entries: [TeamFixtureEntry(date: now, team: nil, game: nil)], policy: .never)
        }

        let lookup = await Self.games(for: team)
        // One entry per phase change so the widget flips to "likely live" at kickoff
        // (and back off at likely full time) without spending a reload.
        let transitions = lookup.games.flatMap { game -> [Date] in
            guard let kickoff = game.standardDate else { return [] }
            return FixtureSelection.transitions(kickoff: kickoff, length: Self.length(of: game), after: now)
        }
        let dates = Set(transitions.filter { $0 < now.addingTimeInterval(Self.lookahead) }).sorted()
        let entries = ([now] + dates).map { Self.entry(at: $0, team: team, lookup: lookup) }

        let wait = lookup.failed ? Self.retryInterval : Self.refreshInterval
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(wait)))
    }

    // MARK: Data

    private struct Lookup {
        var games: [Game]
        var failed = false
    }

    /// The team's games from the app's snapshot, or from the server when the snapshot
    /// has nothing to show for them.
    private static func games(for team: WidgetTeamEntity) async -> Lookup {
        let now = Date()
        let cached = teamGames(WidgetDataStore.readSnapshot()?.games ?? [], for: team)
        if pick(cached, at: now) != nil { return Lookup(games: cached) }

        // The snapshot only carries the next ~30 games across all sports, so most
        // teams' fixtures aren't in it. The widget endpoint puts games involving any
        // of these exact names first — send the aliases too, since the schedule may
        // spell the team differently from the teams cache.
        do {
            let result = try await NetworkHandler.getWidgetScheduleFor(sports: [], limit: 10, favorites: names(for: team))
            return Lookup(games: teamGames(result.games, for: team))
        } catch {
            AppLogger.widget.error("[teamFixture] fetch failed: \(error.localizedDescription)")
            return Lookup(games: cached, failed: true)
        }
    }

    private static func names(for team: WidgetTeamEntity) -> [String] {
        let aliases = TeamsManager.shared.team(byID: team.id)?.strAlternate?
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(",") } ?? []
        var seen = Set<String>()
        return ([team.name] + aliases).filter { seen.insert($0).inserted }
    }

    private static func teamGames(_ games: [Game], for team: WidgetTeamEntity) -> [Game] {
        games.filter { !$0.isIndividualSport && involves($0, team) }
    }

    // MARK: Game selection

    private static func entry(at date: Date, team: WidgetTeamEntity, lookup: Lookup) -> TeamFixtureEntry {
        let picked = pick(lookup.games, at: date)

        let kickoff = picked?.game.standardDate
        let relevance: TimelineEntryRelevance
        switch picked?.phase {
        case .likelyLive:
            let end = kickoff.map { $0.addingTimeInterval(length(of: picked?.game)) } ?? date
            relevance = TimelineEntryRelevance(score: 100, duration: max(end.timeIntervalSince(date), 0))
        case .upcoming where (kickoff?.timeIntervalSince(date) ?? .infinity) < 60 * 60:
            relevance = TimelineEntryRelevance(score: 50)
        default:
            relevance = TimelineEntryRelevance(score: 10)
        }

        return TeamFixtureEntry(
            date: date,
            team: team,
            game: picked?.game,
            phase: picked?.phase,
            loadFailed: lookup.failed && picked == nil,
            relevance: relevance
        )
    }

    /// Likely-live game first, then the next upcoming one, then today's result.
    private static func pick(_ games: [Game], at date: Date) -> (game: Game, phase: FixturePhase)? {
        FixtureSelection.pick(
            from: games,
            at: date,
            kickoff: \.standardDate,
            isCompleted: isCompleted,
            length: length(of:)
        )
    }

    private static func isCompleted(_ game: Game) -> Bool {
        game.isCompleted == true || game.displayStatus?.hasPrefix("Final") == true
    }

    private static func length(of game: Game?) -> TimeInterval {
        (game?.sportType ?? .soccer).typicalGameLength
    }

    private static func involves(_ game: Game, _ team: WidgetTeamEntity) -> Bool {
        name(game.strHomeTeam, refersTo: team) || name(game.strAwayTeam, refersTo: team)
    }

    /// Matches on name or alias rather than the game's raw team ID — ESPN and
    /// TheSportsDB IDs share a namespace and collide across sports.
    static func name(_ name: String, refersTo team: WidgetTeamEntity) -> Bool {
        if name == team.name { return true }
        return TeamsManager.shared.teamID(forName: name) == team.id
    }

    static var sampleEntry: TeamFixtureEntry {
        let kickoff = Calendar.current.date(byAdding: .hour, value: 26, to: Date()) ?? Date()
        let game = Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4356", strLeague: "A-League", idHomeTeam: "140093", idAwayTeam: "140094", strHomeTeam: "Sydney FC", strAwayTeam: "Melbourne Victory", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: nil, intAwayScore: nil, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: nil, strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: kickoff.ISO8601Format(), isoDate: nil)
        return TeamFixtureEntry(
            date: Date(),
            team: WidgetTeamEntity(id: "140093", name: "Sydney FC", shortName: "SYD"),
            game: game,
            phase: .upcoming
        )
    }

    static var sampleLiveEntry: TeamFixtureEntry {
        let kickoff = Date().addingTimeInterval(-40 * 60)
        let game = Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4356", strLeague: "A-League", idHomeTeam: "140094", idAwayTeam: "140093", strHomeTeam: "Melbourne Victory", strAwayTeam: "Sydney FC", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: nil, intAwayScore: nil, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: nil, strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: kickoff.ISO8601Format(), isoDate: nil)
        return TeamFixtureEntry(
            date: Date(),
            team: WidgetTeamEntity(id: "140093", name: "Sydney FC", shortName: "SYD"),
            game: game,
            phase: .likelyLive
        )
    }
}

// MARK: - Views

struct TeamFixtureEntryView: View {
    var entry: TeamFixtureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(deepLink)
    }

    private var deepLink: URL? {
        guard let id = entry.game?.idEvent else { return nil }
        return URL(string: "sportscal://game/\(id)")
    }

    private var versus: String { entry.isHome ? "vs" : "@" }

    // MARK: Circular

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if entry.team == nil {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .widgetAccentable()
                    Text("Team")
                        .font(.system(size: 9, design: .rounded).weight(.semibold))
                } else if let game = entry.game {
                    Text(entry.phase == .likelyLive ? "LIVE" : versus)
                        .font(.system(size: 8, design: .rounded).weight(entry.phase == .likelyLive ? .heavy : .regular))
                        .foregroundStyle(entry.phase == .likelyLive ? .primary : .secondary)
                    Text(opponentCode)
                        .font(.system(size: 14, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    if entry.phase == .upcoming, let date = game.standardDate {
                        Text(compactWhen(date))
                            .font(.system(size: 8, design: .rounded).weight(.semibold))
                            .minimumScaleFactor(0.7)
                    } else if entry.phase == .ended {
                        Text(finalScore(game) ?? "Ended")
                            .font(.system(size: 8, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                } else {
                    Text(teamCode)
                        .font(.system(size: 12, design: .rounded).weight(.bold))
                        .widgetAccentable()
                    Text(entry.loadFailed ? "Offline" : "No games")
                        .font(.system(size: 7, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .padding(4)
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.team == nil {
                Label("Team Fixture", systemImage: "person.2.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .widgetAccentable()
                Text("Touch and hold to choose a team")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let game = entry.game {
                HStack(spacing: 4) {
                    Image(systemName: (game.sportType ?? .soccer).widgetSystemImage)
                        .font(.caption2)
                        .widgetAccentable()
                    Text(entry.team?.name ?? "")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                Text("\(versus) \(entry.opponentName ?? "")")
                    .font(.system(.subheadline, design: .rounded))
                Group {
                    switch entry.phase {
                    case .likelyLive:
                        Text("Likely live · Tap for the score")
                    case .ended:
                        Text(endedDetail(game))
                    default:
                        if let date = game.standardDate { Text(fullWhen(date)) }
                    }
                }
                .font(.system(size: 11, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            } else {
                Text(entry.team?.name ?? "")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .widgetAccentable()
                Text(entry.loadFailed ? "Couldn't load games" : "No upcoming games")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Inline

    @ViewBuilder
    private var inline: some View {
        if entry.team == nil {
            Text("Choose a team")
        } else if let game = entry.game {
            switch entry.phase {
            case .likelyLive:
                Text("\(teamCode) \(versus) \(opponentCode) · Likely live")
            case .ended:
                Text("\(teamCode) \(versus) \(opponentCode) · \(finalScore(game) ?? "Ended")")
            default:
                if let date = game.standardDate {
                    Text("\(teamCode) \(versus) \(opponentCode) · \(compactWhen(date))")
                } else {
                    Text("\(teamCode) \(versus) \(opponentCode)")
                }
            }
        } else {
            Text("\(teamCode) · \(entry.loadFailed ? "Couldn't load games" : "No upcoming games")")
        }
    }

    // MARK: Formatting

    private var teamCode: String {
        guard let team = entry.team else { return "" }
        return Team.shortCode(strTeamShort: team.shortName, name: team.name)
    }

    private var opponentCode: String {
        guard let name = entry.opponentName else { return "" }
        let short = TeamsManager.shared.team(byNameOrAlias: name)?.strTeamShort
        return Team.shortCode(strTeamShort: short, name: name)
    }

    /// Final score from the configured team's perspective ("2–1" means they won), only
    /// once the game is known to be complete — never a mid-game score.
    private func finalScore(_ game: Game) -> String? {
        guard game.isCompleted == true || game.displayStatus?.hasPrefix("Final") == true,
              let home = game.intHomeScore, let away = game.intAwayScore else { return nil }
        return entry.isHome ? "\(home)–\(away)" : "\(away)–\(home)"
    }

    /// "Final · 2–1" when the result is known; otherwise the status ("Postponed") or a
    /// nudge to open the game.
    private func endedDetail(_ game: Game) -> String {
        if let score = finalScore(game) { return "\(game.displayStatus ?? "Final") · \(score)" }
        if let status = game.displayStatus { return status }
        return "Tap for the result"
    }

    /// Days from the entry's date — entries are rendered ahead of time, so "today"
    /// means the day the entry shows, not the day it was built.
    private func daysAway(_ date: Date) -> Int? {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date), to: calendar.startOfDay(for: date)).day
    }

    /// "7:30 PM" today, "Sat" within the week, "Oct 4" beyond.
    private func compactWhen(_ date: Date) -> String {
        switch daysAway(date) {
        case 0: return date.formatted(date: .omitted, time: .shortened)
        case let days? where days < 7: return date.formatted(.dateTime.weekday(.abbreviated))
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// "Today 7:30 PM", "Tomorrow 7:30 PM", "Sat 7:30 PM", or "Oct 4, 7:30 PM".
    private func fullWhen(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        switch daysAway(date) {
        case 0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        default: return "\(compactWhen(date)), \(time)"
        }
    }
}


// MARK: - Widget

struct TeamFixtureWidget: Widget {
    let kind = "TeamFixtureWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TeamFixtureIntent.self, provider: TeamFixtureProvider()) { entry in
            TeamFixtureEntryView(entry: entry)
        }
        .configurationDisplayName("Team Fixture")
        .description("One team's next game, on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .accessoryRectangular) {
    TeamFixtureWidget()
} timeline: {
    TeamFixtureProvider.sampleEntry
    TeamFixtureProvider.sampleLiveEntry
}

#Preview(as: .accessoryCircular) {
    TeamFixtureWidget()
} timeline: {
    TeamFixtureProvider.sampleEntry
    TeamFixtureProvider.sampleLiveEntry
}
#endif
