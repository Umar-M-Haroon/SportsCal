// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let result = try? newJSONDecoder().decode(Result.self, from: jsonData)

import Foundation

// MARK: - Result
struct Result: Codable {
    let points: Double?
    let carNumber: Int?
    let position: Int
    let victories: Int?
    let races: Int
    let racesWithPoints, polepositions, podiums, fastestLaps: Int?
    let victoryPoleAndFastestLap: Int?

    enum CodingKeys: String, CodingKey {
        case points
        case carNumber = "car_number"
        case position, victories, races
        case racesWithPoints = "races_with_points"
        case polepositions, podiums
        case fastestLaps = "fastest_laps"
        case victoryPoleAndFastestLap = "victory_pole_and_fastest_lap"
    }
}
