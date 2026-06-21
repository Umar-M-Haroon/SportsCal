//
//  LiveBasketball.swift
//
//
//  Created by Umar Haroon on 10/21/22.
//

import Foundation
// MARK: - LiveEvent
public struct LiveEvent: Codable, Equatable, Hashable {
    public init(events: [Game]) {
        self.events = events
    }

    /// Combines two optional LiveEvents, concatenating their events arrays
    public static func merging(_ lhs: LiveEvent?, _ rhs: LiveEvent?) -> LiveEvent? {
        switch (lhs, rhs) {
        case (.some(let l), .some(let r)):
            return LiveEvent(events: l.events + r.events)
        case (.some(let l), .none):
            return l
        case (.none, .some(let r)):
            return r
        case (.none, .none):
            return nil
        }
    }

    public init?(events: Scoreboard, league: Leagues, constructorMap: [String: String] = [:], timingMap: [String: [String: String]] = [:]) {
        guard let slug = events.leagues.first?.slug,
              let league = Leagues(slug: slug) else { return nil }
        let sportType = SportType(league: league)
        let leagueID = "\(league.rawValue)"

        self.events = events.events.flatMap({ event -> [Game] in
            // 1) Team sports: competitions → competitors with homeAway + team
            if let competition = event.competitions?.first,
               let home = competition.competitors?.first(where: { $0.homeAway == "home" }),
               let away = competition.competitors?.first(where: { $0.homeAway == "away" }),
               let homeTeam = home.team,
               let awayTeam = away.team {
                let hLinescores = home.linescores?.compactMap { $0.value }
                let aLinescores = away.linescores?.compactMap { $0.value }

                let hLeaders = home.leaders?.compactMap { leader -> GameLeader? in
                    guard let top = leader.leaders.first,
                          let name = top.athlete?.displayName ?? top.athlete?.shortName else { return nil }
                    return GameLeader(category: leader.name, categoryDisplay: leader.displayName,
                                      playerName: name, displayValue: top.displayValue, headshot: top.athlete?.headshot)
                }
                let aLeaders = away.leaders?.compactMap { leader -> GameLeader? in
                    guard let top = leader.leaders.first,
                          let name = top.athlete?.displayName ?? top.athlete?.shortName else { return nil }
                    return GameLeader(category: leader.name, categoryDisplay: leader.displayName,
                                      playerName: name, displayValue: top.displayValue, headshot: top.athlete?.headshot)
                }

                // Playoff detection: season.type == 3 is ESPN's authoritative postseason flag.
                // Fall back to series presence, and to event/notes text matching, so playoff
                // context still populates when any one signal is missing.
                let playoffEligibleTeamLeagues: Set<Leagues> = [.nba, .nhl, .mlb, .nfl, .ncaaMBBTournament]
                let namedAsPostseason: Bool = {
                    let short = event.shortName ?? ""
                    let nameHaystack = (event.name + " " + short).lowercased()
                    let noteHaystack = (competition.notes ?? [])
                        .compactMap { ($0.headline ?? "") + " " + ($0.text ?? "") }
                        .joined(separator: " ")
                        .lowercased()
                    let haystack = nameHaystack + " " + noteHaystack
                    let markers = [
                        "playoff", "postseason", "wild card", "wild-card", "divisional",
                        "conference final", "conference semifinal", "conference quarterfinal",
                        "nba finals", "stanley cup", "world series", "alcs", "nlcs",
                        "division series", "championship series", "super bowl"
                    ]
                    return markers.contains(where: { haystack.contains($0) })
                }()
                let isPlayoff = (event.season?.type == 3)
                    || (competition.series != nil && playoffEligibleTeamLeagues.contains(league))
                    || (namedAsPostseason && playoffEligibleTeamLeagues.contains(league))

                // `curatedRank.current` is a real bracket seed (1–16) only for NCAA tournament
                // competitors. For pro-league games ESPN returns 99 as an "unranked" sentinel,
                // which would surface as "(99)". Pro-league playoff seeds live on the standings
                // endpoint and need separate wiring — leave seeds nil here for now.
                let homeSeed = (league == .ncaaMBBTournament) ? home.curatedRank?.current : nil
                let awaySeed = (league == .ncaaMBBTournament) ? away.curatedRank?.current : nil
                let homeColor = homeTeam.color
                let awayColor = awayTeam.color
                let homeRec = home.records?.first(where: { $0.type == "total" })?.summary
                let awayRec = away.records?.first(where: { $0.type == "total" })?.summary

                // ESPN overloads SeriesCompetitor.aggregateScore: series wins for NBA/NHL/MLB
                // versus aggregate goals for soccer knockout rounds. Keep the soccer string rendering,
                // use the integer wins rendering for the playoff context.
                let winsFormatLeagues: Set<Leagues> = [.nba, .nhl, .mlb]

                // Soccer aggregate rendering (unchanged behaviour for UCL etc.)
                var aggregateScore: String?
                if !winsFormatLeagues.contains(league),
                   let seriesCompetitors = competition.series?.competitors,
                   seriesCompetitors.count == 2 {
                    let homeAgg = seriesCompetitors.first(where: { $0.id == homeTeam.id })?.aggregateScore
                    let awayAgg = seriesCompetitors.first(where: { $0.id == awayTeam.id })?.aggregateScore
                    if let h = homeAgg, let a = awayAgg {
                        aggregateScore = "Agg: \(Int(a))-\(Int(h))"
                    }
                }

                var playoff: PlayoffContext? = nil
                if isPlayoff {
                    // ESPN populates `competitors[].wins` for NBA/NHL/MLB playoff series.
                    // `aggregateScore` is a different field used by soccer knockouts.
                    var homeWins: Int? = nil
                    var awayWins: Int? = nil
                    if winsFormatLeagues.contains(league),
                       let sc = competition.series?.competitors, sc.count == 2 {
                        homeWins = sc.first(where: { $0.id == homeTeam.id })?.wins
                        awayWins = sc.first(where: { $0.id == awayTeam.id })?.wins
                    }
                    // Prefer ESPN's own "Game N" labeling (notes headline, status detail).
                    // Avoid wins-sum inference — it lags the scoreboard by a cycle.
                    let gameNumberTextSources: [String?] = (competition.notes ?? [])
                        .flatMap { [$0.headline, $0.text] }
                        + [
                            event.shortName, event.name,
                            event.status?.type.detail, event.status?.type.shortDetail,
                            competition.status?.type.detail, competition.status?.type.shortDetail
                        ]
                    let gameNumber: Int? = winsFormatLeagues.contains(league)
                        ? gameNumberTextSources.lazy.compactMap { Self.parseGameNumber(from: $0) }.first
                        : nil

                    // Round label preference: notes headline (e.g. "East 1st Round - Game 2")
                    // beats series.title which is usually just "Playoff Series". Strip any
                    // trailing "- Game N" so it doesn't duplicate the game number display.
                    let rawSeriesTitle = competition.notes?.first(where: { $0.headline?.isEmpty == false })?.headline
                        ?? competition.series?.title
                        ?? competition.notes?.first(where: { $0.text?.isEmpty == false })?.text
                        ?? event.shortName
                        ?? event.name
                    let seriesTitle = Self.stripGameSuffix(from: rawSeriesTitle)

                    playoff = PlayoffContext(
                        seriesTitle: seriesTitle,
                        gameNumber: gameNumber,
                        bestOf: competition.series?.totalCompetitions,
                        homeWins: homeWins,
                        awayWins: awayWins,
                        seriesCompleted: competition.series?.completed,
                        isNeutralSite: competition.neutralSite
                    )
                }

                // ESPN's shortDetail for pre-game is a hardcoded "M/d - h:mm a TZ" in
                // Eastern Time — useless on-device since we format standardDate locally.
                let eventState = event.status?.type.state
                let progressDetail = eventState == "pre" ? nil : event.status?.type.shortDetail
                return [Game(
                    idLiveScore: event.id, idEvent: event.id, strSport: sportType.rawValue,
                    idLeague: leagueID, idHomeTeam: homeTeam.id, idAwayTeam: awayTeam.id,
                    strHomeTeam: homeTeam.displayName, strAwayTeam: awayTeam.displayName,
                    strHomeTeamBadge: homeTeam.logo, strAwayTeamBadge: awayTeam.logo,
                    intHomeScore: home.score, intAwayScore: away.score,
                    strStatus: eventState, strProgress: progressDetail,
                    strTimestamp: event.date,
                    lastPlay: competition.situation?.lastPlay?.text,
                    homeLinescores: hLinescores?.isEmpty == true ? nil : hLinescores,
                    awayLinescores: aLinescores?.isEmpty == true ? nil : aLinescores,
                    homeLeaders: hLeaders?.isEmpty == true ? nil : hLeaders,
                    awayLeaders: aLeaders?.isEmpty == true ? nil : aLeaders,
                    isCompleted: event.status?.type.completed, isoDate: nil,
                    homeTeamColor: homeColor, awayTeamColor: awayColor,
                    homeRecord: homeRec, awayRecord: awayRec,
                    legDisplay: competition.leg?.displayValue,
                    aggregateScore: aggregateScore,
                    homeSeed: homeSeed,
                    awaySeed: awaySeed,
                    // Safety net: tennis matches normally arrive via the groupings path (#2)
                    // which sets the tournament from `event.name`. If a tennis match ever comes
                    // through this standard path (flat `event.competitions`), keep it tagged so
                    // it doesn't collapse into the `strLeague` ("ATP Tour"/"WTA Tour") bucket.
                    tournamentName: league.isTennis ? event.name : nil,
                    playoff: playoff,
                    lastPlayScoreboardID: competition.situation?.lastPlay?.id
                )]
            }

            // 2) Tennis: matches nested under groupings → competitions → competitors with athlete
            if let groupings = event.groupings {
                return groupings.flatMap { grouping -> [Game] in
                    (grouping.competitions ?? []).compactMap { competition -> Game? in
                        guard let home = competition.competitors?.first(where: { $0.homeAway == "home" }),
                              let away = competition.competitors?.first(where: { $0.homeAway == "away" })
                        else { return nil }
                        let homeName = home.athlete?.displayName ?? home.team?.displayName ?? "TBD"
                        let awayName = away.athlete?.displayName ?? away.team?.displayName ?? "TBD"
                        let hLinescores = home.linescores?.compactMap { $0.value }
                        let aLinescores = away.linescores?.compactMap { $0.value }
                        let tennisState = competition.status?.type.state ?? event.status?.type.state
                        let tennisProgress = tennisState == "pre"
                            ? nil
                            : (competition.status?.type.shortDetail ?? event.status?.type.shortDetail)
                        return Game(
                            idLiveScore: competition.id, idEvent: competition.id, strSport: sportType.rawValue,
                            idLeague: leagueID, idHomeTeam: home.id, idAwayTeam: away.id,
                            strHomeTeam: homeName, strAwayTeam: awayName,
                            strHomeTeamBadge: home.athlete?.headshot, strAwayTeamBadge: away.athlete?.headshot,
                            intHomeScore: home.score, intAwayScore: away.score,
                            strStatus: tennisState,
                            strProgress: tennisProgress,
                            strTimestamp: competition.date,
                            homeLinescores: hLinescores?.isEmpty == true ? nil : hLinescores,
                            awayLinescores: aLinescores?.isEmpty == true ? nil : aLinescores,
                            isCompleted: competition.status?.type.completed ?? event.status?.type.completed, isoDate: nil,
                            tournamentName: event.name,
                            round: competition.round?.displayName
                        )
                    }
                }
            }

            // 3) Racing: create ONE game per event (Grand Prix weekend) with all sessions
            if league.isRacing, let competitions = event.competitions, !competitions.isEmpty {
                // Session priority: Race > Sprint > Qual > FP3 > FP2 > FP1
                let sessionPriority = ["Race": 6, "Sprint": 5, "Qual": 4, "FP3": 3, "FP2": 2, "FP1": 1]

                // Build EventSession array from all competitions
                let eventSessions: [EventSession] = competitions.map { competition in
                    let sessionType = competition.type?.abbreviation ?? ""
                    let sessionName: String
                    switch sessionType {
                    case "FP1": sessionName = "Free Practice 1"
                    case "FP2": sessionName = "Free Practice 2"
                    case "FP3": sessionName = "Free Practice 3"
                    case "Qual": sessionName = "Qualifying"
                    case "Sprint": sessionName = "Sprint"
                    case "Race": sessionName = "Race"
                    default: sessionName = sessionType.isEmpty ? "Session" : sessionType
                    }
                    let competitionTiming = timingMap[competition.id]
                    let sessionLeaderboard: [LeaderboardEntry] = (competition.competitors ?? []).map { competitor in
                        let name = competitor.athlete?.displayName ?? "TBD"
                        let score = competitor.score ?? "P\(competitor.order ?? 0)"
                        let constructorName = constructorMap[competitor.id] ?? competitor.team?.displayName ?? ""
                        // Gap priority: timing map (core API) → scoreboard statistics → scoreboard score
                        var gap = competitionTiming?[competitor.id] ?? ""
                        if gap.isEmpty, let stats = competitor.statistics {
                            // ESPN scoreboard includes gap stats on competitors during live/completed races
                            for stat in stats {
                                let name = stat.name.lowercased()
                                if (name.contains("behind") || name.contains("gap") || name == "status" || name == "lapsdown"),
                                   !stat.displayValue.isEmpty, stat.displayValue != "--",
                                   stat.displayValue != "0", stat.displayValue != "Running" {
                                    gap = stat.displayValue
                                    break
                                }
                            }
                        }
                        return LeaderboardEntry(
                            name: name, score: score, position: competitor.order ?? 0,
                            headshot: competitor.athlete?.headshot,
                            constructor: constructorName.isEmpty ? nil : constructorName,
                            gap: gap.isEmpty ? nil : gap
                        )
                    }
                    let sessionState = competition.status?.type.state
                    return EventSession(
                        sessionType: sessionType, sessionName: sessionName,
                        status: sessionState,
                        progress: sessionState == "pre" ? nil : competition.status?.type.shortDetail,
                        date: competition.date,
                        leaderboard: sessionLeaderboard
                    )
                }

                // Pick primary session: latest in-progress, else highest-priority completed, else latest
                let primarySession: EventSession
                if let liveSession = eventSessions.first(where: { $0.status == "in" }) {
                    primarySession = liveSession
                } else {
                    let completedSessions = eventSessions.filter { $0.status == "post" }
                    if !completedSessions.isEmpty {
                        primarySession = completedSessions.max(by: {
                            (sessionPriority[$0.sessionType] ?? 0) < (sessionPriority[$1.sessionType] ?? 0)
                        }) ?? eventSessions.last!
                    } else {
                        primarySession = eventSessions.last!
                    }
                }

                let leader = primarySession.leaderboard.first
                let leaderName = leader?.name ?? "TBD"
                let leaderScore = leader?.score

                // Build backward-compatible lastPlay string
                let lastPlayStr = primarySession.leaderboard.map { entry in
                    let gap = entry.gap ?? ""
                    let constructor = entry.constructor ?? ""
                    return "\(entry.name)|\(entry.score)|\(gap)|\(constructor)"
                }.joined(separator: "\n")

                let venueName = competitions.first?.venue?.fullName

                // For F1, use the primary session status (not event-level) because ESPN
                // marks the entire event as "post"/"completed" after each practice session.
                // A race weekend is only truly "in progress" or "complete" based on sessions.
                let raceSession = eventSessions.first(where: { $0.sessionType == "Race" })
                let raceCompleted = raceSession?.status == "post"
                let anySessionLive = eventSessions.contains(where: { $0.status == "in" })
                let primaryStatus: String?
                if anySessionLive {
                    primaryStatus = "in"
                } else if raceCompleted {
                    primaryStatus = "post"
                } else {
                    // Sessions have happened but race hasn't — show as upcoming
                    primaryStatus = "pre"
                }
                let progress = primaryStatus == "pre"
                    ? nil
                    : (primarySession.progress ?? event.status?.type.shortDetail)

                return [Game(
                    idLiveScore: event.id, idEvent: event.id, strSport: sportType.rawValue,
                    idLeague: leagueID,
                    strHomeTeam: event.name, strAwayTeam: leaderName,
                    intHomeScore: nil, intAwayScore: leaderScore,
                    strStatus: primaryStatus,
                    strProgress: progress,
                    strTimestamp: event.date,
                    lastPlay: lastPlayStr,
                    isCompleted: raceCompleted, isoDate: nil,
                    leaderboardEntries: primarySession.leaderboard,
                    sessions: eventSessions,
                    venueName: venueName
                )]
            }

            // 4) Golf/individual: one game per event (tournament)
            if let competition = event.competitions?.first {
                let leader = competition.competitors?.first
                let leaderName = leader?.athlete?.displayName ?? "TBD"
                let leaderScore = leader?.score
                let golfState = competition.status?.type.state ?? event.status?.type.state
                let progress = golfState == "pre"
                    ? nil
                    : (competition.status?.type.shortDetail ?? event.status?.type.shortDetail)
                let competitors = Array((competition.competitors ?? []).prefix(30))

                // Extract course hole pars from the first competitor's first round hole data
                let holePars: [Int]? = {
                    guard let firstCompetitor = (competition.competitors ?? []).first,
                          let firstRound = firstCompetitor.linescores?.first,
                          let holes = firstRound.linescores, !holes.isEmpty else { return nil }
                    // Derive par from scoreType: if score=4 and scoreType="E", par=4; if score=3 and scoreType="-1", par=4
                    return holes.sorted(by: { ($0.period ?? 0) < ($1.period ?? 0) }).map { hole in
                        let score = Int(hole.value ?? 0)
                        if let st = hole.scoreType?.displayValue {
                            if st == "E" { return score }
                            if let diff = Int(st.replacingOccurrences(of: "+", with: "")) {
                                return score - diff
                            }
                        }
                        return 4 // fallback
                    }
                }()
                let derivedCoursePar = holePars?.reduce(0, +)

                // Build course info if we have hole data
                let courseInfo: GolfCourseInfo? = {
                    guard let par = derivedCoursePar else { return nil }
                    let courseName = competition.venue?.fullName ?? event.name
                    return GolfCourseInfo(courseName: courseName, par: par, holePars: holePars)
                }()

                // Build structured leaderboard entries with headshots, thru-hole, golf stats, and round details
                let entries: [LeaderboardEntry] = competitors.enumerated().map { index, competitor in
                    let name = competitor.athlete?.displayName ?? "TBD"
                    let score = competitor.score ?? "--"
                    let headshot = competitor.athlete?.headshot
                    let thruHole = competitor.statistics?.first(where: { $0.name == "thruHole" })?.displayValue
                    let rounds = (competitor.linescores ?? []).compactMap { ls -> String? in
                        guard let v = ls.value else { return nil }
                        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : "\(v)"
                    }

                    // Movement indicator (position change)
                    let movementStr = competitor.statistics?.first(where: { $0.name == "movement" })?.displayValue
                    let movement = movementStr.flatMap { Int($0) }

                    // Cut status
                    let isCut = score.lowercased() == "cut"

                    // Tee time for upcoming round
                    let teeTime = competitor.statistics?.first(where: { $0.name == "teeTime" })?.displayValue

                    // Country flag
                    let flagURL = competitor.athlete?.flag?.href
                    let flagAlt = competitor.athlete?.flag?.alt

                    // Per-round details with hole-by-hole scores and stats
                    let roundDetails: [GolfRoundDetail]? = {
                        let allLinescores = competitor.linescores ?? []
                        let details = allLinescores.compactMap { roundLS -> GolfRoundDetail? in
                            guard let roundNum = roundLS.period else { return nil }

                            let totalScore = roundLS.value.map { Int($0) }

                            // Hole-by-hole scores
                            let holeScores: [GolfHoleScore]? = roundLS.linescores?.compactMap { holeLS -> GolfHoleScore? in
                                guard let holeNum = holeLS.period, holeNum >= 1, holeNum <= 18 else { return nil }
                                let holeScore = holeLS.value.map { Int($0) }
                                let holePar = holePars != nil && holeNum <= holePars!.count ? holePars![holeNum - 1] : 4
                                return GolfHoleScore(hole: holeNum, par: holePar, score: holeScore)
                            }

                            // Round stats from nested statistics
                            let stats: GolfRoundStats? = {
                                guard let categories = roundLS.statistics?.categories,
                                      let statEntries = categories.first?.stats,
                                      statEntries.count >= 6 else { return nil }
                                // ESPN golf stats order: [birdiesOrBetter, bogeys, ?, ?, ?, pars, teeTime]
                                let birdies = statEntries.count > 0 ? statEntries[0].value.map { Int($0) } : nil
                                let bogeys = statEntries.count > 1 ? statEntries[1].value.map { Int($0) } : nil
                                let parCount = statEntries.count > 5 ? statEntries[5].value.map { Int($0) } : nil

                                // Count eagles from hole scores (birdiesOrBetter includes eagles)
                                var eagles = 0
                                var actualBirdies = birdies ?? 0
                                if let holes = holeScores {
                                    for hole in holes {
                                        if let s = hole.score, s <= hole.par - 2 { eagles += 1 }
                                    }
                                    if eagles > 0 { actualBirdies = max(0, actualBirdies - eagles) }
                                }

                                // Derive putts from total score if not directly available
                                return GolfRoundStats(
                                    birdies: actualBirdies > 0 ? actualBirdies : birdies,
                                    bogeys: bogeys,
                                    eagles: eagles > 0 ? eagles : nil,
                                    pars: parCount
                                )
                            }()

                            return GolfRoundDetail(
                                roundNumber: roundNum,
                                totalScore: totalScore,
                                stats: stats,
                                holeScores: holeScores
                            )
                        }
                        return details.isEmpty ? nil : details
                    }()

                    return LeaderboardEntry(
                        name: name, score: score, position: competitor.order ?? 0,
                        headshot: headshot, thruHole: thruHole, rounds: rounds,
                        isCut: isCut ? true : nil,
                        movement: movement,
                        flagURL: flagURL, flagAlt: flagAlt,
                        teeTime: teeTime,
                        roundDetails: roundDetails
                    )
                }

                // Backward-compatible lastPlay string
                let leaderboard = competitors.map { competitor in
                    let name = competitor.athlete?.displayName ?? "TBD"
                    let score = competitor.score ?? "--"
                    let rounds = (competitor.linescores ?? []).compactMap { ls -> String? in
                        guard let v = ls.value else { return nil }
                        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : "\(v)"
                    }.joined(separator: ",")
                    return rounds.isEmpty ? "\(name)|\(score)" : "\(name)|\(score)|\(rounds)"
                }.joined(separator: "\n")

                let venueName = competition.venue?.fullName

                return [Game(
                    idLiveScore: event.id, idEvent: event.id, strSport: sportType.rawValue,
                    idLeague: leagueID,
                    strHomeTeam: event.name, strAwayTeam: leaderName,
                    intHomeScore: nil, intAwayScore: leaderScore,
                    strStatus: event.status?.type.state, strProgress: progress,
                    strTimestamp: event.date,
                    lastPlay: leaderboard,
                    isCompleted: event.status?.type.completed, isoDate: nil,
                    leaderboardEntries: entries,
                    venueName: venueName,
                    golfCourseInfo: courseInfo
                )]
            }

            return []
        })
    }
    
    public var events: [Game]
    enum CodingKeys: String, CodingKey {
        case events
    }

    /// Extracts a `Game N` number from free-form ESPN strings (event names, notes).
    /// Matches "Game 3", "Game 3:", "- Game 3", "game3", etc.
    static func parseGameNumber(from source: String?) -> Int? {
        guard let source = source?.lowercased(), source.contains("game") else { return nil }
        // Tokenize on non-alphanumeric separators, scan for "game" followed by an integer.
        let tokens = source.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for (i, token) in tokens.enumerated() {
            if token == "game", i + 1 < tokens.count, let n = Int(tokens[i + 1]), (1...7).contains(n) {
                return n
            }
        }
        // Also catch the glued form, e.g. "game3"
        if let range = source.range(of: #"game\s*(\d+)"#, options: .regularExpression) {
            let digits = source[range].filter { $0.isNumber }
            if let n = Int(digits), (1...7).contains(n) { return n }
        }
        return nil
    }

    /// Strips a trailing `"- Game N"` (or `" Game N"`) so that round labels like
    /// `"East 1st Round - Game 2"` become just `"East 1st Round"` for display.
    static func stripGameSuffix(from source: String) -> String {
        guard let range = source.range(of: #"\s*[-–—]?\s*[Gg]ame\s+\d+\s*$"#, options: .regularExpression) else {
            return source
        }
        return String(source[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - GameLeader
public struct GameLeader: Codable, Equatable, Hashable {
    public let category: String
    public let categoryDisplay: String
    public let playerName: String
    public let displayValue: String
    public let headshot: String?

    public init(category: String, categoryDisplay: String, playerName: String, displayValue: String, headshot: String? = nil) {
        self.category = category
        self.categoryDisplay = categoryDisplay
        self.playerName = playerName
        self.displayValue = displayValue
        self.headshot = headshot
    }
}

// MARK: - PlayoffContext
/// Captures playoff/postseason series metadata when a game is part of a playoff bracket.
/// Populated during ESPN → Game translation when `season.type == 3` or a CompetitionSeries
/// is present on a playoff-eligible league (NBA/NHL/MLB/NFL/NCAA MBB).
public struct PlayoffContext: Codable, Equatable, Hashable {
    /// e.g. "NBA Finals", "Eastern Conf. Finals", "Wild Card"
    public var seriesTitle: String?
    /// Current game's number in the series (1-indexed). Nil for single-elim (NFL).
    public var gameNumber: Int?
    /// Series format length (e.g. 7 for best-of-7). Nil for single-elim.
    public var bestOf: Int?
    /// Wins so far for the home team in this series. Nil for single-elim.
    public var homeWins: Int?
    /// Wins so far for the away team in this series. Nil for single-elim.
    public var awayWins: Int?
    /// True once the series has been decided.
    public var seriesCompleted: Bool?
    /// True for games played on a neutral site (e.g. Super Bowl, Final Four).
    public var isNeutralSite: Bool?

    public init(seriesTitle: String? = nil, gameNumber: Int? = nil, bestOf: Int? = nil,
                homeWins: Int? = nil, awayWins: Int? = nil,
                seriesCompleted: Bool? = nil, isNeutralSite: Bool? = nil) {
        self.seriesTitle = seriesTitle
        self.gameNumber = gameNumber
        self.bestOf = bestOf
        self.homeWins = homeWins
        self.awayWins = awayWins
        self.seriesCompleted = seriesCompleted
        self.isNeutralSite = isNeutralSite
    }
}

// Shared, lazily-initialized timestamp parsers. Decoding ~1000 games per /schedules
// response used to allocate fresh formatters per game (>30 ms of work); hoisting them
// here means each format is created once for the process lifetime.
// `nonisolated(unsafe)` because Foundation's date formatters are documented as safe
// for concurrent reads on iOS 7+ once configured, but the compiler can't prove it.
fileprivate enum DateParsers {
    nonisolated(unsafe) static let iso8601 = ISO8601DateFormatter()
    static let dashedSeconds: DateFormatter = {
        let df = DateFormatter()
        df.timeZone = .init(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df
    }()
    static let dashedNoSeconds: DateFormatter = {
        let df = DateFormatter()
        df.timeZone = .init(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return df
    }()
    static let dashedZ: DateFormatter = {
        let df = DateFormatter()
        df.timeZone = .init(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return df
    }()

    static func parse(_ timestamp: String) -> Date? {
        if let d = iso8601.date(from: timestamp) { return d }
        if let d = dashedSeconds.date(from: timestamp) { return d }
        if let d = dashedNoSeconds.date(from: timestamp) { return d }
        return dashedZ.date(from: timestamp)
    }
}

// MARK: - Event
public struct Game: Identifiable, Equatable, Hashable {
    public init(idLiveScore: String? = nil, idEvent: String? = nil, strSport: String? = nil, idLeague: String? = nil, strLeague: String? = nil, idHomeTeam: String? = nil, idAwayTeam: String? = nil, strHomeTeam: String, strAwayTeam: String, strHomeTeamBadge: String? = nil, strAwayTeamBadge: String? = nil, intHomeScore: String? = nil, intAwayScore: String? = nil, strPlayer: String?? = nil, idPlayer: String?? = nil, intEventScore: String?? = nil, intEventScoreTotal: String?? = nil, strStatus: String? = nil, strProgress: String? = nil, strEventTime: String? = nil, dateEvent: String? = nil, updated: String? = nil, strTimestamp: String? = nil, lastPlay: String? = nil, homeLinescores: [Double]? = nil, awayLinescores: [Double]? = nil, homeLeaders: [GameLeader]? = nil, awayLeaders: [GameLeader]? = nil, isCompleted: Bool? = false, isoDate: Date?, leaderboardEntries: [LeaderboardEntry]? = nil, sessions: [EventSession]? = nil, venueName: String? = nil, homeTeamColor: String? = nil, awayTeamColor: String? = nil, homeRecord: String? = nil, awayRecord: String? = nil, circuitInfo: F1CircuitInfo? = nil, golfCourseInfo: GolfCourseInfo? = nil, legDisplay: String? = nil, aggregateScore: String? = nil, homeSeed: Int? = nil, awaySeed: Int? = nil, tournamentName: String? = nil, round: String? = nil, homeInjuries: [InjuryReport]? = nil, awayInjuries: [InjuryReport]? = nil, raceTiming: F1RaceTiming? = nil, playoff: PlayoffContext? = nil, lastPlayScoreboardID: String? = nil) {
        self.idLiveScore = idLiveScore
        self.idEvent = idEvent
        self._strSport = strSport
        self.idLeague = idLeague
        self._strLeague = strLeague
        self.idHomeTeam = idHomeTeam
        self.idAwayTeam = idAwayTeam
        self.strHomeTeam = strHomeTeam
        self.strAwayTeam = strAwayTeam
        self.strHomeTeamBadge = strHomeTeamBadge
        self.strAwayTeamBadge = strAwayTeamBadge
        self.intHomeScore = intHomeScore
        self.intAwayScore = intAwayScore
        self.strStatus = strStatus
        self.strProgress = strProgress
        self.strTimestamp = strTimestamp
        self.lastPlay = lastPlay
        self.homeLinescores = homeLinescores
        self.awayLinescores = awayLinescores
        self.homeLeaders = homeLeaders
        self.awayLeaders = awayLeaders
        self.isCompleted = isCompleted
        self.leaderboardEntries = leaderboardEntries
        self.sessions = sessions
        self.venueName = venueName
        self.homeTeamColor = homeTeamColor
        self.awayTeamColor = awayTeamColor
        self.homeRecord = homeRecord
        self.awayRecord = awayRecord
        self.circuitInfo = circuitInfo
        self.golfCourseInfo = golfCourseInfo
        self.legDisplay = legDisplay
        self.aggregateScore = aggregateScore
        self.homeSeed = homeSeed
        self.awaySeed = awaySeed
        self.tournamentName = tournamentName
        self.round = round
        self.homeInjuries = homeInjuries
        self.awayInjuries = awayInjuries
        self.raceTiming = raceTiming
        self.playoff = playoff
        self.lastPlayScoreboardID = lastPlayScoreboardID
        // Pre-compute date from strTimestamp if isoDate not provided
        if let isoDate {
            self.isoDate = isoDate
        } else if let strTimestamp {
            self.isoDate = DateParsers.parse(strTimestamp)
        } else {
            self.isoDate = nil
        }
    }

    public var id: String {
        idEvent ?? UUID().uuidString
    }
    public let idLiveScore, idEvent: String?
    public let idLeague: String?
    public let idHomeTeam, idAwayTeam: String?
    public let strHomeTeam: String
    public let strAwayTeam: String
    public let strHomeTeamBadge, strAwayTeamBadge: String?
    public let intHomeScore, intAwayScore: String?
    public let strStatus, strProgress: String?
    public let strTimestamp: String?
    public let lastPlay: String?
    public let homeLinescores: [Double]?
    public let awayLinescores: [Double]?
    public let homeLeaders: [GameLeader]?
    public let awayLeaders: [GameLeader]?
    public var isCompleted: Bool? = false
    public var isoDate: Date?
    public let leaderboardEntries: [LeaderboardEntry]?
    public let sessions: [EventSession]?
    public let venueName: String?
    public let homeTeamColor: String?
    public let awayTeamColor: String?
    public let homeRecord: String?
    public let awayRecord: String?
    public let circuitInfo: F1CircuitInfo?
    public let golfCourseInfo: GolfCourseInfo?
    public let legDisplay: String?
    public let aggregateScore: String?
    public let homeSeed: Int?
    public let awaySeed: Int?
    public let tournamentName: String?
    /// Tennis: round name (e.g. "Quarterfinal", "Round of 16"). Nil for non-tennis.
    public let round: String?
    public let homeInjuries: [InjuryReport]?
    public let awayInjuries: [InjuryReport]?
    public let raceTiming: F1RaceTiming?
    public let playoff: PlayoffContext?

    /// Transient scoreboard play ID (`competition.situation.lastPlay.id`) used server-side to
    /// decide when to re-fetch play-by-play from ESPN's summary endpoint. Not persisted to Redis
    /// or sent to clients — absent from Codable keys on purpose.
    public let lastPlayScoreboardID: String?

    // MARK: - Computed Properties (derived from idLeague)
    // Private storage for backward compatibility when decoding old data
    private let _strSport: String?
    private let _strLeague: String?

    /// Sport type, computed from idLeague when possible
    public var strSport: String? {
        if let id = idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) {
            return league.sport
        }
        return _strSport
    }

    /// League name, computed from idLeague when possible
    public var strLeague: String? {
        if let id = idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) {
            return league.leagueName
        }
        return _strLeague
    }
}

// MARK: - Codable
extension Game: Codable {
    enum CodingKeys: String, CodingKey {
        case idLiveScore, idEvent, idLeague, idHomeTeam, idAwayTeam
        case strHomeTeam, strAwayTeam, strHomeTeamBadge, strAwayTeamBadge
        case intHomeScore, intAwayScore
        case strStatus, strProgress, strTimestamp
        case lastPlay, homeLinescores, awayLinescores, homeLeaders, awayLeaders
        case isCompleted, isoDate
        case leaderboardEntries, sessions, venueName
        case homeTeamColor, awayTeamColor, homeRecord, awayRecord
        case circuitInfo, golfCourseInfo, legDisplay, aggregateScore
        case homeSeed, awaySeed, tournamentName, round
        case homeInjuries, awayInjuries
        case raceTiming
        case playoff
        // Computed properties - decoded for backward compatibility, not encoded
        case strSport, strLeague
        // Individual sport fallback (golf/tennis have null strHomeTeam/strAwayTeam)
        case strEvent
        // Deprecated fields - kept for decode compatibility only
        case strPlayer, idPlayer, intEventScore, intEventScoreTotal
        case strEventTime, dateEvent, updated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idLiveScore = try container.decodeIfPresent(String.self, forKey: .idLiveScore)
        idEvent = try container.decodeIfPresent(String.self, forKey: .idEvent)
        idLeague = try container.decodeIfPresent(String.self, forKey: .idLeague)
        idHomeTeam = try container.decodeIfPresent(String.self, forKey: .idHomeTeam)
        idAwayTeam = try container.decodeIfPresent(String.self, forKey: .idAwayTeam)
        let eventName = try container.decodeIfPresent(String.self, forKey: .strEvent)
        strHomeTeam = try container.decodeIfPresent(String.self, forKey: .strHomeTeam) ?? eventName ?? "TBD"
        strAwayTeam = try container.decodeIfPresent(String.self, forKey: .strAwayTeam) ?? "TBD"
        strHomeTeamBadge = try container.decodeIfPresent(String.self, forKey: .strHomeTeamBadge)
        strAwayTeamBadge = try container.decodeIfPresent(String.self, forKey: .strAwayTeamBadge)
        intHomeScore = try container.decodeIfPresent(String.self, forKey: .intHomeScore)
        intAwayScore = try container.decodeIfPresent(String.self, forKey: .intAwayScore)
        strStatus = try container.decodeIfPresent(String.self, forKey: .strStatus)
        strProgress = try container.decodeIfPresent(String.self, forKey: .strProgress)
        strTimestamp = try container.decodeIfPresent(String.self, forKey: .strTimestamp)
        lastPlay = try container.decodeIfPresent(String.self, forKey: .lastPlay)
        homeLinescores = try container.decodeIfPresent([Double].self, forKey: .homeLinescores)
        awayLinescores = try container.decodeIfPresent([Double].self, forKey: .awayLinescores)
        homeLeaders = try container.decodeIfPresent([GameLeader].self, forKey: .homeLeaders)
        awayLeaders = try container.decodeIfPresent([GameLeader].self, forKey: .awayLeaders)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted)
        isoDate = try container.decodeIfPresent(Date.self, forKey: .isoDate)
        leaderboardEntries = try container.decodeIfPresent([LeaderboardEntry].self, forKey: .leaderboardEntries)
        sessions = try container.decodeIfPresent([EventSession].self, forKey: .sessions)
        venueName = try container.decodeIfPresent(String.self, forKey: .venueName)
        homeTeamColor = try container.decodeIfPresent(String.self, forKey: .homeTeamColor)
        awayTeamColor = try container.decodeIfPresent(String.self, forKey: .awayTeamColor)
        homeRecord = try container.decodeIfPresent(String.self, forKey: .homeRecord)
        awayRecord = try container.decodeIfPresent(String.self, forKey: .awayRecord)
        circuitInfo = try container.decodeIfPresent(F1CircuitInfo.self, forKey: .circuitInfo)
        golfCourseInfo = try container.decodeIfPresent(GolfCourseInfo.self, forKey: .golfCourseInfo)
        legDisplay = try container.decodeIfPresent(String.self, forKey: .legDisplay)
        aggregateScore = try container.decodeIfPresent(String.self, forKey: .aggregateScore)
        // Sanitize seed values on decode — ESPN returns `99` as a "no rank" sentinel for
        // pro-league competitors, and older cached responses may still carry it. Any value
        // outside the realistic bracket range (1...16, NCAA tournament) is discarded.
        let rawHomeSeed = try container.decodeIfPresent(Int.self, forKey: .homeSeed)
        let rawAwaySeed = try container.decodeIfPresent(Int.self, forKey: .awaySeed)
        homeSeed = rawHomeSeed.flatMap { (1...16).contains($0) ? $0 : nil }
        awaySeed = rawAwaySeed.flatMap { (1...16).contains($0) ? $0 : nil }
        tournamentName = try container.decodeIfPresent(String.self, forKey: .tournamentName)
        round = try container.decodeIfPresent(String.self, forKey: .round)
        homeInjuries = try container.decodeIfPresent([InjuryReport].self, forKey: .homeInjuries)
        awayInjuries = try container.decodeIfPresent([InjuryReport].self, forKey: .awayInjuries)
        raceTiming = try container.decodeIfPresent(F1RaceTiming.self, forKey: .raceTiming)
        playoff = try container.decodeIfPresent(PlayoffContext.self, forKey: .playoff)
        // Transient server-side field, not persisted
        lastPlayScoreboardID = nil
        // Decode for backward compatibility with old cached data
        _strSport = try container.decodeIfPresent(String.self, forKey: .strSport)
        _strLeague = try container.decodeIfPresent(String.self, forKey: .strLeague)
        // Deprecated fields are ignored during decode

        // Pre-compute date from strTimestamp so standardDate never calls getDate() at runtime
        if isoDate == nil, let timestamp = strTimestamp {
            isoDate = DateParsers.parse(timestamp)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(idLiveScore, forKey: .idLiveScore)
        try container.encodeIfPresent(idEvent, forKey: .idEvent)
        try container.encodeIfPresent(idLeague, forKey: .idLeague)
        try container.encodeIfPresent(idHomeTeam, forKey: .idHomeTeam)
        try container.encodeIfPresent(idAwayTeam, forKey: .idAwayTeam)
        try container.encode(strHomeTeam, forKey: .strHomeTeam)
        try container.encode(strAwayTeam, forKey: .strAwayTeam)
        try container.encodeIfPresent(strHomeTeamBadge, forKey: .strHomeTeamBadge)
        try container.encodeIfPresent(strAwayTeamBadge, forKey: .strAwayTeamBadge)
        try container.encodeIfPresent(intHomeScore, forKey: .intHomeScore)
        try container.encodeIfPresent(intAwayScore, forKey: .intAwayScore)
        try container.encodeIfPresent(strStatus, forKey: .strStatus)
        try container.encodeIfPresent(strProgress, forKey: .strProgress)
        try container.encodeIfPresent(strTimestamp, forKey: .strTimestamp)
        try container.encodeIfPresent(lastPlay, forKey: .lastPlay)
        try container.encodeIfPresent(homeLinescores, forKey: .homeLinescores)
        try container.encodeIfPresent(awayLinescores, forKey: .awayLinescores)
        try container.encodeIfPresent(homeLeaders, forKey: .homeLeaders)
        try container.encodeIfPresent(awayLeaders, forKey: .awayLeaders)
        try container.encodeIfPresent(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(isoDate, forKey: .isoDate)
        try container.encodeIfPresent(leaderboardEntries, forKey: .leaderboardEntries)
        try container.encodeIfPresent(sessions, forKey: .sessions)
        try container.encodeIfPresent(venueName, forKey: .venueName)
        try container.encodeIfPresent(homeTeamColor, forKey: .homeTeamColor)
        try container.encodeIfPresent(awayTeamColor, forKey: .awayTeamColor)
        try container.encodeIfPresent(homeRecord, forKey: .homeRecord)
        try container.encodeIfPresent(awayRecord, forKey: .awayRecord)
        try container.encodeIfPresent(circuitInfo, forKey: .circuitInfo)
        try container.encodeIfPresent(golfCourseInfo, forKey: .golfCourseInfo)
        try container.encodeIfPresent(legDisplay, forKey: .legDisplay)
        try container.encodeIfPresent(aggregateScore, forKey: .aggregateScore)
        try container.encodeIfPresent(homeSeed, forKey: .homeSeed)
        try container.encodeIfPresent(awaySeed, forKey: .awaySeed)
        try container.encodeIfPresent(tournamentName, forKey: .tournamentName)
        try container.encodeIfPresent(round, forKey: .round)
        try container.encodeIfPresent(homeInjuries, forKey: .homeInjuries)
        try container.encodeIfPresent(awayInjuries, forKey: .awayInjuries)
        try container.encodeIfPresent(raceTiming, forKey: .raceTiming)
        try container.encodeIfPresent(playoff, forKey: .playoff)
        // Note: strSport and strLeague are not encoded - they're computed from idLeague
        // Deprecated fields are not encoded: strPlayer, idPlayer, intEventScore,
        // intEventScoreTotal, strEventTime, dateEvent, updated
    }
}

extension Game {
    /// Whether this is a tennis match (head-to-head) as opposed to a tournament overview
    /// Tennis matches from Path #2 have idHomeTeam/idAwayTeam set; tournament entries from Path #3 don't.
    public var isTennisMatch: Bool {
        guard let id = idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) else { return false }
        return league.isTennis && idHomeTeam != nil && idAwayTeam != nil
    }

    /// Whether this game represents an individual sport (golf/tennis/racing tournament) rather than a team head-to-head
    public var isIndividualSport: Bool {
        if let id = idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) {
            return league.isGolf || league.isTennis || league.isRacing
        }
        return strSport == "golf" || strSport == "tennis" || strSport == "racing"
    }

    /// Whether this is an F1 race
    public var isRace: Bool {
        if let id = idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) {
            return league.isRacing
        }
        return strSport == "racing"
    }

    /// Best-effort playoff marker when structured `playoff` data isn't available
    /// (e.g. stale cached responses, or data paths that bypass ESPN scoreboard parsing).
    /// Checks league + team-name text + date window to surface a round label.
    public var fallbackPostseasonTitle: String? {
        guard let leagueID = idLeague.flatMap(Int.init).flatMap(Leagues.init(rawValue:)) else {
            return nil
        }
        let eligible: Set<Leagues> = [.nba, .nhl, .mlb, .nfl]
        guard eligible.contains(leagueID) else { return nil }

        let combined = (strHomeTeam + " " + strAwayTeam).lowercased()
        let markers = [
            "playoff", "postseason", "wild card", "wild-card", "divisional",
            "conference final", "conference semifinal",
            "nba finals", "stanley cup", "world series",
            "alcs", "nlcs", "alds", "nlds",
            "division series", "championship series", "super bowl"
        ]
        if let match = markers.first(where: { combined.contains($0) }) {
            return match.capitalized
        }

        // Date-window fallback for each league's typical postseason.
        if let date = isoDate {
            let month = Calendar(identifier: .gregorian).component(.month, from: date)
            switch leagueID {
            case .nba:  if (4...6).contains(month)  { return "NBA Postseason" }
            case .nhl:  if (4...6).contains(month)  { return "NHL Postseason" }
            case .mlb:  if month == 10 || month == 11 { return "MLB Postseason" }
            case .nfl:  if month == 1 || month == 2 { return "NFL Postseason" }
            default: break
            }
        }
        return nil
    }

    /// Structured leaderboard with headshots and thru-hole data.
    /// Falls back to parsing `lastPlay` when `leaderboardEntries` is not available (backward compat).
    public var resolvedLeaderboard: [LeaderboardEntry] {
        if let entries = leaderboardEntries, !entries.isEmpty { return entries }
        // Fallback for racing: parse raceLeaderboard
        if isRace {
            return raceLeaderboard.enumerated().map { index, entry in
                LeaderboardEntry(name: entry.name, score: entry.position, position: index + 1,
                                 constructor: entry.constructor.isEmpty ? nil : entry.constructor,
                                 gap: entry.gap.isEmpty ? nil : entry.gap)
            }
        }
        // Fallback for golf/tennis: parse leaderboard
        return leaderboard.enumerated().map { index, entry in
            LeaderboardEntry(name: entry.name, score: entry.score, position: index + 1, rounds: entry.rounds)
        }
    }

    /// Parses race leaderboard from `lastPlay` for F1 data
    /// Format: "DriverName|Position|Gap|ConstructorName" per line
    public var raceLeaderboard: [(name: String, position: String, gap: String, constructor: String)] {
        guard let lastPlay else { return [] }
        return lastPlay.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 2 else { return nil }
            let name = parts[0]
            let position = parts[1]
            let gap = parts.count >= 3 ? parts[2] : ""
            let constructor = parts.count >= 4 ? parts[3] : ""
            return (name: name, position: position, gap: gap, constructor: constructor)
        }
    }

    /// Parses the leaderboard from `lastPlay`
    /// Supports both old format ("Name|Score") and new format ("Name|Score|R1,R2,R3")
    public var leaderboard: [(name: String, score: String, rounds: [String])] {
        guard let lastPlay else { return [] }
        return lastPlay.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 2 else { return nil }
            let rounds = parts.count >= 3 ? parts[2].components(separatedBy: ",") : []
            return (name: parts[0], score: parts[1], rounds: rounds)
        }
    }

    public func periodLabels(count: Int) -> [String] {
        guard let sport = strSport.flatMap({ SportType(rawValue: $0) }) else {
            return (1...count).map { "\($0)" }
        }
        switch sport {
        case .basketball, .nfl:
            // Q1, Q2, Q3, Q4, OT, OT2...
            return (0..<count).map { i in
                if i < 4 { return "Q\(i + 1)" }
                else if i == 4 { return "OT" }
                else { return "OT\(i - 3)" }
            }
        case .hockey:
            // P1, P2, P3, OT, OT2...
            return (0..<count).map { i in
                if i < 3 { return "P\(i + 1)" }
                else if i == 3 { return "OT" }
                else { return "OT\(i - 2)" }
            }
        case .mlb:
            return (1...count).map { "\($0)" }
        case .soccer:
            // 1H, 2H, ET1, ET2, PEN
            let labels = ["1H", "2H", "ET1", "ET2", "PEN"]
            return (0..<count).map { i in
                i < labels.count ? labels[i] : "\(i + 1)"
            }
        case .golf, .tennis:
            return (1...count).map { "\($0)" }
        case .racing:
            return (1...count).map { "Lap \($0)" }
        }
    }

    /// Whether this is a major golf tournament (Masters, US Open, PGA Championship, The Open)
    public var isMajor: Bool {
        let name = strHomeTeam.lowercased()
        return name.contains("masters") ||
               name.contains("u.s. open") || name.contains("us open") ||
               name.contains("pga championship") ||
               name.contains("the open championship") || name.contains("the open")
    }

    /// Course par — from enrichment data when available, falling back to hardcoded majors
    public var coursePar: Int? {
        if let par = golfCourseInfo?.par { return par }
        let name = strHomeTeam.lowercased()
        if name.contains("masters") { return 72 }
        if name.contains("pga championship") { return 72 }
        if name.contains("u.s. open") || name.contains("us open") { return 70 }
        if name.contains("the open") { return 72 }
        return nil
    }

    public var sportType: SportType? {
        guard let id = idLeague, let leagueID = Int(id), let league = Leagues(rawValue: leagueID) else { return nil }
        return SportType(league: league)
    }

    public var hasDoneStatus: Bool {
        let invalidStrings = ["NS", "FT", "AOT", "pre", "Final", "Final/OT", "AP", "post"]
        if let isCompleted {
            return invalidStrings.contains(where: {$0 == strStatus}) || invalidStrings.contains(where: {$0 == strProgress}) || isCompleted
        } else {
            return invalidStrings.contains(where: {$0 == strStatus}) || invalidStrings.contains(where: {$0 == strProgress})
        }
    }
    public func getDate(dateFormatter: DateFormatter, isoFormatter: ISO8601DateFormatter) -> Date? {
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.timeZone = .init(secondsFromGMT: 0)
        guard let timestamp = strTimestamp else { return nil }
        if let date = isoFormatter.date(from: timestamp) {
            return date
        }
        if let date = dateFormatter.date(from: timestamp) {
            return date
        }
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = dateFormatter.date(from: timestamp) {
            return date
        }
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        if let date = dateFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }

}

public extension Game {
    /// Returns a copy of this game with the provided fields overridden; any argument left at
    /// its default (`nil`) keeps the current value. Centralizes the field-by-field copy that
    /// the server's merge/translate paths previously open-coded as ~40-parameter `Game(...)`
    /// calls, and is the building block the reconcile engine uses to overlay reconciled dynamic
    /// fields onto a schedule-sourced identity skeleton.
    ///
    /// Semantics note: a `nil` argument means "keep the existing value" — this helper cannot
    /// clear an optional field back to `nil`. `strSport`/`strLeague` are intentionally not
    /// parameters: they are computed from `idLeague`. `isoDate` is preserved as-is (no recompute
    /// from `strTimestamp`).
    func updated(
        idLiveScore: String? = nil,
        idEvent: String? = nil,
        idLeague: String? = nil,
        idHomeTeam: String? = nil,
        idAwayTeam: String? = nil,
        strHomeTeam: String? = nil,
        strAwayTeam: String? = nil,
        strHomeTeamBadge: String? = nil,
        strAwayTeamBadge: String? = nil,
        intHomeScore: String? = nil,
        intAwayScore: String? = nil,
        strStatus: String? = nil,
        strProgress: String? = nil,
        strTimestamp: String? = nil,
        lastPlay: String? = nil,
        homeLinescores: [Double]? = nil,
        awayLinescores: [Double]? = nil,
        homeLeaders: [GameLeader]? = nil,
        awayLeaders: [GameLeader]? = nil,
        isCompleted: Bool? = nil,
        isoDate: Date? = nil,
        leaderboardEntries: [LeaderboardEntry]? = nil,
        sessions: [EventSession]? = nil,
        venueName: String? = nil,
        homeTeamColor: String? = nil,
        awayTeamColor: String? = nil,
        homeRecord: String? = nil,
        awayRecord: String? = nil,
        circuitInfo: F1CircuitInfo? = nil,
        golfCourseInfo: GolfCourseInfo? = nil,
        legDisplay: String? = nil,
        aggregateScore: String? = nil,
        homeSeed: Int? = nil,
        awaySeed: Int? = nil,
        tournamentName: String? = nil,
        round: String? = nil,
        homeInjuries: [InjuryReport]? = nil,
        awayInjuries: [InjuryReport]? = nil,
        raceTiming: F1RaceTiming? = nil,
        playoff: PlayoffContext? = nil,
        lastPlayScoreboardID: String? = nil
    ) -> Game {
        Game(
            idLiveScore: idLiveScore ?? self.idLiveScore,
            idEvent: idEvent ?? self.idEvent,
            strSport: nil,
            idLeague: idLeague ?? self.idLeague,
            strLeague: nil,
            idHomeTeam: idHomeTeam ?? self.idHomeTeam,
            idAwayTeam: idAwayTeam ?? self.idAwayTeam,
            strHomeTeam: strHomeTeam ?? self.strHomeTeam,
            strAwayTeam: strAwayTeam ?? self.strAwayTeam,
            strHomeTeamBadge: strHomeTeamBadge ?? self.strHomeTeamBadge,
            strAwayTeamBadge: strAwayTeamBadge ?? self.strAwayTeamBadge,
            intHomeScore: intHomeScore ?? self.intHomeScore,
            intAwayScore: intAwayScore ?? self.intAwayScore,
            strStatus: strStatus ?? self.strStatus,
            strProgress: strProgress ?? self.strProgress,
            strTimestamp: strTimestamp ?? self.strTimestamp,
            lastPlay: lastPlay ?? self.lastPlay,
            homeLinescores: homeLinescores ?? self.homeLinescores,
            awayLinescores: awayLinescores ?? self.awayLinescores,
            homeLeaders: homeLeaders ?? self.homeLeaders,
            awayLeaders: awayLeaders ?? self.awayLeaders,
            isCompleted: isCompleted ?? self.isCompleted,
            isoDate: isoDate ?? self.isoDate,
            leaderboardEntries: leaderboardEntries ?? self.leaderboardEntries,
            sessions: sessions ?? self.sessions,
            venueName: venueName ?? self.venueName,
            homeTeamColor: homeTeamColor ?? self.homeTeamColor,
            awayTeamColor: awayTeamColor ?? self.awayTeamColor,
            homeRecord: homeRecord ?? self.homeRecord,
            awayRecord: awayRecord ?? self.awayRecord,
            circuitInfo: circuitInfo ?? self.circuitInfo,
            golfCourseInfo: golfCourseInfo ?? self.golfCourseInfo,
            legDisplay: legDisplay ?? self.legDisplay,
            aggregateScore: aggregateScore ?? self.aggregateScore,
            homeSeed: homeSeed ?? self.homeSeed,
            awaySeed: awaySeed ?? self.awaySeed,
            tournamentName: tournamentName ?? self.tournamentName,
            round: round ?? self.round,
            homeInjuries: homeInjuries ?? self.homeInjuries,
            awayInjuries: awayInjuries ?? self.awayInjuries,
            raceTiming: raceTiming ?? self.raceTiming,
            playoff: playoff ?? self.playoff,
            lastPlayScoreboardID: lastPlayScoreboardID ?? self.lastPlayScoreboardID
        )
    }
}
