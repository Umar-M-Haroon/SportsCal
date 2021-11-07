// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let sportEvent = try? newJSONDecoder().decode(SportEvent.self, from: jsonData)

import Foundation

// MARK: - SportEvent
struct SportEvent: Codable {
    let id: String
    let startTime: String
    let startTimeConfirmed: Bool
    let sportEventContext: SportEventContext
    let coverage: Coverage
    let competitors: [SoccerCompetitor]
    let venue: Venue?
    let replacedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case startTimeConfirmed = "start_time_confirmed"
        case sportEventContext = "sport_event_context"
        case coverage, competitors, venue
        case replacedBy = "replaced_by"
    }
}
