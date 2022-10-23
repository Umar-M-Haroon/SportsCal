// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let stage = try? newJSONDecoder().decode(Stage.self, from: jsonData)

import Foundation

// MARK: - Stage
struct Stage: Codable {
    let order: Int
    let type: StageType
    let phase: Phase
    let startDate, endDate: String
    let year: String

    enum CodingKeys: String, CodingKey {
        case order, type, phase
        case startDate = "start_date"
        case endDate = "end_date"
        case year
    }
}
