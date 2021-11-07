// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let f1Stage = try? newJSONDecoder().decode(F1Stage.self, from: jsonData)

import Foundation

// MARK: - F1Stage
struct F1Stage: Codable {
    let id, stageDescription: String
    let scheduled, scheduledEnd: String
    let type: String
    let singleEvent: Bool
    let parents: [Parent]
    let stages: [StageElement]
    let competitors: [Competitor]
    let teams: [Team]

    enum CodingKeys: String, CodingKey {
        case id
        case stageDescription = "description"
        case scheduled
        case scheduledEnd = "scheduled_end"
        case type
        case singleEvent = "single_event"
        case parents, stages, competitors, teams
    }
}
