// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let season = try? newJSONDecoder().decode(Season.self, from: jsonData)

import Foundation

// MARK: - Season
struct Season: Codable {
    let id: String
    let name: String
    let startDate, endDate: String
    let year: String
    let competitionID: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case startDate = "start_date"
        case endDate = "end_date"
        case year
        case competitionID = "competition_id"
    }
}
