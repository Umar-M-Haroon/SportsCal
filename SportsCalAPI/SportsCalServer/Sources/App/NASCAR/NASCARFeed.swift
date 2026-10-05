//
//  NASCARFeed.swift
//
//  Decode types for NASCAR's public JSON feeds on cf.nascar.com. They are undocumented,
//  so every field we don't strictly need is optional and decoding never fails on a
//  missing one. Only the fields we read are declared.
//
//  - cacher/{season}/race_list_basic.json         every race of every national series
//  - cacher/{season}/{series}/{race}/weekend-feed.json   per-session results, stages, cautions
//  - live/feeds/live-feed.json                    whatever session is on track right now
//  - cacher/{season}/{series}/racinginsights-points-feed.json   driver standings
//  - cacher/{season}/{series}/{race}/lap-times.json / lap-notes.json
//  - cacher/live/series_{series}/{race}/live-pit-data.json
//

import Foundation

// MARK: - Race list / weekend

struct NASCARRaceListResponse: Decodable {
    let series1: [NASCARRace]?

    enum CodingKeys: String, CodingKey {
        case series1 = "series_1"
    }
}

struct NASCARRace: Codable {
    let raceID: Int
    let seriesID: Int?
    let season: Int?
    let raceName: String
    /// 1 points race, 2 exhibition (Clash, All-Star).
    let raceTypeID: Int?
    let trackName: String?
    /// Eastern time, no zone ("2026-10-04T17:30:00"). Prefer the race entry in `schedule`.
    let raceDate: String?
    let scheduledLaps: Int?
    let actualLaps: Int?
    let scheduledDistance: Double?
    let stage1Laps: Int?
    let stage2Laps: Int?
    let stage3Laps: Int?
    let numberOfCautions: Int?
    let numberOfCautionLaps: Int?
    let numberOfLeadChanges: Int?
    let numberOfLeaders: Int?
    let winnerDriverID: Int?
    let televisionBroadcaster: String?
    let radioBroadcaster: String?
    let playoffRound: Int?
    let schedule: [NASCARScheduleEntry]?
    // weekend-feed only
    let results: [NASCARRaceResult]?
    let stageResults: [NASCARStageResults]?
    let cautionSegments: [NASCARCautionSegment]?
    let raceLeaders: [NASCARRaceLeader]?

    enum CodingKeys: String, CodingKey {
        case raceID = "race_id"
        case seriesID = "series_id"
        case season = "race_season"
        case raceName = "race_name"
        case raceTypeID = "race_type_id"
        case trackName = "track_name"
        case raceDate = "race_date"
        case scheduledLaps = "scheduled_laps"
        case actualLaps = "actual_laps"
        case scheduledDistance = "scheduled_distance"
        case stage1Laps = "stage_1_laps"
        case stage2Laps = "stage_2_laps"
        case stage3Laps = "stage_3_laps"
        case numberOfCautions = "number_of_cautions"
        case numberOfCautionLaps = "number_of_caution_laps"
        case numberOfLeadChanges = "number_of_lead_changes"
        case numberOfLeaders = "number_of_leaders"
        case winnerDriverID = "winner_driver_id"
        case televisionBroadcaster = "television_broadcaster"
        case radioBroadcaster = "radio_broadcaster"
        case playoffRound = "playoff_round"
        case schedule
        case results
        case stageResults = "stage_results"
        case cautionSegments = "caution_segments"
        case raceLeaders = "race_leaders"
    }

    /// Lap counts at which each stage ends ([80, 165, 267]); empty for unstaged races.
    var stageEndLaps: [Int] {
        var ends: [Int] = []
        var total = 0
        for laps in [stage1Laps, stage2Laps, stage3Laps].compactMap({ $0 }) where laps > 0 {
            total += laps
            ends.append(total)
        }
        return ends
    }
}

struct NASCARScheduleEntry: Codable {
    let eventName: String
    let notes: String?
    /// UTC, no zone suffix ("2026-10-04T21:30:00").
    let startTimeUTC: String?
    /// 0 non-track event, 1 practice, 2 qualifying, 3 race.
    let runType: Int

    enum CodingKeys: String, CodingKey {
        case eventName = "event_name"
        case notes
        case startTimeUTC = "start_time_utc"
        case runType = "run_type"
    }

    var isCanceled: Bool {
        notes?.localizedCaseInsensitiveContains("cancel") ?? false
    }
}

struct NASCARRaceResult: Codable {
    let finishingPosition: Int
    let startingPosition: Int?
    let carNumber: String
    let driverFullname: String
    let driverID: Int?
    let teamName: String?
    let carMake: String?
    let sponsor: String?
    let lapsLed: Int?
    let lapsCompleted: Int?
    let pointsEarned: Int?
    let playoffPointsEarned: Int?
    let finishingStatus: String?
    let diffLaps: Int?
    /// Milliseconds behind the winner (565 → 0.565s).
    let diffTime: Int?

    enum CodingKeys: String, CodingKey {
        case finishingPosition = "finishing_position"
        case startingPosition = "starting_position"
        case carNumber = "car_number"
        case driverFullname = "driver_fullname"
        case driverID = "driver_id"
        case teamName = "team_name"
        case carMake = "car_make"
        case sponsor
        case lapsLed = "laps_led"
        case lapsCompleted = "laps_completed"
        case pointsEarned = "points_earned"
        case playoffPointsEarned = "playoff_points_earned"
        case finishingStatus = "finishing_status"
        case diffLaps = "diff_laps"
        case diffTime = "diff_time"
    }
}

struct NASCARStageResults: Codable {
    let stageNumber: Int
    let results: [Entry]

    struct Entry: Codable {
        let driverFullname: String
        let carNumber: String
        let finishingPosition: Int
        let stagePoints: Int?

        enum CodingKeys: String, CodingKey {
            case driverFullname = "driver_fullname"
            case carNumber = "car_number"
            case finishingPosition = "finishing_position"
            case stagePoints = "stage_points"
        }
    }

    enum CodingKeys: String, CodingKey {
        case stageNumber = "stage_number"
        case results
    }
}

struct NASCARCautionSegment: Codable {
    let startLap: Int
    let endLap: Int
    let reason: String?
    let comment: String?
    let beneficiaryCarNumber: String?

    enum CodingKeys: String, CodingKey {
        case startLap = "start_lap"
        case endLap = "end_lap"
        case reason, comment
        case beneficiaryCarNumber = "beneficiary_car_number"
    }
}

struct NASCARRaceLeader: Codable {
    let startLap: Int
    let endLap: Int
    let carNumber: String

    enum CodingKeys: String, CodingKey {
        case startLap = "start_lap"
        case endLap = "end_lap"
        case carNumber = "car_number"
    }
}

struct NASCARWeekendFeed: Decodable {
    /// Null for a few races (seen on exhibition events) — treated as no feed.
    let weekendRace: [NASCARRace]?
    let weekendRuns: [NASCARWeekendRun]?

    enum CodingKeys: String, CodingKey {
        case weekendRace = "weekend_race"
        case weekendRuns = "weekend_runs"
    }

    var race: NASCARRace? { weekendRace?.first }
}

struct NASCARWeekendRun: Decodable {
    let runName: String?
    let runType: Int
    let runDateUTC: String?
    let results: [Result]

    struct Result: Decodable {
        let carNumber: String
        let manufacturer: String?
        let driverName: String
        let finishingPosition: Int
        let bestLapTime: Double?
        let bestLapSpeed: Double?
        let lapsCompleted: Int?
        let deltaLeader: Double?

        enum CodingKeys: String, CodingKey {
            case carNumber = "car_number"
            case manufacturer
            case driverName = "driver_name"
            case finishingPosition = "finishing_position"
            case bestLapTime = "best_lap_time"
            case bestLapSpeed = "best_lap_speed"
            case lapsCompleted = "laps_completed"
            case deltaLeader = "delta_leader"
        }
    }

    enum CodingKeys: String, CodingKey {
        case runName = "run_name"
        case runType = "run_type"
        case runDateUTC = "run_date_utc"
        case results
    }

    /// Whether any car set a time (a canceled session still lists the field, all zeroes).
    var hasTimes: Bool {
        results.contains { ($0.bestLapTime ?? 0) > 0 }
    }
}

// MARK: - Live feed

struct NASCARLiveFeed: Decodable {
    let raceID: Int
    let seriesID: Int
    let runType: Int
    let runName: String?
    let lapNumber: Int
    let lapsInRace: Int
    let flagState: Int?
    /// Wall-clock time of the last update, with offset ("2026-10-04T16:08:25.2002556-07:00").
    let timeOfDayOS: String?
    let numberOfCautionSegments: Int?
    let numberOfCautionLaps: Int?
    let numberOfLeadChanges: Int?
    let numberOfLeaders: Int?
    let stage: Stage?
    let vehicles: [Vehicle]

    struct Stage: Decodable {
        let stageNum: Int?
        let finishAtLap: Int?

        enum CodingKeys: String, CodingKey {
            case stageNum = "stage_num"
            case finishAtLap = "finish_at_lap"
        }
    }

    struct Vehicle: Decodable {
        let vehicleNumber: String
        let vehicleManufacturer: String?
        let driver: Driver
        let runningPosition: Int
        let startingPosition: Int?
        /// Seconds behind the leader when positive; laps down when negative (-1 = one lap).
        let delta: Double?
        let lapsCompleted: Int?
        let lapsLed: [LapsLed]?
        let pitStops: [PitStop]?
        let bestLapTime: Double?
        let bestLapSpeed: Double?
        let sponsorName: String?
        let isOnTrack: Bool?

        struct Driver: Decodable {
            let fullName: String
            let isInChase: Bool?

            enum CodingKeys: String, CodingKey {
                case fullName = "full_name"
                case isInChase = "is_in_chase"
            }
        }

        struct LapsLed: Decodable {
            let startLap: Int
            let endLap: Int

            enum CodingKeys: String, CodingKey {
                case startLap = "start_lap"
                case endLap = "end_lap"
            }
        }

        struct PitStop: Decodable {
            let pitInLapCount: Int?

            enum CodingKeys: String, CodingKey {
                case pitInLapCount = "pit_in_lap_count"
            }
        }

        enum CodingKeys: String, CodingKey {
            case vehicleNumber = "vehicle_number"
            case vehicleManufacturer = "vehicle_manufacturer"
            case driver
            case runningPosition = "running_position"
            case startingPosition = "starting_position"
            case delta
            case lapsCompleted = "laps_completed"
            case lapsLed = "laps_led"
            case pitStops = "pit_stops"
            case bestLapTime = "best_lap_time"
            case bestLapSpeed = "best_lap_speed"
            case sponsorName = "sponsor_name"
            case isOnTrack = "is_on_track"
        }

        var totalLapsLed: Int {
            (lapsLed ?? []).reduce(0) { total, stint in
                // The pole sitter "leads" lap 0 before the green; that isn't a lap led.
                let start = max(stint.startLap, 1)
                return total + max(stint.endLap - start + 1, 0)
            }
        }

        /// Stops made under racing conditions (the feed pads with zeroed entries).
        var pitStopCount: Int {
            (pitStops ?? []).filter { ($0.pitInLapCount ?? 0) > 0 }.count
        }
    }

    enum CodingKeys: String, CodingKey {
        case raceID = "race_id"
        case seriesID = "series_id"
        case runType = "run_type"
        case runName = "run_name"
        case lapNumber = "lap_number"
        case lapsInRace = "laps_in_race"
        case flagState = "flag_state"
        case timeOfDayOS = "time_of_day_os"
        case numberOfCautionSegments = "number_of_caution_segments"
        case numberOfCautionLaps = "number_of_caution_laps"
        case numberOfLeadChanges = "number_of_lead_changes"
        case numberOfLeaders = "number_of_leaders"
        case stage
        case vehicles
    }
}

// MARK: - Points

struct NASCARPointsRow: Decodable {
    let position: Int
    let driverID: Int
    let driverName: String
    let carNo: String?
    let manufacturer: String?
    let points: Int
    let deltaLeader: Int?
    let deltaPlayoff: Int?
    let playoffEligible: Int?
    let wins: Int?
    let top5: Int?
    let top10: Int?
    let poles: Int?
    let stage1Wins: Int?
    let stage2Wins: Int?
    let stage3Wins: Int?
    let lapsLed: Int?
    let starts: Int?
    let dnf: Int?
    let posGL: Int?

    enum CodingKeys: String, CodingKey {
        case position
        case driverID = "driver_id"
        case driverName = "driver_name"
        case carNo = "car_no"
        case manufacturer, points
        case deltaLeader = "delta_leader"
        case deltaPlayoff = "delta_playoff"
        case playoffEligible = "playoff_eligible"
        case wins
        case top5 = "top_5"
        case top10 = "top_10"
        case poles
        case stage1Wins = "stage_1_wins"
        case stage2Wins = "stage_2_wins"
        case stage3Wins = "stage_3_wins"
        case lapsLed = "laps_led"
        case starts, dnf
        case posGL = "pos_gl"
    }
}

// MARK: - Lap times / notes / pit data

struct NASCARLapTimesFeed: Decodable {
    let laps: [Car]

    struct Car: Decodable {
        let number: String
        let fullName: String
        let manufacturer: String?
        let laps: [Lap]

        struct Lap: Decodable {
            let lap: Int
            let runningPos: Int?

            enum CodingKeys: String, CodingKey {
                case lap = "Lap"
                case runningPos = "RunningPos"
            }
        }

        enum CodingKeys: String, CodingKey {
            case number = "Number"
            case fullName = "FullName"
            case manufacturer = "Manufacturer"
            case laps = "Laps"
        }
    }
}

struct NASCARLapNotesFeed: Decodable {
    /// Keyed by lap number as a string.
    let laps: [String: [Note]]

    struct Note: Decodable {
        let flagState: Int?
        let note: String

        enum CodingKeys: String, CodingKey {
            case flagState = "FlagState"
            case note = "Note"
        }
    }
}

struct NASCARPitRecord: Decodable {
    let vehicleNumber: String
    let driverName: String
    let lapCount: Int
    let totalDuration: Double?
    let pitStopDuration: Double?
    let leftFrontTireChanged: Bool?
    let leftRearTireChanged: Bool?
    let rightFrontTireChanged: Bool?
    let rightRearTireChanged: Bool?
    let positionsGainedLost: Int?

    enum CodingKeys: String, CodingKey {
        case vehicleNumber = "vehicle_number"
        case driverName = "driver_name"
        case lapCount = "lap_count"
        case totalDuration = "total_duration"
        case pitStopDuration = "pit_stop_duration"
        case leftFrontTireChanged = "left_front_tire_changed"
        case leftRearTireChanged = "left_rear_tire_changed"
        case rightFrontTireChanged = "right_front_tire_changed"
        case rightRearTireChanged = "right_rear_tire_changed"
        case positionsGainedLost = "positions_gained_lost"
    }

    var tiresChanged: Int {
        [leftFrontTireChanged, leftRearTireChanged, rightFrontTireChanged, rightRearTireChanged]
            .filter { $0 == true }.count
    }
}
