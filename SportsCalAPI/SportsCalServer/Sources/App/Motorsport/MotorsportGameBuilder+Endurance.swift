//
//  MotorsportGameBuilder+Endurance.swift
//
//  IMSA and WEC weekends: TheSportsDB's schedule with Al Kamel's classifications.
//  Several classes race at once, each car shared by a crew of drivers, to a clock.
//

import Foundation
import SportsCalModel

extension MotorsportGameBuilder {
    static func enduranceGame(series: AlKamelSeries, weekend: MotorsportWeekend, sessions: [AlKamelSession],
                              now: Date, detail: Detail) -> Game {
        let akRace = sessions.last { $0.type == "race" }
        // Al Kamel names folders in local track time; TheSportsDB's race time (when it
        // has one) gives the offset to UTC.
        let offset = utcOffset(series: series, tsdbRace: weekend.race.start, localRace: akRace?.localStart)
        func utc(_ local: Date?) -> Date? { local.map { $0.addingTimeInterval(-offset) } }
        let tsdbStart = weekend.race.start.flatMap { isMidnight($0) ? nil : $0 }
        let raceStart = tsdbStart ?? utc(akRace?.localStart) ?? weekend.race.start

        var result: [EventSession] = []
        var used = Set<String>()
        // TheSportsDB's sessions (WEC lists them), with Al Kamel's results where the names agree.
        for scheduled in weekend.sessions {
            let match = sessions.first { $0.type != "race" && !used.contains($0.folder)
                && MotorsportWeekends.normalized($0.name) == MotorsportWeekends.normalized(scheduled.name) }
            if let match {
                used.insert(match.folder)
                result.append(session(match, name: scheduled.name, date: scheduled.event.start ?? utc(match.localStart)))
            } else {
                result.append(EventSession(sessionType: scheduled.type, sessionName: scheduled.name,
                                           status: MotorsportWeekends.scheduledStatus(start: scheduled.event.start, now: now),
                                           date: scheduled.event.start.map(MotorsportWeekends.iso)))
            }
        }
        // Sessions only Al Kamel knows about (IMSA lists no sessions on TheSportsDB).
        for extra in sessions where extra.type != "race" && !used.contains(extra.folder) {
            result.append(session(extra, name: extra.name, date: utc(extra.localStart)))
        }

        let duration = akRace?.duration ?? weekendDuration(weekend.race.strEvent)
        let raceStatus: String
        if akRace?.isFinal == true {
            raceStatus = "post"
        } else if akRace != nil {
            raceStatus = "in"
        } else if let raceStart, now >= raceStart {
            raceStatus = now.timeIntervalSince(raceStart) > (duration ?? 6 * 3600) + 3 * 3600 ? "post" : "in"
        } else {
            raceStatus = "pre"
        }
        let hour = akRace?.hour
        let progress: String? = switch raceStatus {
        case "post": "Final"
        case "in": hour.map { h in duration.map { "Hour \(h) of \(Int($0 / 3600))" } ?? "Hour \(h)" } ?? "Race"
        default: nil
        }
        let entries = akRace.map { enduranceEntries($0.entries, isRace: true) } ?? []
        let raceState = RaceState(
            lap: akRace?.entries.first?.laps ?? 0, totalLaps: 0,
            flag: raceStatus == "post" ? .checkered : .none,
            duration: duration,
            timeRemaining: raceStatus == "in" ? hour.flatMap { h in duration.map { max($0 - Double(h) * 3600, 0) } } : nil
        )
        result.append(EventSession(sessionType: "race", sessionName: "Race", status: raceStatus, progress: progress,
                                   date: raceStart.map(MotorsportWeekends.iso), leaderboard: entries, raceState: raceState))
        return game(weekend: weekend, league: series.league, idPrefix: series.rawValue, sessions: result,
                    raceStart: raceStart, detail: detail)
    }

    private static func session(_ session: AlKamelSession, name: String, date: Date?) -> EventSession {
        EventSession(sessionType: session.type, sessionName: name, status: "post", progress: "Final",
                     date: date.map(MotorsportWeekends.iso), leaderboard: enduranceEntries(session.entries, isRace: false))
    }

    /// Rows in overall order, with each car's place in its class.
    static func enduranceEntries(_ entries: [AlKamelEntry], isRace: Bool) -> [LeaderboardEntry] {
        var classCounts: [String: Int] = [:]
        return entries.map { entry in
            let cls = entry.vehicleClass ?? ""
            classCounts[cls, default: 0] += 1
            let surnames = entry.drivers.map { $0.split(separator: " ").last.map(String.init) ?? $0 }
            let gap: String? = entry.position == 1 ? nil : (isRace && entry.retired ? "Retired" : entry.gapFirst)
            return LeaderboardEntry(
                name: surnames.isEmpty ? "#\(entry.number)" : surnames.joined(separator: " / "),
                score: isRace ? "P\(entry.position)" : (entry.time ?? entry.bestLap ?? "—"),
                position: entry.position,
                constructor: entry.team,
                gap: gap,
                stockCar: StockCarDetail(
                    carNumber: entry.number, manufacturer: entry.manufacturer, lapsCompleted: entry.laps,
                    pitStops: entry.pitStops, status: entry.retired ? "Retired" : "Running",
                    vehicleClass: entry.vehicleClass, classPosition: classCounts[cls], vehicle: entry.vehicle,
                    drivers: entry.drivers
                )
            )
        }
    }

    /// Local minus UTC for the event, rounded to 15 minutes.
    static func utcOffset(series: AlKamelSeries, tsdbRace: Date?, localRace: Date?) -> TimeInterval {
        if let tsdbRace, let localRace, !isMidnight(tsdbRace) {
            let raw = localRace.timeIntervalSince(tsdbRace)
            let rounded = (raw / 900).rounded() * 900
            if abs(rounded) <= 14 * 3600 { return rounded }
        }
        return TimeInterval(series.fallbackTimeZone.secondsFromGMT(for: localRace ?? Date()))
    }

    static func isMidnight(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour == 0 && parts.minute == 0
    }

    /// "6 Hours of Spa", "Rolex 24", "Twelve Hours of Sebring", "Petit Le Mans" → seconds.
    static func weekendDuration(_ name: String) -> Double? {
        let lowered = name.lowercased()
        if lowered.contains("petit le mans") { return 10 * 3600 }
        if lowered.contains("24") || lowered.contains("le mans") { return 24 * 3600 }
        if let match = lowered.range(of: #"(\d+)\s*hours?"#, options: .regularExpression),
           let hours = Double(lowered[match].filter(\.isNumber)) { return hours * 3600 }
        for (word, hours) in ["six": 6.0, "ten": 10, "twelve": 12, "eight": 8] where lowered.contains("\(word) hours") {
            return hours * 3600
        }
        return nil
    }
}
