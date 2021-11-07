// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let team = try? newJSONDecoder().decode(Team.self, from: jsonData)

import Foundation

// MARK: - Team
struct Team: Codable {
    let id, name: String
    let gender: Gender
    let nationality, countryCode: String
    let result: Result?

    enum CodingKeys: String, CodingKey {
        case id, name, gender, nationality
        case countryCode = "country_code"
        case result
    }
}
