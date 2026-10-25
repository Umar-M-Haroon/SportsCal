//
//  PollRankingsService.swift
//
//  College polls (AP, Coaches, CFP, lower divisions) for `/rankings/:leagueID`.
//
//  - The latest week comes from the site API, which ignores `week`/`season` query
//    parameters, so it can only ever answer "now". Teams arrive inline.
//  - Earlier weeks come from the core API, one request per poll, with each team as a
//    `$ref`. Rather than follow ~40 refs, teams are looked up in the league's team
//    directory (one cached request) and in the latest week's inline teams.
//
//  Everything is cached in Redis, so app traffic never reaches ESPN directly.
//

import Foundation
import Vapor
import SportsCalModel

// MARK: - ESPN shapes

/// `site.api.espn.com/apis/site/v2/sports/{sport}/{league}/rankings`
struct ESPNRankingsResponse: Decodable {
    let requestedSeason: Season?
    let latestSeason: Season?
    let weeks: [WeekOption]?
    let rankings: [ESPNPoll]?

    struct Season: Decodable {
        let year: Int?
        let type: SeasonType?
        let week: ESPNPoll.Occurrence?
    }

    struct SeasonType: Decodable {
        let type: Int?
    }

    struct WeekOption: Decodable {
        let display: String?
        let week: String?
        let type: String?
    }
}

/// One poll for one week. The site API embeds teams; the core API sends `$ref`s.
struct ESPNPoll: Decodable {
    let id: String?
    let name: String?
    let shortName: String?
    let date: String?
    let occurrence: Occurrence?
    let ranks: [Rank]?
    let others: [Rank]?
    let droppedOut: [Rank]?

    struct Occurrence: Decodable {
        let number: Int?
        let displayValue: String?
    }

    struct Rank: Decodable {
        let current: Int?
        let previous: Int?
        let points: Double?
        let firstPlaceVotes: Int?
        /// Site API.
        let recordSummary: String?
        /// Core API.
        let record: Record?
        let team: Team?

        struct Record: Decodable {
            let summary: String?
        }
    }

    struct Team: Decodable {
        let id: String?
        let location: String?
        let name: String?
        let abbreviation: String?
        let color: String?
        let logos: [ESPNLogo]?
        let groups: Group?
        let ref: String?

        enum CodingKeys: String, CodingKey {
            case id, location, name, abbreviation, color, logos, groups
            case ref = "$ref"
        }

        struct Group: Decodable {
            let shortName: String?
            let isConference: Bool?
        }

        /// The ID from the inline team, or the last path component of a core `$ref`
        /// (".../seasons/2026/teams/251?lang=en").
        var resolvedID: String? {
            if let id, !id.isEmpty { return id }
            guard let ref, let url = URL(string: ref) else { return nil }
            let last = url.lastPathComponent
            return last.isEmpty || !last.allSatisfy(\.isNumber) ? nil : last
        }
    }
}

struct ESPNLogo: Decodable {
    let href: String?
    let rel: [String]?
}

/// `site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams?limit=1000`
struct ESPNTeamDirectoryResponse: Decodable {
    let sports: [Sport]?

    struct Sport: Decodable { let leagues: [League]? }
    struct League: Decodable { let teams: [Wrapper]? }
    struct Wrapper: Decodable { let team: ESPNPoll.Team? }

    var teams: [ESPNPoll.Team] {
        (sports ?? []).flatMap { $0.leagues ?? [] }.flatMap { $0.teams ?? [] }.compactMap(\.team)
    }
}

// MARK: - Builder

enum PollRankingsBuilder {
    /// Team details by ESPN ID, for polls whose teams are only refs.
    typealias TeamDirectory = [String: PollRankings.Team]

    /// The latest week, from the site API.
    static func latest(league: Leagues, response: ESPNRankingsResponse) -> PollRankings? {
        let season = response.requestedSeason ?? response.latestSeason
        guard let year = season?.year else { return nil }
        let weeks = weekOptions(response.weeks)
        let polls = (response.rankings ?? []).compactMap { poll($0, directory: [:]) }
        // The requested week is the newest one the site API knows about; fall back to its
        // own occurrence when the week list is missing.
        let current = weeks.last ?? PollRankings.Week(
            seasonType: season?.type?.type ?? 2,
            number: season?.week?.number ?? 1,
            label: season?.week?.displayValue ?? "Latest"
        )
        return PollRankings(league: league.rawValue, season: year, week: current,
                            weeks: weeks.isEmpty ? [current] : weeks, polls: polls)
    }

    /// An earlier week: core API polls, labelled and ordered like the latest week's.
    static func week(_ week: PollRankings.Week, latest: PollRankings, polls: [ESPNPoll],
                     directory: TeamDirectory) -> PollRankings {
        let order = latest.polls.map(\.id)
        let built = polls.compactMap { poll($0, directory: directory) }
            .sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        return PollRankings(league: latest.league, season: latest.season, week: week,
                            weeks: latest.weeks, polls: built)
    }

    /// The latest week's teams — the only source of conferences.
    static func directory(from rankings: PollRankings) -> TeamDirectory {
        var out: TeamDirectory = [:]
        for poll in rankings.polls {
            for entry in poll.ranks + poll.others + poll.droppedOut where out[entry.team.id] == nil {
                out[entry.team.id] = entry.team
            }
        }
        return out
    }

    static func directory(from response: ESPNTeamDirectoryResponse) -> TeamDirectory {
        var out: TeamDirectory = [:]
        for raw in response.teams {
            if let team = team(raw) { out[team.id] = team }
        }
        return out
    }

    /// "Preseason", "Week 1"… in ESPN's order (already chronological).
    static func weekOptions(_ options: [ESPNRankingsResponse.WeekOption]?) -> [PollRankings.Week] {
        var seen = Set<String>()
        return (options ?? []).compactMap { option in
            guard let type = option.type.flatMap(Int.init), let number = option.week.flatMap(Int.init) else {
                return nil
            }
            let week = PollRankings.Week(seasonType: type, number: number,
                                         label: option.display ?? "Week \(number)")
            return seen.insert(week.id).inserted ? week : nil
        }
    }

    static func poll(_ raw: ESPNPoll, directory: TeamDirectory) -> PollRankings.Poll? {
        guard let id = raw.id, let name = raw.name else { return nil }
        func entries(_ ranks: [ESPNPoll.Rank]?, ranked: Bool) -> [PollRankings.Entry] {
            (ranks ?? []).compactMap { entry($0, ranked: ranked, directory: directory) }
        }
        let ranks = entries(raw.ranks, ranked: true).sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
        guard !ranks.isEmpty else { return nil }
        let byPoints: (PollRankings.Entry, PollRankings.Entry) -> Bool = { ($0.points ?? 0) > ($1.points ?? 0) }
        return PollRankings.Poll(
            id: id,
            name: name,
            shortName: raw.shortName ?? name,
            date: raw.date,
            ranks: ranks,
            others: entries(raw.others, ranked: false).sorted(by: byPoints),
            droppedOut: entries(raw.droppedOut, ranked: false).sorted {
                ($0.previous ?? .max) < ($1.previous ?? .max)
            }
        )
    }

    static func entry(_ raw: ESPNPoll.Rank, ranked: Bool, directory: TeamDirectory) -> PollRankings.Entry? {
        guard let rawTeam = raw.team, let id = rawTeam.resolvedID else { return nil }
        // Prefer the inline team; fill a ref-only one from the directory.
        guard let team = team(rawTeam) ?? directory[id] else { return nil }
        // ESPN marks "unranked" with 0 for both weeks.
        let rank = raw.current.flatMap { $0 > 0 ? $0 : nil }
        if ranked && rank == nil { return nil }
        let points = raw.points.flatMap { $0 > 0 ? $0 : nil }
        return PollRankings.Entry(
            rank: ranked ? rank : nil,
            previous: raw.previous.flatMap { $0 > 0 ? $0 : nil },
            points: points,
            firstPlaceVotes: raw.firstPlaceVotes.flatMap { $0 > 0 ? $0 : nil },
            record: ranked ? (raw.recordSummary ?? raw.record?.summary) : nil,
            team: team
        )
    }

    static func team(_ raw: ESPNPoll.Team) -> PollRankings.Team? {
        guard let id = raw.resolvedID, let location = raw.location, !location.isEmpty else { return nil }
        func logo(_ rel: String) -> String? {
            raw.logos?.first { $0.rel?.contains(rel) == true }?.href
        }
        return PollRankings.Team(
            id: id,
            location: location,
            name: raw.name ?? "",
            abbreviation: raw.abbreviation,
            color: raw.color,
            logo: logo("default") ?? raw.logos?.first?.href,
            darkLogo: logo("dark"),
            conference: raw.groups?.isConference == true ? raw.groups?.shortName : nil
        )
    }
}

// MARK: - Service

enum PollRankingsService {
    private static let site = "https://site.api.espn.com/apis/site/v2/sports"
    private static let core = "https://sports.core.api.espn.com/v2/sports"

    private static func key(_ name: String, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + name
    }

    /// The latest polls. Polls come out once a week, but the CFP and preseason ones
    /// land on their own schedule, so the cache stays short.
    static func latest(league: Leagues, app: Application, isDebug: Bool) async throws -> String {
        try await UpstreamCache.value(
            kv: app.kv,
            key: key("Rankings-\(league.rawValue)", isDebug: isDebug),
            freshFor: 30 * 60,
            keepFor: 14 * 24 * 3600,
            logger: app.logger
        ) {
            let response = try await fetchLatest(league: league, client: app.client)
            guard let rankings = PollRankingsBuilder.latest(league: league, response: response) else {
                throw Abort(.badGateway, reason: "ESPN rankings had no season")
            }
            return encodeResult(res: rankings)
        }
    }

    /// One earlier week of the current season. A released poll never changes, so it's
    /// cached for days; only the week list it carries goes stale, and the app reads
    /// that from the latest week.
    static func week(league: Leagues, seasonType: Int, week: Int, app: Application, isDebug: Bool) async throws -> String {
        let latestBody = try await latest(league: league, app: app, isDebug: isDebug)
        let latest = try JSONDecoder().decode(PollRankings.self, from: Data(latestBody.utf8))
        guard let target = latest.weeks.first(where: { $0.seasonType == seasonType && $0.number == week }) else {
            throw Abort(.notFound)
        }
        if target == latest.week { return latestBody }

        return try await UpstreamCache.value(
            kv: app.kv,
            key: key("Rankings-\(league.rawValue)-\(latest.season)-\(target.id)", isDebug: isDebug),
            freshFor: 3 * 24 * 3600,
            keepFor: 30 * 24 * 3600,
            logger: app.logger
        ) {
            guard let slug = league.espnSlug else { throw Abort(.notFound) }
            let base = "\(core)/\(league.sport)/leagues/\(slug)/seasons/\(latest.season)/types/\(seasonType)/weeks/\(week)/rankings"
            let client = app.client
            // Only the polls the latest week has: the core list also carries polls ESPN
            // has stopped showing.
            let polls = await withTaskGroup(of: ESPNPoll?.self) { group in
                for poll in latest.polls {
                    group.addTask {
                        try? await ESPNNetworking.performGet(client, URI(string: "\(base)/\(poll.id)"))
                            .content.decode(ESPNPoll.self)
                    }
                }
                var out: [ESPNPoll] = []
                for await poll in group { if let poll { out.append(poll) } }
                return out
            }
            guard !polls.isEmpty else { throw Abort(.badGateway, reason: "ESPN had no polls for \(target.label)") }

            // The latest week's teams carry conferences; the directory covers every team
            // that has since dropped out of the polls.
            var directory = (try? await teamDirectory(league: league, app: app, isDebug: isDebug)) ?? [:]
            directory.merge(PollRankingsBuilder.directory(from: latest)) { _, latestTeam in latestTeam }
            return encodeResult(res: PollRankingsBuilder.week(target, latest: latest, polls: polls, directory: directory))
        }
    }

    private static func fetchLatest(league: Leagues, client: some Client) async throws -> ESPNRankingsResponse {
        guard let slug = league.espnSlug else { throw Abort(.notFound) }
        let uri = URI(string: "\(site)/\(league.sport)/\(slug)/rankings")
        return try await ESPNNetworking.performGet(client, uri).content.decode(ESPNRankingsResponse.self)
    }

    /// Every team in the league, slimmed to what a poll row shows. The raw directory is
    /// ~1.8MB for college football; the slim copy is a few dozen KB.
    private static func teamDirectory(league: Leagues, app: Application, isDebug: Bool) async throws -> PollRankingsBuilder.TeamDirectory {
        let body = try await UpstreamCache.value(
            kv: app.kv,
            key: key("Rankings Teams-\(league.rawValue)", isDebug: isDebug),
            freshFor: 7 * 24 * 3600,
            keepFor: 30 * 24 * 3600,
            logger: app.logger
        ) {
            guard let slug = league.espnSlug else { throw Abort(.notFound) }
            let uri = URI(string: "\(site)/\(league.sport)/\(slug)/teams?limit=1000")
            let response = try await ESPNNetworking.performGet(app.client, uri).content.decode(ESPNTeamDirectoryResponse.self)
            return encodeResult(res: PollRankingsBuilder.directory(from: response))
        }
        return try JSONDecoder().decode(PollRankingsBuilder.TeamDirectory.self, from: Data(body.utf8))
    }
}
