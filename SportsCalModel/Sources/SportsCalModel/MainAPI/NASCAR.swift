//
//  NASCAR.swift
//  SportsCalModel
//
//  Payloads for NASCAR's on-demand endpoints (`/racing/nascar/standings`,
//  `/racing/nascar/race`), plus the small vocabulary helpers both the server and the
//  app need to read NASCAR's feeds consistently.
//

import Foundation

// MARK: - Standings

/// Cup Series driver standings, with the Chase (playoff) picture.
public struct NASCARStandings: Codable, Equatable, Hashable {
    public var season: Int
    public var drivers: [NASCARStandingsEntry]
    /// How many drivers make the Chase; the cut line sits below this position.
    public var playoffSpots: Int

    public init(season: Int, drivers: [NASCARStandingsEntry], playoffSpots: Int = 16) {
        self.season = season
        self.drivers = drivers
        self.playoffSpots = playoffSpots
    }

    /// Whether the Chase field has been set (any driver flagged eligible).
    public var hasPlayoffField: Bool {
        drivers.contains { $0.inPlayoffs }
    }
}

public struct NASCARStandingsEntry: Codable, Equatable, Hashable, Identifiable {
    public var id: Int { driverID }
    public var driverID: Int
    public var position: Int
    public var name: String
    public var carNumber: String
    public var manufacturer: String?
    public var points: Int
    /// Points behind the leader (≤ 0).
    public var behindLeader: Int
    /// Points above (+) or below (−) the Chase cut line.
    public var aboveCutLine: Int?
    public var inPlayoffs: Bool
    public var wins: Int
    public var top5: Int
    public var top10: Int
    public var poles: Int
    public var stageWins: Int
    public var lapsLed: Int
    public var starts: Int
    public var dnf: Int
    /// Places gained (+) or lost (−) since the previous race.
    public var movement: Int

    public init(driverID: Int, position: Int, name: String, carNumber: String, manufacturer: String? = nil, points: Int, behindLeader: Int, aboveCutLine: Int? = nil, inPlayoffs: Bool, wins: Int, top5: Int, top10: Int, poles: Int, stageWins: Int, lapsLed: Int, starts: Int, dnf: Int, movement: Int) {
        self.driverID = driverID
        self.position = position
        self.name = name
        self.carNumber = carNumber
        self.manufacturer = manufacturer
        self.points = points
        self.behindLeader = behindLeader
        self.aboveCutLine = aboveCutLine
        self.inPlayoffs = inPlayoffs
        self.wins = wins
        self.top5 = top5
        self.top10 = top10
        self.poles = poles
        self.stageWins = stageWins
        self.lapsLed = lapsLed
        self.starts = starts
        self.dnf = dnf
        self.movement = movement
    }
}

// MARK: - Race detail

/// Everything about one race that is too heavy for the schedule payload: the lap
/// chart, NASCAR's lap-by-lap notes, stage results, cautions, lead changes and pit stops.
public struct NASCARRaceDetail: Codable, Equatable, Hashable {
    public var raceID: Int
    /// Running position of each car at the end of every lap (index 0 = the start).
    public var lapPositions: [NASCARLapPositions]
    public var notes: [NASCARLapNote]
    public var stages: [NASCARStageResult]
    public var cautions: [NASCARCaution]
    public var leaders: [NASCARLeadStint]
    public var pitStops: [NASCARPitStop]
    /// Every session with its full leaderboard. The schedule's copy of a game is trimmed
    /// (top 15 of a race, top 3 of practice/qualifying) to keep `/schedules` small.
    public var sessions: [EventSession]?

    public init(raceID: Int, lapPositions: [NASCARLapPositions] = [], notes: [NASCARLapNote] = [], stages: [NASCARStageResult] = [], cautions: [NASCARCaution] = [], leaders: [NASCARLeadStint] = [], pitStops: [NASCARPitStop] = [], sessions: [EventSession]? = nil) {
        self.raceID = raceID
        self.lapPositions = lapPositions
        self.notes = notes
        self.stages = stages
        self.cautions = cautions
        self.leaders = leaders
        self.pitStops = pitStops
        self.sessions = sessions
    }

    public var isEmpty: Bool {
        lapPositions.isEmpty && notes.isEmpty && stages.isEmpty && cautions.isEmpty && leaders.isEmpty && pitStops.isEmpty
    }
}

public struct NASCARLapPositions: Codable, Equatable, Hashable {
    public var carNumber: String
    public var driver: String
    public var manufacturer: String?
    /// Position after each lap; 0 where the car has no time for that lap.
    public var positions: [Int]

    public init(carNumber: String, driver: String, manufacturer: String? = nil, positions: [Int]) {
        self.carNumber = carNumber
        self.driver = driver
        self.manufacturer = manufacturer
        self.positions = positions
    }
}

public struct NASCARLapNote: Codable, Equatable, Hashable {
    public var lap: Int
    public var note: String
    public var flag: RaceState.Flag

    public init(lap: Int, note: String, flag: RaceState.Flag) {
        self.lap = lap
        self.note = note
        self.flag = flag
    }
}

public struct NASCARStageResult: Codable, Equatable, Hashable {
    public var stage: Int
    /// Top finishers in stage order, with the stage points each earned.
    public var finishers: [Finisher]

    public struct Finisher: Codable, Equatable, Hashable {
        public var position: Int
        public var driver: String
        public var carNumber: String
        public var points: Int

        public init(position: Int, driver: String, carNumber: String, points: Int) {
            self.position = position
            self.driver = driver
            self.carNumber = carNumber
            self.points = points
        }
    }

    public init(stage: Int, finishers: [Finisher]) {
        self.stage = stage
        self.finishers = finishers
    }
}

public struct NASCARCaution: Codable, Equatable, Hashable {
    public var startLap: Int
    public var endLap: Int
    public var reason: String
    /// The car that got the free pass back onto the lead lap ("lucky dog").
    public var freePassCar: String?

    public init(startLap: Int, endLap: Int, reason: String, freePassCar: String? = nil) {
        self.startLap = startLap
        self.endLap = endLap
        self.reason = reason
        self.freePassCar = freePassCar
    }

    public var laps: Int { max(endLap - startLap + 1, 0) }
}

public struct NASCARLeadStint: Codable, Equatable, Hashable {
    public var carNumber: String
    public var startLap: Int
    public var endLap: Int

    public init(carNumber: String, startLap: Int, endLap: Int) {
        self.carNumber = carNumber
        self.startLap = startLap
        self.endLap = endLap
    }

    public var laps: Int { max(endLap - startLap + 1, 0) }
}

public struct NASCARPitStop: Codable, Equatable, Hashable {
    public var carNumber: String
    public var driver: String
    public var lap: Int
    /// Time stationary in the box, in seconds, when timed.
    public var stopDuration: Double?
    /// Pit road entry to exit, in seconds.
    public var totalDuration: Double?
    /// Tires changed: 0, 2 or 4.
    public var tires: Int
    /// Places gained (+) or lost (−) through the stop.
    public var positionChange: Int?

    public init(carNumber: String, driver: String, lap: Int, stopDuration: Double? = nil, totalDuration: Double? = nil, tires: Int, positionChange: Int? = nil) {
        self.carNumber = carNumber
        self.driver = driver
        self.lap = lap
        self.stopDuration = stopDuration
        self.totalDuration = totalDuration
        self.tires = tires
        self.positionChange = positionChange
    }
}

// MARK: - Vocabulary

public enum NASCARVocabulary {
    /// NASCAR's live feed abbreviates makes ("Chv", "Frd", "Tyt"); results spell them out.
    public static func manufacturer(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "chv", "chevy", "chevrolet": return "Chevrolet"
        case "frd", "ford": return "Ford"
        case "tyt", "toy", "toyota": return "Toyota"
        case "dge", "dodge": return "Dodge"
        default: return raw
        }
    }

    /// Brand colour per manufacturer, hex without "#".
    public static func manufacturerColorHex(_ manufacturer: String?) -> String? {
        switch manufacturer?.lowercased() {
        case "chevrolet": "D4A017"
        case "ford": "1F5AA6"
        case "toyota": "EB0A1E"
        case "dodge": "BA0C2F"
        default: nil
        }
    }

    /// Strips the markers NASCAR appends to names in its live and results feeds:
    /// "(C)" in the Chase, "(i)" ineligible for points, "#" rookie, "(P)" playoff,
    /// "*" for some substitutes.
    public static func cleanDriverName(_ raw: String) -> String {
        var name = raw
        for marker in ["(C)", "(c)", "(i)", "(I)", "(P)", "(p)", "#", "*"] {
            name = name.replacingOccurrences(of: marker, with: "")
        }
        return name
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// NASCAR `flag_state` codes. 1/2/4/8 are confirmed against finished races (the last
    /// lap of a race is 4, the pre-race lap 0 is 8); 3 and 5 follow NASCAR's scheme.
    public static func flag(_ state: Int?) -> RaceState.Flag {
        switch state {
        case 1: .green
        case 2: .yellow
        case 3: .red
        case 4: .checkered
        case 5: .white
        default: .none
        }
    }

    /// NASCAR `run_type`: 1 practice, 2 qualifying, 3 race.
    public static func sessionType(runType: Int) -> (type: String, name: String)? {
        switch runType {
        case 1: ("practice", "Practice")
        case 2: ("qual", "Qualifying")
        case 3: ("race", "Race")
        default: nil
        }
    }
}
