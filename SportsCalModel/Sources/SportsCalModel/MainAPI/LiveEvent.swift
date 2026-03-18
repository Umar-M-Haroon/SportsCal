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

                let homeColor = homeTeam.color
                let awayColor = awayTeam.color
                let homeRec = home.records?.first(where: { $0.type == "total" })?.summary
                let awayRec = away.records?.first(where: { $0.type == "total" })?.summary

                // Compute aggregate score for multi-leg ties (e.g. UCL knockout)
                var aggregateScore: String?
                if let seriesCompetitors = competition.series?.competitors,
                   seriesCompetitors.count == 2 {
                    let homeAgg = seriesCompetitors.first(where: { $0.id == homeTeam.id })?.aggregateScore
                    let awayAgg = seriesCompetitors.first(where: { $0.id == awayTeam.id })?.aggregateScore
                    if let h = homeAgg, let a = awayAgg {
                        aggregateScore = "Agg: \(Int(a))-\(Int(h))"
                    }
                }

                return [Game(
                    idLiveScore: event.id, idEvent: event.id, strSport: sportType.rawValue,
                    idLeague: leagueID, idHomeTeam: homeTeam.id, idAwayTeam: awayTeam.id,
                    strHomeTeam: homeTeam.displayName, strAwayTeam: awayTeam.displayName,
                    strHomeTeamBadge: homeTeam.logo, strAwayTeamBadge: awayTeam.logo,
                    intHomeScore: home.score, intAwayScore: away.score,
                    strStatus: event.status?.type.state, strProgress: event.status?.type.shortDetail,
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
                    aggregateScore: aggregateScore
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
                        return Game(
                            idLiveScore: competition.id, idEvent: competition.id, strSport: sportType.rawValue,
                            idLeague: leagueID, idHomeTeam: home.id, idAwayTeam: away.id,
                            strHomeTeam: homeName, strAwayTeam: awayName,
                            strHomeTeamBadge: home.athlete?.headshot, strAwayTeamBadge: away.athlete?.headshot,
                            intHomeScore: home.score, intAwayScore: away.score,
                            strStatus: competition.status?.type.state ?? event.status?.type.state,
                            strProgress: competition.status?.type.shortDetail ?? event.status?.type.shortDetail,
                            strTimestamp: competition.date,
                            homeLinescores: hLinescores?.isEmpty == true ? nil : hLinescores,
                            awayLinescores: aLinescores?.isEmpty == true ? nil : aLinescores,
                            isCompleted: competition.status?.type.completed ?? event.status?.type.completed, isoDate: nil
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
                        let score = competitor.score ?? "P\(competitor.order)"
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
                            name: name, score: score, position: competitor.order,
                            headshot: competitor.athlete?.headshot,
                            constructor: constructorName.isEmpty ? nil : constructorName,
                            gap: gap.isEmpty ? nil : gap
                        )
                    }
                    return EventSession(
                        sessionType: sessionType, sessionName: sessionName,
                        status: competition.status?.type.state,
                        progress: competition.status?.type.shortDetail,
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
                let progress = primarySession.progress ?? event.status?.type.shortDetail

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
                let progress = competition.status?.type.shortDetail ?? event.status?.type.shortDetail
                let competitors = Array((competition.competitors ?? []).prefix(30))

                // Build structured leaderboard entries with headshots + thru-hole
                let entries: [LeaderboardEntry] = competitors.enumerated().map { index, competitor in
                    let name = competitor.athlete?.displayName ?? "TBD"
                    let score = competitor.score ?? "--"
                    let headshot = competitor.athlete?.headshot
                    let thruHole = competitor.statistics?.first(where: { $0.name == "thruHole" })?.displayValue
                    let rounds = (competitor.linescores ?? []).compactMap { ls -> String? in
                        guard let v = ls.value else { return nil }
                        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : "\(v)"
                    }
                    return LeaderboardEntry(
                        name: name, score: score, position: competitor.order,
                        headshot: headshot, thruHole: thruHole, rounds: rounds
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
                    venueName: venueName
                )]
            }

            return []
        })
    }
    
    public var events: [Game]
    enum CodingKeys: String, CodingKey {
        case events
    }
}

// MARK: - GameLeader
public struct GameLeader: Codable, Equatable, Hashable {
    public let category: String
    public let categoryDisplay: String
    public let playerName: String
    public let displayValue: String
    public let headshot: String?
}

// MARK: - Event
public struct Game: Identifiable, Equatable, Hashable {
    public init(idLiveScore: String? = nil, idEvent: String? = nil, strSport: String? = nil, idLeague: String? = nil, strLeague: String? = nil, idHomeTeam: String? = nil, idAwayTeam: String? = nil, strHomeTeam: String, strAwayTeam: String, strHomeTeamBadge: String? = nil, strAwayTeamBadge: String? = nil, intHomeScore: String? = nil, intAwayScore: String? = nil, strPlayer: String?? = nil, idPlayer: String?? = nil, intEventScore: String?? = nil, intEventScoreTotal: String?? = nil, strStatus: String? = nil, strProgress: String? = nil, strEventTime: String? = nil, dateEvent: String? = nil, updated: String? = nil, strTimestamp: String? = nil, lastPlay: String? = nil, homeLinescores: [Double]? = nil, awayLinescores: [Double]? = nil, homeLeaders: [GameLeader]? = nil, awayLeaders: [GameLeader]? = nil, isCompleted: Bool? = false, isoDate: Date?, leaderboardEntries: [LeaderboardEntry]? = nil, sessions: [EventSession]? = nil, venueName: String? = nil, homeTeamColor: String? = nil, awayTeamColor: String? = nil, homeRecord: String? = nil, awayRecord: String? = nil, circuitInfo: F1CircuitInfo? = nil, legDisplay: String? = nil, aggregateScore: String? = nil) {
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
        self.legDisplay = legDisplay
        self.aggregateScore = aggregateScore
        // Pre-compute date from strTimestamp if isoDate not provided
        if let isoDate {
            self.isoDate = isoDate
        } else if let strTimestamp {
            let iso = ISO8601DateFormatter()
            let df = DateFormatter()
            df.timeZone = .init(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = iso.date(from: strTimestamp) {
                self.isoDate = d
            } else if let d = df.date(from: strTimestamp) {
                self.isoDate = d
            } else {
                df.dateFormat = "yyyy-MM-dd'T'HH:mm"
                if let d = df.date(from: strTimestamp) {
                    self.isoDate = d
                } else {
                    df.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
                    self.isoDate = df.date(from: strTimestamp)
                }
            }
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
    public let legDisplay: String?
    public let aggregateScore: String?

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
        case circuitInfo, legDisplay, aggregateScore
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
        legDisplay = try container.decodeIfPresent(String.self, forKey: .legDisplay)
        aggregateScore = try container.decodeIfPresent(String.self, forKey: .aggregateScore)
        // Decode for backward compatibility with old cached data
        _strSport = try container.decodeIfPresent(String.self, forKey: .strSport)
        _strLeague = try container.decodeIfPresent(String.self, forKey: .strLeague)
        // Deprecated fields are ignored during decode

        // Pre-compute date from strTimestamp so standardDate never calls getDate() at runtime
        if isoDate == nil, let timestamp = strTimestamp {
            let iso = ISO8601DateFormatter()
            let df = DateFormatter()
            df.timeZone = .init(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = iso.date(from: timestamp) {
                isoDate = d
            } else if let d = df.date(from: timestamp) {
                isoDate = d
            } else {
                df.dateFormat = "yyyy-MM-dd'T'HH:mm"
                if let d = df.date(from: timestamp) {
                    isoDate = d
                } else {
                    df.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
                    isoDate = df.date(from: timestamp)
                }
            }
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
        try container.encodeIfPresent(legDisplay, forKey: .legDisplay)
        try container.encodeIfPresent(aggregateScore, forKey: .aggregateScore)
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
