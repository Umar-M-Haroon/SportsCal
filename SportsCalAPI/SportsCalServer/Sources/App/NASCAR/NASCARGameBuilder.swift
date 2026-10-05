//
//  NASCARGameBuilder.swift
//
//  Turns NASCAR's feeds into the app's `Game`: one game per race weekend, with
//  practice, qualifying and the race as `EventSession`s (the same shape F1 uses), and
//  stock-car detail on each leaderboard row. Pure — no I/O — so it is unit tested
//  against recorded feeds.
//

import Foundation
import SportsCalModel

enum NASCARGameBuilder {
    static let league = Leagues.nascarCup

    /// Event IDs are namespaced: NASCAR race IDs are small integers that could collide
    /// with another source's.
    static func eventID(raceID: Int) -> String { "nascar-\(raceID)" }

    static func raceID(fromEventID id: String) -> Int? {
        guard id.hasPrefix("nascar-") else { return nil }
        return Int(id.dropFirst("nascar-".count))
    }

    /// How long after its last update a practice or qualifying feed still counts as live.
    /// Races don't use this: a red flag can freeze the feed for longer.
    static let sessionFreshness: TimeInterval = 5 * 60
    /// A race that started this long ago is over, whatever the feed says.
    static let raceMaxDuration: TimeInterval = 8 * 60 * 60

    // MARK: - Game

    /// How much of each leaderboard a game carries. Every current client downloads every
    /// NASCAR game in `/schedules` (the series is filtered on the device), and full boards
    /// for every session of two seasons came to 2.7MB. The race page fetches the full
    /// sessions from `/racing/nascar/race`.
    enum Detail {
        /// Everything (the race endpoint, tests).
        case full
        /// A weekend in progress: the whole running order, top ten elsewhere.
        case live
        /// Schedule rows: enough for list rows and the session strip.
        case compact

        var raceRows: Int {
            switch self {
            case .full, .live: .max
            case .compact: 15
            }
        }

        var sessionRows: Int {
            switch self {
            case .full: .max
            case .live: 10
            case .compact: 3
            }
        }
    }

    /// - Parameters:
    ///   - race: the race from `race_list_basic` (always available).
    ///   - weekend: its weekend feed, when fetched — session results, stages, cautions.
    ///   - live: the current live feed; ignored unless it is this race's.
    static func game(race listRace: NASCARRace, weekend: NASCARWeekendFeed?, live: NASCARLiveFeed?, now: Date = Date(), detail: Detail = .full) -> Game {
        let race = weekend?.race ?? listRace
        let schedule = (race.schedule?.isEmpty == false ? race.schedule : listRace.schedule) ?? []
        let raceStart = raceStartDate(race: race, schedule: schedule)

        let live = live.flatMap { feed in
            isLive(feed, for: race.raceID, raceStart: raceStart, now: now) ? feed : nil
        }

        let teams = teamsByCar(race.results)
        let officialResults = finalResults(race.results)
        let liveFinished = live.map { $0.runType == 3 && NASCARVocabulary.flag($0.flagState) == .checkered && $0.lapNumber >= $0.lapsInRace } ?? false
        // Past the race window counts as over even without results (a rainout, or a
        // weekend feed we couldn't fetch) so a race can never sit "upcoming" forever.
        let raceFinal = officialResults != nil || liveFinished
            || (raceStart.map { now.timeIntervalSince($0) > raceMaxDuration } ?? false)

        var sessions = practiceAndQualifying(schedule: schedule, runs: weekend?.weekendRuns ?? [], now: now)

        // The race itself.
        let raceLeaderboard: [LeaderboardEntry]
        let raceStatus: String
        if let live, live.runType == 3 {
            raceLeaderboard = liveLeaderboard(live, teams: teams)
            raceStatus = liveFinished ? "post" : "in"
        } else if let officialResults {
            raceLeaderboard = resultLeaderboard(officialResults)
            raceStatus = "post"
        } else {
            raceLeaderboard = startingLineup(race.results)
            raceStatus = raceFinal ? "post" : "pre"
        }
        let raceState = raceState(race: race, live: live?.runType == 3 ? live : nil, final: raceStatus == "post")
        sessions.append(EventSession(
            sessionType: "race",
            sessionName: "Race",
            status: raceStatus,
            progress: raceProgress(status: raceStatus, state: raceState),
            date: raceStart.map(iso),
            leaderboard: raceLeaderboard,
            raceState: raceState
        ))

        // A live practice/qualifying session replaces its scheduled placeholder.
        if let live, live.runType != 3, let (type, name) = NASCARVocabulary.sessionType(runType: live.runType) {
            let board = liveTimedLeaderboard(live, teams: teams)
            let index = sessions.lastIndex { $0.sessionType == type && ($0.startDate ?? .distantFuture) <= now }
                ?? sessions.lastIndex { $0.sessionType == type }
            let session = EventSession(
                sessionType: type, sessionName: index.map { sessions[$0].sessionName } ?? name,
                status: "in", progress: live.runName ?? name,
                date: index.flatMap { sessions[$0].date } ?? iso(now),
                leaderboard: board
            )
            if let index { sessions[index] = session } else { sessions.append(session) }
        }
        sessions.sort { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        // Same pick as F1: a live session, else the most important finished one, else the race.
        let primary = sessions.first { $0.status == "in" }
            ?? sessions.filter { $0.status == "post" && !$0.leaderboard.isEmpty }.max { $0.importance < $1.importance }
            ?? sessions.last
        let status: String = sessions.contains { $0.status == "in" } ? "in" : (raceStatus == "post" ? "post" : "pre")
        let leader = primary?.leaderboard.first
        let trimmed = sessions.map { trim($0, to: $0.sessionType == "race" ? detail.raceRows : detail.sessionRows) }
        let progress: String? = switch status {
        case "in": primary?.sessionType == "race" ? primary?.progress : (primary?.progress ?? primary?.displayName)
        case "post": "Final"
        default: nil
        }

        return Game(
            idLiveScore: eventID(raceID: race.raceID),
            idEvent: eventID(raceID: race.raceID),
            idLeague: "\(league.rawValue)",
            strHomeTeam: race.raceName.trimmingCharacters(in: .whitespaces),
            strAwayTeam: leader?.name ?? "TBD",
            intAwayScore: leader?.score,
            strStatus: status,
            strProgress: progress,
            strTimestamp: raceStart.map(iso),

            isCompleted: status == "post",
            isoDate: raceStart,
            // List rows show three; the sessions hold the rest.
            leaderboardEntries: primary.map { Array($0.leaderboard.prefix(detail == .full ? .max : 3)) },
            sessions: trimmed,
            venueName: race.trackName ?? listRace.trackName,
            season: (race.season ?? listRace.season).map(String.init),
            seasonPhase: (race.playoffRound ?? listRace.playoffRound ?? 0) > 0 ? .postseason : .regular
        )
    }

    // MARK: - Live

    /// Whether `feed` is this race weekend's session and still running.
    static func isLive(_ feed: NASCARLiveFeed, for raceID: Int, raceStart: Date?, now: Date) -> Bool {
        guard feed.seriesID == 1, feed.raceID == raceID else { return false }
        if feed.runType == 3 {
            // The race: live from the green until the official results replace it. A red
            // flag can stall the feed, so freshness doesn't apply — the race window does.
            guard let raceStart else { return true }
            return now >= raceStart.addingTimeInterval(-30 * 60) && now.timeIntervalSince(raceStart) < raceMaxDuration
        }
        guard let updated = feed.timeOfDayOS.flatMap(DateParsers.parse) else { return false }
        return now.timeIntervalSince(updated) < sessionFreshness
    }

    static func liveLeaderboard(_ feed: NASCARLiveFeed, teams: [String: String]) -> [LeaderboardEntry] {
        feed.vehicles.sorted { $0.runningPosition < $1.runningPosition }.map { car in
            let lapsDown = (car.delta ?? 0) < 0 ? Int((-(car.delta ?? 0)).rounded()) : 0
            let gap: String? = if car.runningPosition == 1 {
                nil
            } else if lapsDown > 0 {
                lapsLabel(lapsDown)
            } else if let delta = car.delta, delta > 0 {
                String(format: "+%.3f", delta)
            } else {
                nil
            }
            return LeaderboardEntry(
                name: NASCARVocabulary.cleanDriverName(car.driver.fullName),
                score: "P\(car.runningPosition)",
                position: car.runningPosition,
                constructor: teams[car.vehicleNumber],
                gap: gap,
                stockCar: StockCarDetail(
                    carNumber: car.vehicleNumber,
                    manufacturer: NASCARVocabulary.manufacturer(car.vehicleManufacturer),
                    startPosition: car.startingPosition,
                    lapsCompleted: car.lapsCompleted,
                    lapsLed: car.totalLapsLed,
                    pitStops: car.pitStopCount,
                    bestLapTime: car.bestLapTime.flatMap { $0 > 0 ? $0 : nil },
                    bestLapSpeed: car.bestLapSpeed.flatMap { $0 > 0 ? $0 : nil },
                    status: car.isOnTrack == false ? "Out" : "Running",
                    inPlayoffs: car.driver.isInChase,
                    sponsor: car.sponsorName,
                    lapsDown: lapsDown
                )
            )
        }
    }

    /// Practice/qualifying on the live feed: ordered by best lap.
    static func liveTimedLeaderboard(_ feed: NASCARLiveFeed, teams: [String: String]) -> [LeaderboardEntry] {
        let timed = feed.vehicles.filter { ($0.bestLapTime ?? 0) > 0 }
            .sorted { ($0.bestLapTime ?? .infinity) < ($1.bestLapTime ?? .infinity) }
        let best = timed.first?.bestLapTime
        return timed.enumerated().map { index, car in
            let time = car.bestLapTime ?? 0
            return LeaderboardEntry(
                name: NASCARVocabulary.cleanDriverName(car.driver.fullName),
                score: String(format: "%.3f", time),
                position: index + 1,
                constructor: teams[car.vehicleNumber],
                gap: index == 0 ? nil : best.map { String(format: "+%.3f", time - $0) },
                stockCar: StockCarDetail(
                    carNumber: car.vehicleNumber,
                    manufacturer: NASCARVocabulary.manufacturer(car.vehicleManufacturer),
                    lapsCompleted: car.lapsCompleted,
                    bestLapTime: time,
                    bestLapSpeed: car.bestLapSpeed,
                    inPlayoffs: car.driver.isInChase
                )
            )
        }
    }

    // MARK: - Results

    /// Official results once the race has a classified winner; nil before that (the
    /// weekend feed lists the entry list with every position 0 until then).
    static func finalResults(_ results: [NASCARRaceResult]?) -> [NASCARRaceResult]? {
        guard let results,
              results.contains(where: { $0.finishingPosition == 1 && ($0.lapsCompleted ?? 0) > 0 }) else { return nil }
        return results.filter { $0.finishingPosition > 0 }.sorted { $0.finishingPosition < $1.finishingPosition }
    }

    static func resultLeaderboard(_ results: [NASCARRaceResult]) -> [LeaderboardEntry] {
        results.map { result in
            let status = result.finishingStatus?.trimmingCharacters(in: .whitespaces)
            let running = status.map { $0.isEmpty || $0.caseInsensitiveCompare("Running") == .orderedSame } ?? true
            let gap: String? = if result.finishingPosition == 1 {
                nil
            } else if !running, let status {
                status
            } else if let laps = result.diffLaps, laps > 0 {
                lapsLabel(laps)
            } else if let ms = result.diffTime, ms > 0 {
                String(format: "+%.3f", Double(ms) / 1000)
            } else {
                nil
            }
            return LeaderboardEntry(
                name: NASCARVocabulary.cleanDriverName(result.driverFullname),
                score: "P\(result.finishingPosition)",
                position: result.finishingPosition,
                constructor: nonEmpty(result.teamName),
                gap: gap,
                stockCar: StockCarDetail(
                    carNumber: result.carNumber,
                    manufacturer: NASCARVocabulary.manufacturer(result.carMake),
                    startPosition: result.startingPosition.flatMap { $0 > 0 ? $0 : nil },
                    lapsCompleted: result.lapsCompleted,
                    lapsLed: result.lapsLed,
                    status: nonEmpty(status) ?? "Running",
                    points: result.pointsEarned,
                    playoffPoints: result.playoffPointsEarned,
                    sponsor: nonEmpty(result.sponsor?.trimmingCharacters(in: .whitespaces)),
                    lapsDown: result.diffLaps
                )
            )
        }
    }

    /// The grid, once qualifying has set it; empty before.
    static func startingLineup(_ results: [NASCARRaceResult]?) -> [LeaderboardEntry] {
        guard let results else { return [] }
        return results.filter { ($0.startingPosition ?? 0) > 0 }
            .sorted { ($0.startingPosition ?? 0) < ($1.startingPosition ?? 0) }
            .map { result in
                let start = result.startingPosition ?? 0
                return LeaderboardEntry(
                    name: NASCARVocabulary.cleanDriverName(result.driverFullname),
                    score: "P\(start)",
                    position: start,
                    constructor: nonEmpty(result.teamName),
                    stockCar: StockCarDetail(
                        carNumber: result.carNumber,
                        manufacturer: NASCARVocabulary.manufacturer(result.carMake),
                        startPosition: start,
                        sponsor: nonEmpty(result.sponsor?.trimmingCharacters(in: .whitespaces))
                    )
                )
            }
    }

    // MARK: - Sessions

    /// Practice and qualifying sessions from the weekend schedule, filled with results
    /// from the weekend feed's runs (matched by type, in order). Runs the schedule doesn't
    /// list (a second qualifying round) are added on their own.
    static func practiceAndQualifying(schedule: [NASCARScheduleEntry], runs: [NASCARWeekendRun], now: Date) -> [EventSession] {
        var pending = Dictionary(grouping: runs.filter { $0.runType == 1 || $0.runType == 2 }, by: \.runType)
            .mapValues { $0.sorted { ($0.runDateUTC ?? "") < ($1.runDateUTC ?? "") } }
        let scheduled = schedule.filter { $0.runType == 1 || $0.runType == 2 }
            .sorted { ($0.startTimeUTC ?? "") < ($1.startTimeUTC ?? "") }
        let counts = Dictionary(grouping: scheduled, by: \.runType).mapValues(\.count)
        var seen: [Int: Int] = [:]

        var sessions: [EventSession] = []
        for entry in scheduled {
            guard let (type, baseName) = NASCARVocabulary.sessionType(runType: entry.runType) else { continue }
            seen[entry.runType, default: 0] += 1
            let name = (counts[entry.runType] ?? 0) > 1 ? "\(baseName) \(seen[entry.runType]!)" : baseName
            let start = entry.startTimeUTC.flatMap(utcDate)
            let run = pending[entry.runType]?.isEmpty == false ? pending[entry.runType]!.removeFirst() : nil
            sessions.append(session(type: type, name: name, start: start, run: run, canceled: entry.isCanceled, now: now))
        }
        for (runType, leftover) in pending {
            guard let (type, baseName) = NASCARVocabulary.sessionType(runType: runType) else { continue }
            for run in leftover where run.hasTimes {
                sessions.append(session(type: type, name: run.runName ?? baseName,
                                        start: run.runDateUTC.flatMap(utcDate), run: run, canceled: false, now: now))
            }
        }
        return sessions
    }

    private static func session(type: String, name: String, start: Date?, run: NASCARWeekendRun?, canceled: Bool, now: Date) -> EventSession {
        let board = run.map(timedLeaderboard) ?? []
        let status: String
        let progress: String?
        if canceled {
            status = "post"; progress = "Canceled"
        } else if !board.isEmpty {
            status = "post"; progress = "Final"
        } else if let start, now.timeIntervalSince(start) > 2 * 60 * 60 {
            status = "post"; progress = nil
        } else {
            status = "pre"; progress = nil
        }
        return EventSession(sessionType: type, sessionName: name, status: status, progress: progress,
                            date: start.map(iso), leaderboard: board)
    }

    static func timedLeaderboard(_ run: NASCARWeekendRun) -> [LeaderboardEntry] {
        guard run.hasTimes else { return [] }
        return run.results.filter { $0.finishingPosition > 0 }
            .sorted { $0.finishingPosition < $1.finishingPosition }
            .map { result in
                let time = result.bestLapTime ?? 0
                let delta = result.deltaLeader ?? 0
                return LeaderboardEntry(
                    name: NASCARVocabulary.cleanDriverName(result.driverName),
                    score: time > 0 ? String(format: "%.3f", time) : "—",
                    position: result.finishingPosition,
                    gap: result.finishingPosition == 1 || delta <= 0 ? nil : String(format: "+%.3f", delta),
                    stockCar: StockCarDetail(
                        carNumber: result.carNumber,
                        manufacturer: NASCARVocabulary.manufacturer(result.manufacturer),
                        lapsCompleted: result.lapsCompleted,
                        bestLapTime: time > 0 ? time : nil,
                        bestLapSpeed: result.bestLapSpeed.flatMap { $0 > 0 ? $0 : nil }
                    )
                )
            }
    }

    // MARK: - Race state

    static func raceState(race: NASCARRace, live: NASCARLiveFeed?, final: Bool) -> RaceState {
        let stageEnds = race.stageEndLaps
        let total = live?.lapsInRace ?? race.scheduledLaps ?? 0
        if let live {
            return RaceState(
                lap: live.lapNumber, totalLaps: total,
                flag: NASCARVocabulary.flag(live.flagState),
                stage: live.stage?.stageNum, stageEndLap: live.stage?.finishAtLap,
                cautions: live.numberOfCautionSegments, cautionLaps: live.numberOfCautionLaps,
                leadChanges: live.numberOfLeadChanges, leaders: live.numberOfLeaders,
                stageEndLaps: stageEnds.isEmpty ? nil : stageEnds,
                distanceMiles: race.scheduledDistance, broadcast: nonEmpty(race.televisionBroadcaster)
            )
        }
        let laps = final ? (race.actualLaps ?? total) : 0
        return RaceState(
            lap: laps, totalLaps: max(total, laps),
            flag: final ? .checkered : .none,
            cautions: final ? race.numberOfCautions : nil, cautionLaps: final ? race.numberOfCautionLaps : nil,
            leadChanges: final ? race.numberOfLeadChanges : nil, leaders: final ? race.numberOfLeaders : nil,
            stageEndLaps: stageEnds.isEmpty ? nil : stageEnds,
            distanceMiles: race.scheduledDistance, broadcast: nonEmpty(race.televisionBroadcaster)
        )
    }

    /// "Lap 135/267 · Stage 2", "Caution · Lap 92/267", "Final".
    static func raceProgress(status: String, state: RaceState) -> String? {
        switch status {
        case "post": return "Final"
        case "in":
            var parts: [String] = []
            switch state.flag {
            case .yellow: parts.append("Caution")
            case .red: parts.append("Red Flag")
            case .white: parts.append("White Flag")
            default: break
            }
            parts.append(state.lap > 0 ? state.lapLabel : "Starting")
            if let stage = state.stage, state.flag != .yellow, state.flag != .red,
               let ends = state.stageEndLaps, ends.count > 1, stage <= ends.count {
                parts.append(stage == ends.count ? "Final Stage" : "Stage \(stage)")
            }
            return parts.joined(separator: " · ")
        default: return nil
        }
    }

    // MARK: - Standings / detail

    static func standings(_ rows: [NASCARPointsRow], season: Int) -> NASCARStandings {
        let entries = rows.sorted { $0.position < $1.position }.map { row in
            NASCARStandingsEntry(
                driverID: row.driverID,
                position: row.position,
                name: NASCARVocabulary.cleanDriverName(row.driverName),
                carNumber: row.carNo ?? "",
                manufacturer: NASCARVocabulary.manufacturer(row.manufacturer),
                points: row.points,
                behindLeader: row.deltaLeader ?? 0,
                aboveCutLine: row.playoffEligible == 1 ? row.deltaPlayoff : nil,
                inPlayoffs: row.playoffEligible == 1,
                wins: row.wins ?? 0,
                top5: row.top5 ?? 0,
                top10: row.top10 ?? 0,
                poles: row.poles ?? 0,
                stageWins: (row.stage1Wins ?? 0) + (row.stage2Wins ?? 0) + (row.stage3Wins ?? 0),
                lapsLed: row.lapsLed ?? 0,
                starts: row.starts ?? 0,
                dnf: row.dnf ?? 0,
                movement: row.posGL ?? 0
            )
        }
        let spots = entries.filter(\.inPlayoffs).count
        return NASCARStandings(season: season, drivers: entries, playoffSpots: spots > 0 ? spots : 16)
    }

    static func raceDetail(
        raceID: Int,
        weekend: NASCARWeekendFeed?,
        lapTimes: NASCARLapTimesFeed?,
        notes: NASCARLapNotesFeed?,
        pits: [NASCARPitRecord]?
    ) -> NASCARRaceDetail {
        let race = weekend?.race
        let lapPositions = (lapTimes?.laps ?? []).map { car -> NASCARLapPositions in
            let maxLap = car.laps.map(\.lap).max() ?? 0
            var positions = Array(repeating: 0, count: maxLap + 1)
            for lap in car.laps where lap.lap >= 0 && lap.lap <= maxLap {
                positions[lap.lap] = lap.runningPos ?? 0
            }
            return NASCARLapPositions(
                carNumber: car.number,
                driver: NASCARVocabulary.cleanDriverName(car.fullName),
                manufacturer: NASCARVocabulary.manufacturer(car.manufacturer),
                positions: positions
            )
        }
        let lapNotes = (notes?.laps ?? [:]).flatMap { key, notes in
            notes.map { NASCARLapNote(lap: Int(key) ?? 0, note: $0.note, flag: NASCARVocabulary.flag($0.flagState)) }
        }.sorted { $0.lap < $1.lap }
        let stages = (race?.stageResults ?? []).map { stage in
            NASCARStageResult(stage: stage.stageNumber, finishers: stage.results
                .sorted { $0.finishingPosition < $1.finishingPosition }
                .map { .init(position: $0.finishingPosition, driver: NASCARVocabulary.cleanDriverName($0.driverFullname),
                             carNumber: $0.carNumber, points: $0.stagePoints ?? 0) })
        }.sorted { $0.stage < $1.stage }
        let cautions = (race?.cautionSegments ?? []).map {
            NASCARCaution(startLap: $0.startLap, endLap: $0.endLap,
                          reason: nonEmpty($0.comment) ?? nonEmpty($0.reason) ?? "Caution",
                          freePassCar: nonEmpty($0.beneficiaryCarNumber?.trimmingCharacters(in: .whitespaces)))
        }
        // Lap 0 is the pace laps behind the pole sitter, not a lead.
        let leaders = (race?.raceLeaders ?? []).filter { $0.endLap > 0 }.map {
            NASCARLeadStint(carNumber: $0.carNumber, startLap: max($0.startLap, 1), endLap: $0.endLap)
        }
        let pitStops = (pits ?? []).filter { $0.lapCount > 0 }.map { pit in
            NASCARPitStop(
                carNumber: pit.vehicleNumber,
                driver: NASCARVocabulary.cleanDriverName(pit.driverName),
                lap: pit.lapCount,
                stopDuration: pit.pitStopDuration.flatMap { $0 > 0 ? $0 : nil },
                totalDuration: pit.totalDuration.flatMap { $0 > 0 ? $0 : nil },
                tires: pit.tiresChanged,
                positionChange: pit.positionsGainedLost
            )
        }.sorted { ($0.lap, $0.carNumber) < ($1.lap, $1.carNumber) }
        return NASCARRaceDetail(raceID: raceID, lapPositions: lapPositions, notes: lapNotes, stages: stages,
                                cautions: cautions, leaders: leaders, pitStops: pitStops)
    }

    // MARK: - Helpers

    static func raceStartDate(race: NASCARRace, schedule: [NASCARScheduleEntry]) -> Date? {
        if let utc = schedule.first(where: { $0.runType == 3 })?.startTimeUTC, let date = utcDate(utc) {
            return date
        }
        // `race_date` is Eastern time without a zone.
        return race.raceDate.flatMap { easternFormatter.date(from: $0) }
    }

    static func teamsByCar(_ results: [NASCARRaceResult]?) -> [String: String] {
        var teams: [String: String] = [:]
        for result in results ?? [] {
            if let team = nonEmpty(result.teamName) { teams[result.carNumber] = team }
        }
        return teams
    }

    /// `session` with its leaderboard cut to `rows`. No `lastPlay` string either way: it
    /// only exists for builds that predate structured leaderboards, which never see NASCAR.
    static func trim(_ session: EventSession, to rows: Int) -> EventSession {
        guard session.leaderboard.count > rows else { return session }
        var copy = EventSession(sessionType: session.sessionType, sessionName: session.sessionName, status: session.status,
                                progress: session.progress, date: session.date,
                                leaderboard: Array(session.leaderboard.prefix(rows)))
        copy.raceState = session.raceState
        return copy
    }

    static func lapsLabel(_ laps: Int) -> String {
        laps == 1 ? "+1 Lap" : "+\(laps) Laps"
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func utcDate(_ string: String) -> Date? {
        utcFormatter.date(from: string) ?? DateParsers.parse(string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let easternFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
}
