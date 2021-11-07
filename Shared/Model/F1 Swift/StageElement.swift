// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let stageElement = try? newJSONDecoder().decode(StageElement.self, from: jsonData)

import Foundation

// MARK: - StageElement
struct StageElement: Codable {
    let id, stageDescription: String
    let scheduled, scheduledEnd: String
    let type: TypeEnum
    let status: Status
    let singleEvent: Bool
    let gender: String?

    enum CodingKeys: String, CodingKey {
        case id
        case stageDescription = "description"
        case scheduled
        case scheduledEnd = "scheduled_end"
        case type, status
        case singleEvent = "single_event"
        case gender
    }
}
