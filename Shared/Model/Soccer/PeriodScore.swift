// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let periodScore = try? newJSONDecoder().decode(PeriodScore.self, from: jsonData)

import Foundation

// MARK: - PeriodScore
struct PeriodScore: Codable {
    let homeScore, awayScore: Int
    let type: PeriodScoreType
    let number: Int?

    enum CodingKeys: String, CodingKey {
        case homeScore = "home_score"
        case awayScore = "away_score"
        case type, number
    }
}
