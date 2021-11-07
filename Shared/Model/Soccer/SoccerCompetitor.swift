// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let competitor = try? newJSONDecoder().decode(SoccerCompetitor.self, from: jsonData)

import Foundation

// MARK: - SoccerCompetitor
struct SoccerCompetitor: Codable {
    let id, name: String
    let country: CountryName
    let countryCode: CountryCode
    let abbreviation: String
    let qualifier: Qualifier
    let gender: SoccerGender

    enum CodingKeys: String, CodingKey {
        case id, name, country
        case countryCode = "country_code"
        case abbreviation, qualifier, gender
    }
}
