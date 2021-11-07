// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let round = try? newJSONDecoder().decode(Round.self, from: jsonData)

import Foundation

// MARK: - Round
struct Round: Codable {
    let number: Int?
    let name: String?
    let cupRoundSportEventNumber, cupRoundNumberOfSportEvents: Int?
    let cupRoundID, otherSportEventID: String?

    enum CodingKeys: String, CodingKey {
        case number, name
        case cupRoundSportEventNumber = "cup_round_sport_event_number"
        case cupRoundNumberOfSportEvents = "cup_round_number_of_sport_events"
        case cupRoundID = "cup_round_id"
        case otherSportEventID = "other_sport_event_id"
    }
}
