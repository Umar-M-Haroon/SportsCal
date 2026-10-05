//
//  MotorsportGameBuilder.swift
//
//  Games for the series built on TheSportsDB weekends (IndyCar, IMSA, WEC): one game
//  per race weekend, sessions as `EventSession`s, per-car detail on each row — the
//  shape NASCAR games already have, so the app shows them with the same views.
//

import Foundation
import SportsCalModel

enum MotorsportGameBuilder {
    typealias Detail = NASCARGameBuilder.Detail

    /// A weekend counts as live from 30 minutes before its first session until 8 hours
    /// after its last start (endurance races run 24h; their window is widened below).
    static func isActive(_ weekend: IndyCarService.CachedWeekend, now: Date, raceLength: TimeInterval = 8 * 3600) -> Bool {
        let starts = ([weekend.race.start] + weekend.sessions.map(\.start)).compactMap { $0 }
        guard let first = starts.min(), let last = starts.max() else { return false }
        return now >= first.addingTimeInterval(-30 * 60) && now <= last.addingTimeInterval(raceLength)
    }

    /// Sessions TheSportsDB lists for the weekend (no results), each done once past.
    static func scheduledSessions(_ weekend: MotorsportWeekend, now: Date) -> [EventSession] {
        weekend.sessions.map { session in
            EventSession(sessionType: session.type, sessionName: session.name,
                         status: MotorsportWeekends.scheduledStatus(start: session.event.start, now: now),
                         date: session.event.start.map(MotorsportWeekends.iso))
        }
    }

    // MARK: - IndyCar

    static func indyCarGame(
        weekend: MotorsportWeekend, espn: Event?, cars: [IndyCarService.ESPNCar],
        entryList: [IndyCarService.ESPNCar], now: Date, detail: Detail
    ) -> Game {
        let competition = espn?.competitions?.first
        let raceStart = competition.flatMap { DateParsers.parse($0.date) } ?? weekend.race.start
        let state = competition?.status?.type.state
        let raceStatus: String = switch state {
        case "in": "in"
        case "post": "post"
        default: MotorsportWeekends.scheduledStatus(start: raceStart, now: now, length: 6 * 3600) == "post" && espn == nil ? "post" : "pre"
        }

        let entries = entryList.isEmpty ? [:] : Dictionary(entryList.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let leaderboard: [LeaderboardEntry]
        if !cars.isEmpty, raceStatus == "post" {
            leaderboard = cars.map { indyCarEntry($0, name: name(for: $0.id, in: competition), raceFinal: true) }
        } else if raceStatus != "pre" {
            // Live (or final before the detail is fetched): ESPN's order, with car numbers
            // and teams from the season's entry list.
            leaderboard = (competition?.competitors ?? [])
                .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
                .map { competitor in
                    let entry = entries[competitor.id]
                    let position = competitor.order ?? 0
                    return LeaderboardEntry(
                        name: competitor.athlete?.displayName ?? "TBD", score: "P\(position)", position: position,
                        constructor: entry?.team,
                        stockCar: entry.map { StockCarDetail(carNumber: $0.number ?? "", manufacturer: $0.manufacturer) }
                    )
                }
        } else {
            leaderboard = []
        }

        let winnerLaps = cars.first?.lapsCompleted
        let broadcast = competition?.broadcasts?.first?.names.first
        let raceState = RaceState(lap: raceStatus == "post" ? (winnerLaps ?? 0) : 0, totalLaps: winnerLaps ?? 0,
                                  flag: raceStatus == "post" ? .checkered : .none, broadcast: broadcast)
        var sessions = scheduledSessions(weekend, now: now)
        sessions.append(EventSession(
            sessionType: "race", sessionName: "Race", status: raceStatus,
            progress: raceStatus == "post" ? "Final" : (raceStatus == "in" ? competition?.status?.type.shortDetail : nil),
            date: raceStart.map(MotorsportWeekends.iso),
            leaderboard: leaderboard, raceState: raceState
        ))
        return game(weekend: weekend, league: .indycar, idPrefix: "indycar", sessions: sessions, raceStart: raceStart, detail: detail)
    }

    static func indyCarEntry(_ car: IndyCarService.ESPNCar, name: String, raceFinal: Bool) -> LeaderboardEntry {
        let lapsDown = car.lapsBehind ?? 0
        let gap: String? = if car.order == 1 {
            nil
        } else if lapsDown > 0 {
            NASCARGameBuilder.lapsLabel(lapsDown)
        } else if let time = car.behindTime, let seconds = Double(time), seconds > 0 {
            String(format: "+%.3f", seconds)
        } else {
            nil
        }
        return LeaderboardEntry(
            name: name, score: "P\(car.order)", position: car.order, constructor: car.team, gap: gap,
            stockCar: StockCarDetail(
                carNumber: car.number ?? "", manufacturer: car.manufacturer,
                startPosition: car.startOrder.flatMap { $0 > 0 ? $0 : nil },
                lapsCompleted: car.lapsCompleted, lapsLed: car.lapsLed, pitStops: car.pits,
                points: raceFinal ? car.points : nil, sponsor: car.sponsor, lapsDown: lapsDown
            )
        )
    }

    private static func name(for id: String, in competition: Competition?) -> String {
        competition?.competitors?.first { $0.id == id }?.athlete?.displayName ?? "Car"
    }

    // MARK: - Shared

    /// The weekend's game from its sessions, picking the headline session the way F1
    /// and NASCAR do: a live one, else the most important finished one, else the race.
    static func game(weekend: MotorsportWeekend, league: Leagues, idPrefix: String, sessions: [EventSession],
                     raceStart: Date?, detail: Detail, timeRemaining: String? = nil) -> Game {
        let sorted = sessions.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        let primary = sorted.first { $0.status == "in" }
            ?? sorted.filter { $0.status == "post" && !$0.leaderboard.isEmpty }.max { $0.importance < $1.importance }
            ?? sorted.last
        let race = sorted.last { $0.sessionType == "race" }
        let status = sorted.contains { $0.status == "in" } ? "in" : (race?.status == "post" ? "post" : "pre")
        let leader = primary?.leaderboard.first
        let progress: String? = switch status {
        case "in": primary?.progress ?? primary?.displayName
        case "post": "Final"
        default: nil
        }
        let trimmed = sorted.map { NASCARGameBuilder.trim($0, to: $0.sessionType == "race" ? detail.raceRows : detail.sessionRows) }
        return Game(
            idLiveScore: "\(idPrefix)-\(weekend.race.idEvent)",
            idEvent: "\(idPrefix)-\(weekend.race.idEvent)",
            idLeague: "\(league.rawValue)",
            strHomeTeam: weekend.race.strEvent.trimmingCharacters(in: .whitespaces),
            strAwayTeam: leader?.name ?? "TBD",
            intAwayScore: leader?.score,
            strStatus: status,
            strProgress: progress,
            strTimestamp: raceStart.map(MotorsportWeekends.iso),
            isCompleted: status == "post",
            isoDate: raceStart,
            leaderboardEntries: primary.map { Array($0.leaderboard.prefix(detail == .full ? .max : 3)) },
            sessions: trimmed,
            venueName: weekend.venue,
            season: raceStart.map { String(Calendar(identifier: .gregorian).component(.year, from: $0)) }
        )
    }

    /// ESPN racing standings with car numbers and makes from the entry list.
    static func standings(_ response: ESPNRacingStandings, entryList: [IndyCarService.ESPNCar]) -> NASCARStandings {
        let rows = response.children?.first?.standings.entries ?? []
        let cars = Dictionary(entryList.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func stat(_ entry: ESPNRacingStandings.Entry, _ name: String) -> Double? {
            entry.stats.first { $0.type == name || $0.name == name }?.value
        }
        let leaderPoints = rows.first.flatMap { Int(stat($0, "points") ?? 0) } ?? 0
        let drivers = rows.enumerated().map { index, entry in
            let points = Int(stat(entry, "points") ?? 0)
            let car = entry.athlete.id.flatMap { cars[$0] }
            return NASCARStandingsEntry(
                driverID: entry.athlete.id.flatMap(Int.init) ?? index, position: Int(stat(entry, "rank") ?? Double(index + 1)),
                name: entry.athlete.displayName, carNumber: car?.number ?? "", manufacturer: car?.manufacturer,
                points: points, behindLeader: points - leaderPoints, inPlayoffs: false,
                wins: 0, top5: 0, top10: 0, poles: 0, stageWins: 0, lapsLed: 0, starts: 0, dnf: 0, movement: 0
            )
        }
        let season = response.seasons?.last?.year
            ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        return NASCARStandings(season: season, drivers: drivers, playoffSpots: 0)
    }
}
