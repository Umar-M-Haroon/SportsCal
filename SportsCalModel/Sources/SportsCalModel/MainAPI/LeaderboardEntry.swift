//
//  LeaderboardEntry.swift
//  SportsCalModel
//
//  Created by Umar Haroon on 2/12/26.
//

import Foundation

// MARK: - LeaderboardEntry
public struct LeaderboardEntry: Codable, Equatable, Hashable {
    public let name: String
    public let score: String
    public let position: Int
    public let headshot: String?
    public let thruHole: String?
    public let rounds: [String]
    public let constructor: String?
    public let gap: String?
    public let isCut: Bool?
    public let movement: Int?
    public let flagURL: String?
    public let flagAlt: String?
    public let teeTime: String?
    public let roundDetails: [GolfRoundDetail]?
    /// Stock-car detail (NASCAR). All optional, so F1/golf/tennis rows and older payloads
    /// decode unchanged; `constructor` holds the race team for these rows.
    public var stockCar: StockCarDetail?

    public init(name: String, score: String, position: Int, headshot: String? = nil, thruHole: String? = nil, rounds: [String] = [], constructor: String? = nil, gap: String? = nil, isCut: Bool? = nil, movement: Int? = nil, flagURL: String? = nil, flagAlt: String? = nil, teeTime: String? = nil, roundDetails: [GolfRoundDetail]? = nil, stockCar: StockCarDetail? = nil) {
        self.name = name
        self.score = score
        self.position = position
        self.headshot = headshot
        self.thruHole = thruHole
        self.rounds = rounds
        self.constructor = constructor
        self.gap = gap
        self.isCut = isCut
        self.movement = movement
        self.flagURL = flagURL
        self.flagAlt = flagAlt
        self.teeTime = teeTime
        self.roundDetails = roundDetails
        self.stockCar = stockCar
    }
}

// MARK: - StockCarDetail
/// Per-car data the car-number series publish (NASCAR, IndyCar, IMSA, WEC) that F1's
/// feed has no equivalent for: car number, manufacturer, laps led, and for endurance
/// racing the class and the driver crew. Named for where it started; every field is
/// optional beyond the car number, so each series fills what it has.
public struct StockCarDetail: Codable, Equatable, Hashable {
    public var carNumber: String
    /// Full manufacturer name: "Chevrolet", "Ford", "Toyota".
    public var manufacturer: String?
    public var startPosition: Int?
    public var lapsCompleted: Int?
    public var lapsLed: Int?
    public var pitStops: Int?
    /// Best lap in seconds, and its speed in mph.
    public var bestLapTime: Double?
    public var bestLapSpeed: Double?
    /// "Running" while on track; otherwise why the car is out ("Accident", "Engine").
    public var status: String?
    /// Points earned in this race (finals only).
    public var points: Int?
    public var playoffPoints: Int?
    /// Still eligible for the championship (the "chase").
    public var inPlayoffs: Bool?
    public var sponsor: String?
    /// Laps down to the leader; 0 on the lead lap.
    public var lapsDown: Int?
    /// Endurance racing: the car's class ("GTP", "LMP2", "GTD PRO", "HYPERCAR", "LMGT3"),
    /// its position within it, its model ("Porsche 963") and the drivers sharing it.
    public var vehicleClass: String?
    public var classPosition: Int?
    public var vehicle: String?
    public var drivers: [String]?

    public init(carNumber: String, manufacturer: String? = nil, startPosition: Int? = nil, lapsCompleted: Int? = nil, lapsLed: Int? = nil, pitStops: Int? = nil, bestLapTime: Double? = nil, bestLapSpeed: Double? = nil, status: String? = nil, points: Int? = nil, playoffPoints: Int? = nil, inPlayoffs: Bool? = nil, sponsor: String? = nil, lapsDown: Int? = nil, vehicleClass: String? = nil, classPosition: Int? = nil, vehicle: String? = nil, drivers: [String]? = nil) {
        self.carNumber = carNumber
        self.manufacturer = manufacturer
        self.startPosition = startPosition
        self.lapsCompleted = lapsCompleted
        self.lapsLed = lapsLed
        self.pitStops = pitStops
        self.bestLapTime = bestLapTime
        self.bestLapSpeed = bestLapSpeed
        self.status = status
        self.points = points
        self.playoffPoints = playoffPoints
        self.inPlayoffs = inPlayoffs
        self.sponsor = sponsor
        self.lapsDown = lapsDown
        self.vehicleClass = vehicleClass
        self.classPosition = classPosition
        self.vehicle = vehicle
        self.drivers = drivers
    }

    /// Places gained (+) or lost (−) from the start.
    public func positionsGained(finishing position: Int) -> Int? {
        guard let start = startPosition, start > 0, position > 0 else { return nil }
        return start - position
    }

    /// Whether the car is out of the race.
    public var isOut: Bool {
        guard let status, !status.isEmpty else { return false }
        return status.caseInsensitiveCompare("Running") != .orderedSame
    }
}

// MARK: - RaceState
/// Where an oval-style race stands: laps, flag, stage, cautions. Carried on the race
/// session of series whose feeds publish it (NASCAR).
public struct RaceState: Codable, Equatable, Hashable {
    public enum Flag: String, Codable, Hashable {
        case green, yellow, red, white, checkered, none
    }

    public var lap: Int
    public var totalLaps: Int
    public var flag: Flag
    /// 1-based stage in progress, and the lap it ends on. Nil outside staged races.
    public var stage: Int?
    public var stageEndLap: Int?
    public var cautions: Int?
    public var cautionLaps: Int?
    public var leadChanges: Int?
    public var leaders: Int?
    /// Lap each stage ends on ([80, 165, 267]); known before the race starts.
    public var stageEndLaps: [Int]?
    public var distanceMiles: Double?
    /// TV network ("USA", "FOX", "Prime Video").
    public var broadcast: String?
    /// Races run to a clock (endurance): its length and what's left, in seconds.
    public var duration: Double?
    public var timeRemaining: Double?

    public init(lap: Int, totalLaps: Int, flag: Flag, stage: Int? = nil, stageEndLap: Int? = nil, cautions: Int? = nil, cautionLaps: Int? = nil, leadChanges: Int? = nil, leaders: Int? = nil, stageEndLaps: [Int]? = nil, distanceMiles: Double? = nil, broadcast: String? = nil, duration: Double? = nil, timeRemaining: Double? = nil) {
        self.lap = lap
        self.totalLaps = totalLaps
        self.flag = flag
        self.stage = stage
        self.stageEndLap = stageEndLap
        self.cautions = cautions
        self.cautionLaps = cautionLaps
        self.leadChanges = leadChanges
        self.leaders = leaders
        self.stageEndLaps = stageEndLaps
        self.distanceMiles = distanceMiles
        self.broadcast = broadcast
        self.duration = duration
        self.timeRemaining = timeRemaining
    }

    /// Timed races have no lap count to run to.
    public var isTimed: Bool { duration != nil }

    /// "4:12:30 left" for a timed race.
    public var timeRemainingLabel: String? {
        guard let timeRemaining, timeRemaining >= 0 else { return nil }
        let seconds = Int(timeRemaining)
        return String(format: "%d:%02d:%02d left", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }

    public var lapsToGo: Int { max(totalLaps - lap, 0) }

    /// "Lap 135/267".
    public var lapLabel: String { "Lap \(lap)/\(totalLaps)" }
}

// MARK: - EventSession
public struct EventSession: Codable, Equatable, Hashable {
    public let sessionType: String
    public let sessionName: String
    public let status: String?
    public let progress: String?
    public let date: String?
    public let leaderboard: [LeaderboardEntry]
    /// Laps/flag/stage for a race in a series that publishes it (NASCAR); nil for F1.
    public var raceState: RaceState?

    public init(sessionType: String, sessionName: String, status: String? = nil, progress: String? = nil, date: String? = nil, leaderboard: [LeaderboardEntry] = [], raceState: RaceState? = nil) {
        self.sessionType = sessionType
        self.sessionName = sessionName
        self.status = status
        self.progress = progress
        self.date = date
        self.leaderboard = leaderboard
        self.raceState = raceState
    }

    /// When the session starts. ESPN sends minute precision ("2026-10-04T07:00Z"),
    /// which `ISO8601DateFormatter` rejects outright — parse through `DateParsers`,
    /// never a bare ISO formatter, or every session date silently comes back nil.
    public var startDate: Date? {
        date.flatMap(DateParsers.parse)
    }

    /// Full human name. ESPN sends sprint sessions as bare "SS"/"SR" codes with
    /// the same code as the name, so derive from the type rather than trusting `sessionName`.
    public var displayName: String {
        switch sessionType.lowercased() {
        case "fp1": "Free Practice 1"
        case "fp2": "Free Practice 2"
        case "fp3": "Free Practice 3"
        case "qual", "qualifying": "Qualifying"
        case "ss", "sq", "sprint qualifying", "sprint shootout": "Sprint Qualifying"
        case "sr", "sprint": "Sprint"
        case "race", "r": "Race"
        default: sessionName.isEmpty ? sessionType : sessionName
        }
    }

    /// Compact label for pills and tabs ("FP1", "Quali", "Sprint Q").
    public var shortName: String {
        switch sessionType.lowercased() {
        case "qual", "qualifying": "Quali"
        case "ss", "sq", "sprint qualifying", "sprint shootout": "Sprint Q"
        case "sr", "sprint": "Sprint"
        case "race", "r": "Race"
        // NASCAR names its own practices ("Practice", "Practice 2").
        case "practice": sessionName
        case "": sessionName.isEmpty ? "?" : sessionName
        default: sessionType
        }
    }

    /// Ranks by how much the session decides the weekend (race > sprint > quali > practice).
    public var importance: Int {
        switch sessionType.lowercased() {
        case "race", "r": 6
        case "sr", "sprint": 5
        case "qual", "qualifying": 4
        case "ss", "sq", "sprint qualifying", "sprint shootout": 3
        case "fp3", "practice": 2
        case "fp2": 1
        default: 0
        }
    }

    /// Practice and qualifying formats are ranked by best lap, not race time.
    public var isTimedLapSession: Bool {
        switch sessionType.lowercased() {
        case "race", "r", "sr", "sprint": false
        default: true
        }
    }
}

public extension Array where Element == EventSession {
    /// The session whose order set `session`'s grid: Qualifying for the Race,
    /// Sprint Qualifying for the Sprint. Nil for practice/qualifying sessions.
    func gridSession(for session: EventSession) -> EventSession? {
        let sourceTypes: Set<String>
        switch session.sessionType.lowercased() {
        case "race", "r": sourceTypes = ["qual", "qualifying"]
        case "sr", "sprint": sourceTypes = ["ss", "sq", "sprint qualifying", "sprint shootout"]
        default: return nil
        }
        return first { sourceTypes.contains($0.sessionType.lowercased()) }
    }

    /// Places gained (+) or lost (−) versus qualifying, keyed by driver name. Approximate
    /// by design: grid penalties and pit-lane starts aren't in the feed, so this is
    /// "vs qualifying", not "vs grid". Empty until qualifying has finished.
    func positionsGainedVsQualifying(in session: EventSession) -> [String: Int] {
        guard let grid = gridSession(for: session), grid.status == "post" else { return [:] }
        let qualifying = Dictionary(
            grid.leaderboard.filter { $0.position > 0 }.map { ($0.name, $0.position) },
            uniquingKeysWith: { first, _ in first }
        )
        var gained: [String: Int] = [:]
        for entry in session.leaderboard where entry.position > 0 {
            if let start = qualifying[entry.name] {
                gained[entry.name] = start - entry.position
            }
        }
        return gained
    }
}
