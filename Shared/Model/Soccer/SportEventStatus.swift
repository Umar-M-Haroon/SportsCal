// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let sportEventStatus = try? newJSONDecoder().decode(SportEventStatus.self, from: jsonData)

import Foundation

// MARK: - SportEventStatus
struct SportEventStatus: Codable {
    let status: SoccerStatus
    let matchStatus: String
    let homeScore, awayScore, homeNormaltimeScore, awayNormaltimeScore: Int?
    let homeOvertimeScore, awayOvertimeScore: Int?
    let winnerID: String?
    let periodScores: [PeriodScore]?
    let matchTie: Bool?
    let aggregateHomeScore, aggregateAwayScore: Int?
    let aggregateWinnerID: String?

    enum CodingKeys: String, CodingKey {
        case status
        case matchStatus = "match_status"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case homeNormaltimeScore = "home_normaltime_score"
        case awayNormaltimeScore = "away_normaltime_score"
        case homeOvertimeScore = "home_overtime_score"
        case awayOvertimeScore = "away_overtime_score"
        case winnerID = "winner_id"
        case periodScores = "period_scores"
        case matchTie = "match_tie"
        case aggregateHomeScore = "aggregate_home_score"
        case aggregateAwayScore = "aggregate_away_score"
        case aggregateWinnerID = "aggregate_winner_id"
    }
}
