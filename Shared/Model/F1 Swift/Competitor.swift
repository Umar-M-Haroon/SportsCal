// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let competitor = try? newJSONDecoder().decode(Competitor.self, from: jsonData)

import Foundation

// MARK: - Competitor
struct Competitor: Codable {
    let id, name: String
    let gender: Gender
    let nationality, countryCode: String
    let team: Team
    let result: Result

    enum CodingKeys: String, CodingKey {
        case id, name, gender, nationality
        case countryCode = "country_code"
        case team, result
    }
}
