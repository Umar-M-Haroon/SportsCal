// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let soccerElement = try? newJSONDecoder().decode(SoccerElement.self, from: jsonData)

import Foundation

// MARK: - SoccerElement
struct SoccerElement: Codable {
    let generatedAt: String
    let schedules: [Schedule]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schedules
    }
}
