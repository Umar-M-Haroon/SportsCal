//
//  TeamFixtureWidget.swift
//  SportsWidgetExtension
//
//  Widget pinned to one team: its next fixture on whatever day that falls, and
//  "likely live" once it kicks off. Lock Screen sizes show just that game; Home
//  Screen medium/large add the fixtures after it. The "Upcoming Games" widget only
//  looks at a single day across every sport, so a team that isn't playing today
//  never shows up there.
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
    static var description: IntentDescription = "Follow one team's next game and upcoming fixtures"

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
    /// Fixtures after `game`, soonest first — only filled for Home Screen sizes.
    var upcoming: [Game] = []
    /// Badge image data keyed by TheSportsDB team ID.
    var badges: [String: Data] = [:]
    /// The schedule couldn't be fetched, so "no upcoming games" would be a guess.
    var loadFailed = false
    var relevance: TimelineEntryRelevance?

    /// Whether the configured team is the home side of `game`.
    var isHome: Bool {
        guard let game, let team else { return true }
        return TeamFixtureProvider.name(game.strHomeTeam, refersTo: team)
    }

    var opponentName: String? {
        game.flatMap(opponent(in:))
    }

    func isHome(in game: Game) -> Bool {
        guard let team else { return true }
        return TeamFixtureProvider.name(game.strHomeTeam, refersTo: team)
    }

    func opponent(in game: Game) -> String {
        isHome(in: game) ? game.strAwayTeam : game.strHomeTeam
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
        let extra = Self.upcomingCount(for: context.family)
        let lookup = await Self.games(for: team, extra: extra)
        let badges = await Self.badges(for: team, games: lookup.games, family: context.family)
        return Self.entry(at: Date(), team: team, lookup: lookup, extra: extra, badges: badges)
    }

    func timeline(for configuration: TeamFixtureIntent, in context: Context) async -> Timeline<TeamFixtureEntry> {
        let now = Date()
        guard let team = configuration.team else {
            return Timeline(entries: [TeamFixtureEntry(date: now, team: nil, game: nil)], policy: .never)
        }

        let extra = Self.upcomingCount(for: context.family)
        let lookup = await Self.games(for: team, extra: extra)
        let badges = await Self.badges(for: team, games: lookup.games, family: context.family)
        // One entry per phase change so the widget flips to "likely live" at kickoff
        // (and back off at likely full time) without spending a reload.
        let transitions = lookup.games.flatMap { game -> [Date] in
            guard let kickoff = game.standardDate else { return [] }
            return FixtureSelection.transitions(kickoff: kickoff, length: Self.length(of: game), after: now)
        }
        let dates = Set(transitions.filter { $0 < now.addingTimeInterval(Self.lookahead) }).sorted()
        let entries = ([now] + dates).map {
            Self.entry(at: $0, team: team, lookup: lookup, extra: extra, badges: badges)
        }

        let wait = lookup.failed ? Self.retryInterval : Self.refreshInterval
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(wait)))
    }

    // MARK: Data

    private struct Lookup {
        var games: [Game]
        var failed = false
    }

    /// Fixtures listed after the main one: none on the Lock Screen or in small.
    private static func upcomingCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemMedium: return 3
        case .systemLarge: return 4
        default: return 0
        }
    }

    /// The team's games from the app's snapshot, or from the server when the snapshot
    /// doesn't have the next game plus `extra` more.
    private static func games(for team: WidgetTeamEntity, extra: Int) async -> Lookup {
        let now = Date()
        let cached = teamGames(WidgetDataStore.readSnapshot()?.games ?? [], for: team)
        let cachedUpcoming = cached.filter { ($0.standardDate ?? .distantPast) > now }.count
        if pick(cached, at: now) != nil, cachedUpcoming > extra { return Lookup(games: cached) }

        // The snapshot only carries the next ~30 games across all sports, so most
        // teams' fixtures aren't in it. The widget endpoint puts games involving any
        // of these exact names first — send the aliases too, since the schedule may
        // spell the team differently from the teams cache.
        do {
            let result = try await NetworkHandler.getWidgetScheduleFor(sports: [], limit: 10 + extra * 2, favorites: names(for: team))
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

    /// Badges for the team and the opponents in its next few games. Home Screen only —
    /// the Lock Screen renders monochrome text. Failures just fall back to initials.
    private static func badges(for team: WidgetTeamEntity, games: [Game], family: WidgetFamily) async -> [String: Data] {
        guard [.systemSmall, .systemMedium, .systemLarge].contains(family) else { return [:] }
        let manager = TeamsManager.shared
        let now = Date()
        let opponents = games
            .filter { ($0.standardDate ?? .distantPast) > now.addingTimeInterval(-lookahead) }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .prefix(upcomingCount(for: family) + 2)
            .compactMap { game in
                manager.team(byNameOrAlias: name(game.strHomeTeam, refersTo: team) ? game.strAwayTeam : game.strHomeTeam)
            }
        var seen = Set<String>()
        let wanted = ([manager.team(byID: team.id)].compactMap { $0 } + opponents).compactMap { team -> (String, String)? in
            guard let id = team.idTeam, let url = team.strTeamBadge, seen.insert(id).inserted else { return nil }
            return (id, url)
        }

        return await withTaskGroup(of: (String, Data?).self) { group in
            for (id, url) in wanted {
                group.addTask { (id, try? await WidgetImageCache.shared.getImage(for: id, imageURL: url)) }
            }
            var result: [String: Data] = [:]
            for await (id, data) in group {
                if let data { result[id] = data }
            }
            return result
        }
    }

    // MARK: Game selection

    private static func entry(
        at date: Date,
        team: WidgetTeamEntity,
        lookup: Lookup,
        extra: Int = 0,
        badges: [String: Data] = [:]
    ) -> TeamFixtureEntry {
        let picked = pick(lookup.games, at: date)
        let upcoming = lookup.games
            .filter { game in
                guard let kickoff = game.standardDate, kickoff > date else { return false }
                return game != picked?.game
            }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .prefix(extra)

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
            upcoming: Array(upcoming),
            badges: badges,
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

    private static let sampleTeam = WidgetTeamEntity(id: "140093", name: "Sydney FC", shortName: "SYD")

    private static func sampleGame(_ home: String, _ away: String, hoursFromNow: Double) -> Game {
        let kickoff = Date().addingTimeInterval(hoursFromNow * 60 * 60)
        return Game(idLeague: "4356", strLeague: "A-League", strHomeTeam: home, strAwayTeam: away, strTimestamp: kickoff.ISO8601Format(), isoDate: nil)
    }

    private static let sampleUpcoming = [
        sampleGame("Western Sydney Wanderers", "Sydney FC", hoursFromNow: 24 * 7 + 2),
        sampleGame("Sydney FC", "Adelaide United", hoursFromNow: 24 * 14 + 1),
        sampleGame("Sydney FC", "Brisbane Roar", hoursFromNow: 24 * 20 + 3),
        sampleGame("Perth Glory", "Sydney FC", hoursFromNow: 24 * 27),
    ]

    static var sampleEntry: TeamFixtureEntry {
        TeamFixtureEntry(
            date: Date(),
            team: sampleTeam,
            game: sampleGame("Sydney FC", "Melbourne Victory", hoursFromNow: 26),
            phase: .upcoming,
            upcoming: sampleUpcoming
        )
    }

    static var sampleLiveEntry: TeamFixtureEntry {
        TeamFixtureEntry(
            date: Date(),
            team: sampleTeam,
            game: sampleGame("Melbourne Victory", "Sydney FC", hoursFromNow: -0.7),
            phase: .likelyLive,
            upcoming: sampleUpcoming
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
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            case .systemLarge: large
            default: small
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
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

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.team == nil {
                chooseTeamPrompt
            } else if let game = entry.game {
                HStack(spacing: 6) {
                    badge(teamID: entry.team?.id, name: entry.team?.name ?? "", size: 22)
                    Text(teamCode)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(WidgetTokens.ink)
                    Spacer(minLength: 0)
                    sportIcon(game)
                }
                Spacer(minLength: 0)
                Text(versus)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WidgetTokens.inkSoft)
                HStack(spacing: 8) {
                    badge(teamID: opponentID(entry.opponentName), name: entry.opponentName ?? "", size: 30)
                    Text(entry.opponentName ?? "")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(WidgetTokens.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                status(game)
            } else {
                noGames
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: WidgetTokens.space3) {
            small
                .frame(maxWidth: .infinity)
            if entry.game != nil {
                Rectangle()
                    .fill(WidgetTokens.inkFaint.opacity(0.4))
                    .frame(width: 0.5)
                upcomingList(title: "Next")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Large

    private var large: some View {
        VStack(alignment: .leading, spacing: WidgetTokens.space3) {
            if entry.team == nil {
                chooseTeamPrompt
            } else if let game = entry.game {
                HStack(spacing: 8) {
                    badge(teamID: entry.team?.id, name: entry.team?.name ?? "", size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.team?.name ?? "")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(WidgetTokens.ink)
                        if let league = leagueName(game) {
                            Text(league)
                                .font(.caption2)
                                .foregroundStyle(WidgetTokens.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                    sportIcon(game)
                }
                heroCard(game)
                upcomingList(title: "Upcoming")
                Spacer(minLength: 0)
                WidgetUpdatedLabel(date: entry.date)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                noGames
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func heroCard(_ game: Game) -> some View {
        let home = entry.isHome
        let us = (id: entry.team?.id, name: entry.team?.name ?? "", code: teamCode)
        let them = (id: opponentID(entry.opponentName), name: entry.opponentName ?? "", code: opponentCode)
        let left = home ? us : them
        let right = home ? them : us
        return HStack(spacing: WidgetTokens.space2) {
            heroSide(id: left.id, name: left.name, code: left.code)
            VStack(spacing: 4) {
                Text(home ? "vs" : "@")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WidgetTokens.inkSoft)
                status(game)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            heroSide(id: right.id, name: right.name, code: right.code)
        }
        .padding(WidgetTokens.space3)
        .background(WidgetTokens.surface, in: RoundedRectangle(cornerRadius: WidgetTokens.radiusMD))
    }

    private func heroSide(id: String?, name: String, code: String) -> some View {
        VStack(spacing: 4) {
            badge(teamID: id, name: name, size: 44)
            Text(code)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(WidgetTokens.ink)
        }
        .frame(width: 64)
    }

    // MARK: Shared pieces

    private var chooseTeamPrompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Team Fixture", systemImage: "person.2.fill")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(WidgetTokens.ink)
            Text("Touch and hold to choose a team")
                .font(.caption)
                .foregroundStyle(WidgetTokens.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var noGames: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                badge(teamID: entry.team?.id, name: entry.team?.name ?? "", size: 22)
                Text(entry.team?.name ?? "")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(WidgetTokens.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entry.loadFailed ? "Couldn't load games" : "No upcoming games")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(WidgetTokens.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// When the game is, or that it's likely under way — never a live score.
    @ViewBuilder
    private func status(_ game: Game) -> some View {
        switch entry.phase {
        case .likelyLive:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Circle().fill(WidgetTokens.live).frame(width: 6, height: 6)
                    Text("Likely live")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(WidgetTokens.live)
                }
                Text("Tap for the score")
                    .font(.caption2)
                    .foregroundStyle(WidgetTokens.inkSoft)
            }
        case .ended:
            Text(endedDetail(game))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetTokens.inkSoft)
        default:
            if let date = game.standardDate {
                Text(fullWhen(date))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WidgetTokens.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder
    private func upcomingList(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTokens.inkSoft)
            if entry.upcoming.isEmpty {
                Text("Nothing else scheduled yet")
                    .font(.caption)
                    .foregroundStyle(WidgetTokens.inkSoft)
            } else {
                ForEach(entry.upcoming) { game in
                    if let id = game.idEvent, let url = URL(string: "sportscal://game/\(id)") {
                        Link(destination: url) { upcomingRow(game) }
                    } else {
                        upcomingRow(game)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func upcomingRow(_ game: Game) -> some View {
        let opponent = entry.opponent(in: game)
        return HStack(spacing: 8) {
            if let date = game.standardDate {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTokens.inkSoft)
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTokens.ink)
                }
                .frame(width: 26)
            }
            badge(teamID: opponentID(opponent), name: opponent, size: 18)
            Text("\(entry.isHome(in: game) ? "vs" : "@") \(opponent)")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(WidgetTokens.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if family == .systemLarge, let date = game.standardDate {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTokens.inkSoft)
            }
        }
    }

    /// Team badge from the provider's prefetch, or initials in a tinted circle.
    @ViewBuilder
    private func badge(teamID: String?, name: String, size: CGFloat) -> some View {
        if let teamID, let data = entry.badges[teamID], let image = widgetImage(from: data) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(WidgetTokens.alt)
                .overlay(
                    Text(Team.shortCode(strTeamShort: nil, name: name))
                        .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTokens.inkSoft)
                        .minimumScaleFactor(0.5)
                )
                .frame(width: size, height: size)
        }
    }

    private func sportIcon(_ game: Game) -> some View {
        let sport = game.sportType ?? .soccer
        return Image(systemName: sport.widgetSystemImage)
            .font(.caption)
            .foregroundStyle(WidgetTokens.sport(sport))
    }

    private func opponentID(_ name: String?) -> String? {
        name.flatMap { TeamsManager.shared.team(byNameOrAlias: $0)?.idTeam }
    }

    private func leagueName(_ game: Game) -> String? {
        game.idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:))?.leagueName
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
        .description("One team's next game and upcoming fixtures.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

#Preview(as: .systemSmall) {
    TeamFixtureWidget()
} timeline: {
    TeamFixtureProvider.sampleEntry
    TeamFixtureProvider.sampleLiveEntry
}

#Preview(as: .systemMedium) {
    TeamFixtureWidget()
} timeline: {
    TeamFixtureProvider.sampleEntry
    TeamFixtureProvider.sampleLiveEntry
}

#Preview(as: .systemLarge) {
    TeamFixtureWidget()
} timeline: {
    TeamFixtureProvider.sampleEntry
    TeamFixtureProvider.sampleLiveEntry
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
