//
//  WorldCupEnrichmentJob.swift
//  SportsCalServer
//
//  Builds FIFA World Cup enrichment (knockout bracket + Golden Boot top scorers)
//  from ESPN and ships it inside the main schedule (`LiveScore.worldCup`) so the
//  client gets it with zero extra fetches. Modeled on F1EnrichmentJob.
//
//  Squads are NOT built here (they're large and fetched lazily per-team by the
//  `/worldcup/squad/:teamID` route). This job stays cheap: two ESPN calls per run,
//  gated to roughly twice an hour.
//

import Foundation
import Queues
import SportsCalModel
import Logging

struct WorldCupEnrichmentJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.worldcup-enrichment")

    /// Refetch interval. Bracket and scorers move fast during the tournament; off-season
    /// this still runs but finds nothing to persist (write-guards skip empty data).
    private static let stalenessInterval: TimeInterval = 30 * 60

    // Write-guards: an empty result means a degraded/absent source — never clobber
    // last-known-good Redis data with emptiness.
    static func shouldPersistBracket(_ bracket: WorldCupBracket) -> Bool { !bracket.isEmpty }
    static func shouldPersistScorers(_ scorers: [WorldCupScorer]) -> Bool { !scorers.isEmpty }

    func run(context: QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let client = context.application.client
        let redis = context.application.redis
        let seasonYear = Calendar.current.component(.year, from: Date())

        let lastUpdateKey = RedisEndpoint.ESPN.worldCupEnrichmentLastUpdate.getValue(isDebug: isDebug)
        if let lastUpdate = try? await redis.get(lastUpdateKey, asJSON: Date.self) {
            let secondsSince = Date().timeIntervalSince(lastUpdate)
            if secondsSince < Self.stalenessInterval {
                Self.logger.info("World Cup enrichment still fresh, skipping", metadata: [
                    "minutesSinceUpdate": "\(String(format: "%.1f", secondsSince / 60))"
                ])
                return
            }
        }

        Self.logger.info("Fetching World Cup enrichment", metadata: ["season": "\(seasonYear)"])

        // Pull the full-tournament scoreboard (dates = year) so we see every knockout
        // fixture, not just the current matchday. Leaders gives the Golden Boot race.
        async let scoreboardTask: Scoreboard? = try? await ESPNNetworking.getScoreboard(
            req: client, DecodeType: Scoreboard.self, league: .FIFA_World_Cup, dates: seasonYear
        )
        // Golden Boot: the /statistics endpoint is the live source (goalsLeaders +
        // assistsLeaders); the old /leaders route 404s for fifa.world but stays as a
        // fallback in case ESPN flips back.
        async let statisticsTask: LeagueStatisticsResponse? = try? await ESPNNetworking.getLeagueStatistics(
            req: client, league: .FIFA_World_Cup
        )
        async let leadersTask: LeadersResponse? = try? await ESPNNetworking.getLeaders(
            req: client, DecodeType: LeadersResponse.self, league: .FIFA_World_Cup
        )

        let scoreboard = await scoreboardTask
        let statistics = await statisticsTask
        let leaders = await leadersTask

        let bracket = scoreboard.map { Self.buildBracket(from: $0) } ?? WorldCupBracket()
        var scorers = statistics.map { Self.buildScorers(fromStatistics: $0) } ?? []
        if scorers.isEmpty {
            scorers = leaders.map { Self.buildScorers(from: $0) } ?? []
        }

        let enrichment = WorldCupEnrichment(
            bracket: bracket.isEmpty ? nil : bracket,
            topScorers: scorers
        )

        // Persist individual caches (for routes/admin) and the combined ridealong payload.
        let bracketKey = RedisEndpoint.ESPN.worldCupBracket.getValue(isDebug: isDebug)
        let scorersKey = RedisEndpoint.ESPN.worldCupScorers.getValue(isDebug: isDebug)
        let enrichmentKey = RedisEndpoint.ESPN.worldCupEnrichment.getValue(isDebug: isDebug)

        var wrotePrimary = false
        if Self.shouldPersistBracket(bracket) {
            try await redis.set(bracketKey, toJSON: bracket)
            wrotePrimary = true
        }
        if Self.shouldPersistScorers(scorers) {
            try await redis.set(scorersKey, toJSON: scorers)
            wrotePrimary = true
        }
        if !enrichment.isEmpty {
            try await redis.set(enrichmentKey, toJSON: enrichment)
        }
        // Only stamp lastUpdate when something real was written, so a degraded run retries
        // next tick instead of being silenced for the staleness window.
        if wrotePrimary {
            try await redis.set(lastUpdateKey, toJSON: Date())
        }

        // Attach to the main schedule so the client picks it up via LiveScore.worldCup.
        if !enrichment.isEmpty {
            let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
            if var schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self) {
                schedule.worldCup = enrichment
                try await redis.set(scheduleKey, toJSON: schedule)
                Self.logger.info("World Cup enrichment applied to schedule")
            }
        }

        Self.logger.info("World Cup enrichment complete", metadata: [
            "rounds": "\(bracket.rounds.count)",
            "knockoutMatches": "\(bracket.rounds.reduce(0) { $0 + $1.matches.count })",
            "thirdPlace": "\(bracket.thirdPlacePlayoff != nil)",
            "scorers": "\(scorers.count)"
        ])
    }

    // MARK: - Bracket building

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Builds the knockout bracket from a full-tournament scoreboard. Group-stage games
    /// are ignored; only knockout fixtures (round label or season.type == 3) are included.
    static func buildBracket(from scoreboard: Scoreboard) -> WorldCupBracket {
        var byRound: [String: [WorldCupBracketMatch]] = [:]
        var roundOrder: [String: Int] = [:]
        var thirdPlace: WorldCupBracketMatch?

        for event in scoreboard.events {
            guard let competition = event.competitions?.first else { continue }
            let roundLabel = roundLabel(for: event, competition: competition)
            // Knockout only: needs either a recognized knockout label or the postseason flag.
            let isKnockout = roundSortIndex(roundLabel) != nil || event.season?.type == 3
            guard isKnockout, let label = roundLabel else { continue }

            let match = buildMatch(event: event, competition: competition)

            if isThirdPlace(label) {
                // Keep the most-decided third-place match if several appear.
                if thirdPlace == nil || (match.winner != nil) { thirdPlace = match }
                continue
            }

            byRound[label, default: []].append(match)
            roundOrder[label] = roundSortIndex(label) ?? 98
        }

        let rounds: [WorldCupBracketRound] = byRound
            .map { (label, matches) in
                WorldCupBracketRound(
                    roundName: label,
                    slug: label.lowercased().replacingOccurrences(of: " ", with: "-"),
                    matches: matches.sorted {
                        ($0.date ?? .distantFuture, $0.eventID ?? "") < ($1.date ?? .distantFuture, $1.eventID ?? "")
                    }
                )
            }
            .sorted { (roundOrder[$0.roundName] ?? 98) < (roundOrder[$1.roundName] ?? 98) }
            // assign stable bracketPosition within each round
            .map { round in
                var r = round
                r.matches = r.matches.enumerated().map { idx, m in
                    var mm = m; mm.bracketPosition = idx; return mm
                }
                return r
            }

        return WorldCupBracket(rounds: rounds, thirdPlacePlayoff: thirdPlace)
    }

    private static func buildMatch(event: Event, competition: Competition) -> WorldCupBracketMatch {
        let competitors = competition.competitors ?? []
        let home = competitors.first(where: { $0.homeAway == "home" }) ?? competitors.first
        let away = competitors.first(where: { $0.homeAway == "away" }) ?? competitors.dropFirst().first

        let completed = competition.status?.type.completed ?? event.status?.type.completed ?? false
        let homeScore = home?.score
        let awayScore = away?.score

        var winner: BracketSide?
        if completed, let h = homeScore.flatMap({ Int($0) }), let a = awayScore.flatMap({ Int($0) }) {
            if h > a { winner = .home } else if a > h { winner = .away }
            // equal regulation score → likely decided on penalties; leave nil unless aggregate decides
        }

        // Aggregate goals for two-leg ties (rare at WC, but ESPN exposes the field).
        var aggregate: String?
        if let series = competition.series?.competitors, series.count == 2,
           let h = series.first(where: { $0.id == home?.id })?.aggregateScore,
           let a = series.first(where: { $0.id == away?.id })?.aggregateScore {
            aggregate = "Agg: \(Int(h))-\(Int(a))"
            if winner == nil { if h > a { winner = .home } else if a > h { winner = .away } }
        }

        return WorldCupBracketMatch(
            eventID: event.id,
            homeTeamName: home?.team?.displayName,
            awayTeamName: away?.team?.displayName,
            homeTeamBadge: home?.team?.logo,
            awayTeamBadge: away?.team?.logo,
            homeScore: completed ? homeScore : nil,
            awayScore: completed ? awayScore : nil,
            aggregateScore: aggregate,
            winner: winner,
            date: isoFormatter.date(from: event.date),
            bracketPosition: 0
        )
    }

    /// Best round label from ESPN. The 2026 World Cup tags the knockout round on the
    /// `season.slug` ("round-of-32", "round-of-16", "quarterfinals", "semifinals",
    /// "final") and leaves `notes` empty, so the slug is the authoritative signal; we
    /// fall back to the notes headline/text and the event name for older formats.
    private static func roundLabel(for event: Event, competition: Competition) -> String? {
        if let slug = event.season?.slug, let label = roundLabel(fromSlug: slug) {
            return label
        }
        if let headline = competition.notes?.first(where: { ($0.headline?.isEmpty == false) })?.headline {
            return headline.trimmingCharacters(in: .whitespaces)
        }
        if let text = competition.notes?.first(where: { ($0.text?.isEmpty == false) })?.text {
            return text.trimmingCharacters(in: .whitespaces)
        }
        // Fall back to a name only if it looks like a knockout label (avoids group games).
        let candidate = (event.shortName ?? event.name)
        return roundSortIndex(candidate) != nil ? candidate : nil
    }

    /// Maps an ESPN `season.slug` to a canonical knockout-round label, or nil for the
    /// group stage ("group-stage" / unknown). The returned label feeds `roundSortIndex`.
    private static func roundLabel(fromSlug slug: String) -> String? {
        switch slug.lowercased() {
        case "round-of-32": return "Round of 32"
        case "round-of-16": return "Round of 16"
        case "quarterfinals", "quarter-finals": return "Quarterfinals"
        case "semifinals", "semi-finals": return "Semifinals"
        case "third-place", "third-place-final", "3rd-place": return "Third Place"
        case "final": return "Final"
        default: return nil
        }
    }

    private static func isThirdPlace(_ label: String) -> Bool {
        let l = label.lowercased()
        return l.contains("third place") || l.contains("3rd place") || l.contains("third-place")
    }

    /// Canonical ordering for known knockout rounds. Returns nil for non-knockout labels
    /// (e.g. "Group A"), which the caller treats as "not a bracket round".
    static func roundSortIndex(_ label: String?) -> Int? {
        guard let label = label?.lowercased() else { return nil }
        if label.contains("round of 32") { return 0 }
        if label.contains("round of 16") { return 1 }
        if label.contains("quarter") { return 2 }
        if label.contains("semi") { return 3 }
        if isThirdPlace(label) { return 4 }
        if label.contains("final") { return 5 } // after semis/third-place so "Final" sorts last
        return nil
    }

    // MARK: - Scorers building

    /// Extracts the Golden Boot race from the ESPN league statistics response —
    /// `goalsLeaders` ranked by goals, with assists joined in from `assistsLeaders`
    /// by athlete id. Entries with zero goals are dropped so the race never pads
    /// itself with the whole player pool.
    static func buildScorers(fromStatistics statistics: LeagueStatisticsResponse) -> [WorldCupScorer] {
        let categories = statistics.stats ?? []
        func leaders(matching key: String) -> [LeagueStatisticsResponse.StatLeader] {
            categories.first { category in
                ((category.name ?? "") + (category.displayName ?? "")).lowercased().contains(key)
            }?.leaders ?? []
        }

        var assistsByAthlete: [String: Int] = [:]
        for entry in leaders(matching: "assist") {
            if let id = entry.athlete?.id, let value = entry.value {
                assistsByAthlete[id] = Int(value)
            }
        }

        return leaders(matching: "goal").prefix(30).enumerated().compactMap { idx, entry in
            guard let athlete = entry.athlete,
                  let name = athlete.displayName ?? athlete.shortName,
                  let goals = entry.value.map({ Int($0) }), goals > 0 else { return nil }
            return WorldCupScorer(
                rank: idx + 1,
                playerName: name,
                teamName: athlete.team?.displayName ?? "",
                teamBadge: athlete.team?.logos?.first?.href,
                headshotURL: nil,
                goals: goals,
                assists: athlete.id.flatMap { assistsByAthlete[$0] }
            )
        }
    }

    /// Extracts the Golden Boot race from the ESPN leaders response (goals category).
    /// Legacy: the route 404s for fifa.world as of mid-2026; kept as a fallback.
    static func buildScorers(from leaders: LeadersResponse) -> [WorldCupScorer] {
        // Prefer an explicit goals category; fall back to the first category.
        let goalCategory = leaders.leaders?.first(where: { cat in
            let key = ((cat.name ?? "") + " " + (cat.displayName ?? "") + " " + (cat.abbreviation ?? "")).lowercased()
            return key.contains("goal") || key.contains("scor")
        }) ?? leaders.leaders?.first

        guard let entries = goalCategory?.leaders else { return [] }

        return entries.enumerated().compactMap { (idx, entry) in
            guard let name = entry.athlete?.displayName ?? entry.athlete?.shortName else { return nil }
            let goals = Int(entry.displayValue?.components(separatedBy: CharacterSet.decimalDigits.inverted).first(where: { !$0.isEmpty }) ?? "") ?? 0
            return WorldCupScorer(
                rank: idx + 1,
                playerName: name,
                teamName: entry.team?.displayName ?? "",
                teamBadge: entry.team?.logos?.first?.href,
                headshotURL: entry.athlete?.headshot?.href,
                goals: goals,
                assists: nil
            )
        }
    }
}
