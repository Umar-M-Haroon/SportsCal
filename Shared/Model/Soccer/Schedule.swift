// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let schedule = try? newJSONDecoder().decode(Schedule.self, from: jsonData)

import Foundation

// MARK: - Schedule
struct Schedule: Codable {
    let sportEvent: SportEvent
    let sportEventStatus: SportEventStatus

    enum CodingKeys: String, CodingKey {
        case sportEvent = "sport_event"
        case sportEventStatus = "sport_event_status"
    }
}
