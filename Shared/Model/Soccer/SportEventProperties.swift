// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let sportEventProperties = try? newJSONDecoder().decode(SportEventProperties.self, from: jsonData)

import Foundation

// MARK: - SportEventProperties
struct SportEventProperties: Codable {
    let lineups, extendedPlayerStats, extendedTeamStats: Bool?
    let lineupsAvailability: LineupsAvailability?
    let ballspotting, commentary, funFacts, goalScorers: Bool?
    let scores: String?
    let gameClock, deeperPlayByPlay, deeperPlayerStats, deeperTeamStats: Bool?
    let basicPlayByPlay, basicPlayerStats, basicTeamStats: Bool?

    enum CodingKeys: String, CodingKey {
        case lineups
        case extendedPlayerStats = "extended_player_stats"
        case extendedTeamStats = "extended_team_stats"
        case lineupsAvailability = "lineups_availability"
        case ballspotting, commentary
        case funFacts = "fun_facts"
        case goalScorers = "goal_scorers"
        case scores
        case gameClock = "game_clock"
        case deeperPlayByPlay = "deeper_play_by_play"
        case deeperPlayerStats = "deeper_player_stats"
        case deeperTeamStats = "deeper_team_stats"
        case basicPlayByPlay = "basic_play_by_play"
        case basicPlayerStats = "basic_player_stats"
        case basicTeamStats = "basic_team_stats"
    }
}
