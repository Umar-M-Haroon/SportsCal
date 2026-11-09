//
//  TennisResultsArchive.swift
//  SportsCalServer
//
//  Serves `/tennis/h2h`: two players' singles meetings since `firstYear`.
//
//  ESPN has no head-to-head endpoint, and its athlete event log is only references (one
//  more request per match). Its scoreboard does carry every draw of every tournament in a
//  date range, back years, so the archive is built from that: one board per tour per
//  month, slimmed to finished main-draw singles and kept in Redis. A finished month never
//  changes, so it's fetched once (and again after a year, in case ESPN corrected it). The
//  current and previous months are refetched every few hours.
//
//  Requests read an in-process index (pair → meetings) built from those month keys, so a
//  head-to-head never touches ESPN and costs one dictionary lookup. The index reloads
//  itself every few hours and whenever the job writes a month.
//

import Foundation
import Vapor
import Queues
import Logging
import SportsCalModel

enum TennisResultsArchive {
    /// The first season searched. ESPN's boards go further back, but this keeps the
    /// archive (and the index held in memory) small: about 5,000 matches a season.
    static let firstYear = 2019
    static let tours: [Leagues] = [.atp, .wta]
    /// Months fetched per tour per run, newest first, while the archive fills.
    static let fetchBudget = 24
    static let recentTTL: TimeInterval = 6 * 60 * 60
    static let settledTTL: TimeInterval = 400 * 24 * 60 * 60

    // MARK: Keys

    static func key(tour: Leagues, year: Int, month: Int, isDebug: Bool) -> String {
        (isDebug ? "debug-" : "") + "Tennis Archive v1 \(tour.rawValue)-\(year)-\(month < 10 ? "0" : "")\(month)"
    }

    /// Every (year, month) from January `firstYear` to `now`'s month, newest first.
    static func months(through now: Date) -> [(year: Int, month: Int)] {
        let parts = utcCalendar.dateComponents([.year, .month], from: now)
        guard let lastYear = parts.year, let lastMonth = parts.month else { return [] }
        var result: [(year: Int, month: Int)] = []
        var year = lastYear, month = lastMonth
        while year > firstYear || (year == firstYear && month >= 1) {
            result.append((year, month))
            month -= 1
            if month == 0 { month = 12; year -= 1 }
        }
        return result
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    // MARK: Fetching

    /// One tour's finished main-draw singles from ESPN's board for a calendar month.
    static func fetchMonth(tour: Leagues, year: Int, month: Int, client: Client) async throws -> [ArchivedTennisMatch] {
        guard let slug = tour.espnSlug else { return [] }
        let start = year * 10000 + month * 100 + 1
        let days = utcCalendar.range(of: .day, in: .month,
                                     for: utcCalendar.date(from: DateComponents(year: year, month: month)) ?? Date())?.count ?? 31
        let end = year * 10000 + month * 100 + days
        let url = "https://site.api.espn.com/apis/site/v2/sports/tennis/\(slug)/scoreboard?dates=\(start)-\(end)"
        let response = try await ESPNNetworking.performGet(client, URI(string: url))
        guard response.status == .ok else { throw Abort(.badGateway) }
        let board = try response.content.decode(TennisArchiveBoard.self)
        return matches(in: board, tour: tour)
    }

    /// The finished main-draw singles of `tour`'s draws on `board`. ESPN puts a combined
    /// event's whole draw on both tours' boards, so the draw slug, not the board, decides.
    static func matches(in board: TennisArchiveBoard, tour: Leagues) -> [ArchivedTennisMatch] {
        var result: [ArchivedTennisMatch] = []
        var seen = Set<String>()
        for event in board.events ?? [] {
            let tournament = event.name ?? ""
            for grouping in event.groupings ?? [] {
                let slug = grouping.grouping?.slug ?? ""
                guard slug.contains("singles"), case .tour(let drawTour)? = TennisDraw(slug: slug), drawTour == tour else { continue }
                for competition in grouping.competitions ?? [] {
                    guard let match = ArchivedTennisMatch(competition: competition, tournament: tournament),
                          seen.insert(match.i).inserted else { continue }
                    result.append(match)
                }
            }
        }
        return result
    }

    // MARK: Filling

    /// Fetches the months the archive is missing (up to `fetchBudget` per tour, newest
    /// first) and stores each. Returns how many were written.
    @discardableResult
    static func fill(app: Application, now: Date = Date(), logger: Logger) async -> Int {
        let isDebug = app.environment == .development
        var written = 0
        for tour in tours {
            var budget = fetchBudget
            for (index, month) in months(through: now).enumerated() where budget > 0 {
                let key = key(tour: tour, year: month.year, month: month.month, isDebug: isDebug)
                // The current and previous months expire quickly, so "missing" covers them too.
                if (try? await app.kv.exists(key)) == true { continue }
                budget -= 1
                do {
                    let matches = try await fetchMonth(tour: tour, year: month.year, month: month.month, client: app.client)
                    try await app.kv.setJSON(key, value: matches, ttl: index < 2 ? recentTTL : settledTTL)
                    written += 1
                } catch {
                    logger.warning("Tennis archive: \(tour.rawValue) \(month.year)-\(month.month) failed: \(error)")
                    break
                }
            }
        }
        if written > 0 {
            await TennisH2HIndex.shared.invalidate()
            logger.info("Tennis archive: wrote \(written) months")
        }
        return written
    }
}

/// Hourly: tops up the archive. Most hours it finds nothing missing but the two recent
/// months when they've expired.
struct TennisResultsArchiveJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.tennis-archive")

    func run(context: QueueContext) async throws {
        let app = context.application
        _ = try await JobLock.withLock(
            app.kv, name: "tennis-archive", ttl: 50 * 60, instanceID: app.instanceID, logger: Self.logger,
            body: { await TennisResultsArchive.fill(app: app, logger: Self.logger) }
        )
    }
}

// MARK: - Stored form

/// A finished singles match as the archive stores it. Short keys, since a season is
/// thousands of these.
struct ArchivedTennisMatch: Codable, Equatable, Sendable {
    /// Competition id.
    var i: String
    /// yyyy-MM-dd.
    var d: String
    /// Tournament.
    var t: String
    /// Round.
    var r: String?
    /// Home and away athlete ids and names.
    var h: String
    var a: String
    var hn: String
    var an: String
    /// Sets as [home, away] or [home, away, loser's tiebreak points].
    var s: [[Int]]
    /// "h" or "a".
    var w: String?
    /// "ret." / "w/o".
    var m: String?

    init(i: String, d: String, t: String, r: String?, h: String, a: String, hn: String, an: String,
         s: [[Int]], w: String?, m: String?) {
        self.i = i; self.d = d; self.t = t; self.r = r
        self.h = h; self.a = a; self.hn = hn; self.an = an
        self.s = s; self.w = w; self.m = m
    }

    /// Nil for a match that isn't finished, is qualifying, or lacks two real players.
    init?(competition: TennisArchiveBoard.Competition, tournament: String) {
        guard competition.status?.type?.completed == true,
              let round = competition.round?.displayName, !round.lowercased().contains("qualif"),
              let competitors = competition.competitors,
              let home = competitors.first(where: { $0.homeAway == "home" }),
              let away = competitors.first(where: { $0.homeAway == "away" }),
              let homeID = home.id, let awayID = away.id,
              Self.isRealID(homeID), Self.isRealID(awayID),
              let homeName = home.athlete?.displayName, let awayName = away.athlete?.displayName,
              let date = competition.date, date.count >= 10 else { return nil }
        let homeSets = home.linescores ?? []
        let awaySets = away.linescores ?? []
        var sets: [[Int]] = []
        for index in 0..<min(homeSets.count, awaySets.count) {
            guard let h = homeSets[index].value, let a = awaySets[index].value else { continue }
            var set = [Int(h), Int(a)]
            if let tiebreak = [homeSets[index].tiebreak, awaySets[index].tiebreak].compactMap({ $0 }).min() {
                set.append(tiebreak)
            }
            sets.append(set)
        }
        let status = (competition.status?.type?.name ?? "").uppercased()
        let marker: String? = status.contains("WALKOVER") ? "w/o" : (status.contains("RETIRED") ? "ret." : nil)
        self.init(i: competition.id, d: String(date.prefix(10)), t: tournament, r: round,
                  h: homeID, a: awayID, hn: homeName, an: awayName, s: sets,
                  w: home.winner == true ? "h" : (away.winner == true ? "a" : nil), m: marker)
    }

    static func isRealID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isNumber) && id != "0"
    }

    var meeting: TennisMeeting {
        TennisMeeting(
            id: i, date: d, tournament: t, round: r, homeID: h, awayID: a, homeName: hn, awayName: an,
            sets: s.compactMap { set in
                set.count >= 2 ? TennisMeeting.SetScore(home: set[0], away: set[1], tiebreak: set.count > 2 ? set[2] : nil) : nil
            },
            winnerID: w == "h" ? h : (w == "a" ? a : nil),
            marker: m
        )
    }
}

/// Just the parts of ESPN's tennis scoreboard the archive keeps. A month's board is
/// several MB; decoding only these fields keeps the job light.
struct TennisArchiveBoard: Decodable {
    struct Event: Decodable {
        let name: String?
        let groupings: [Grouping]?
    }
    struct Grouping: Decodable {
        struct Slug: Decodable { let slug: String? }
        let grouping: Slug?
        let competitions: [Competition]?
    }
    struct Competition: Decodable {
        struct Round: Decodable { let displayName: String? }
        struct Status: Decodable {
            struct Kind: Decodable {
                let name: String?
                let completed: Bool?
            }
            let type: Kind?
        }
        let id: String
        let date: String?
        let round: Round?
        let status: Status?
        let competitors: [Competitor]?
    }
    struct Competitor: Decodable {
        struct Athlete: Decodable { let displayName: String? }
        struct Line: Decodable {
            let value: Double?
            let tiebreak: Int?
        }
        let id: String?
        let homeAway: String?
        let winner: Bool?
        let athlete: Athlete?
        let linescores: [Line]?
    }
    let events: [Event]?
}

// MARK: - Index

/// Pair → meetings, built from the archive's month keys and kept in memory.
actor TennisH2HIndex {
    static let shared = TennisH2HIndex()
    static let maxAge: TimeInterval = 6 * 60 * 60

    private var byPair: [String: [TennisMeeting]] = [:]
    private var loadedAt: Date?
    private var loading: Task<[String: [TennisMeeting]], Never>?

    static func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    /// The two players' meetings, loading the index first when it's stale.
    ///
    /// - Parameters:
    ///   - player: An ESPN athlete id.
    ///   - opponent: The other athlete id.
    ///   - kv: Where the archive's month keys live.
    ///   - isDebug: Read the development keyspace.
    func headToHead(player: String, opponent: String, kv: KeyValueStore, isDebug: Bool) async -> TennisHeadToHead {
        if loadedAt.map({ Date().timeIntervalSince($0) > Self.maxAge }) ?? true {
            await reload(kv: kv, isDebug: isDebug)
        }
        return TennisHeadToHead(playerID: player, opponentID: opponent,
                                meetings: byPair[Self.pairKey(player, opponent)] ?? [],
                                since: TennisResultsArchive.firstYear)
    }

    /// Drops the index so the next request rebuilds it.
    func invalidate() {
        loadedAt = nil
    }

    private func reload(kv: KeyValueStore, isDebug: Bool) async {
        // One load at a time; requests arriving meanwhile wait for it.
        if let loading {
            byPair = await loading.value
            return
        }
        let task = Task { await Self.build(kv: kv, isDebug: isDebug) }
        loading = task
        byPair = await task.value
        loadedAt = Date()
        loading = nil
    }

    private static func build(kv: KeyValueStore, isDebug: Bool) async -> [String: [TennisMeeting]] {
        let keys = TennisResultsArchive.tours.flatMap { tour in
            TennisResultsArchive.months(through: Date()).map {
                TennisResultsArchive.key(tour: tour, year: $0.year, month: $0.month, isDebug: isDebug)
            }
        }
        var index: [String: [TennisMeeting]] = [:]
        var seen = Set<String>()
        let decoder = JSONDecoder()
        // Small MGETs: each month is tens of KB, and one huge read is what wedged the
        // Redis pool in July 2026.
        for start in stride(from: 0, to: keys.count, by: 12) {
            let chunk = Array(keys[start..<min(start + 12, keys.count)])
            let values = (try? await kv.mget(chunk)) ?? []
            for value in values {
                guard let data = value?.data(using: .utf8),
                      let matches = try? decoder.decode([ArchivedTennisMatch].self, from: data) else { continue }
                for match in matches where seen.insert(match.i).inserted {
                    index[pairKey(match.h, match.a), default: []].append(match.meeting)
                }
            }
        }
        return index
    }
}
