// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let venue = try? newJSONDecoder().decode(Venue.self, from: jsonData)

import Foundation

// MARK: - Venue
struct Venue: Codable {
    let id, name: String
    let capacity: Int
    let cityName: String
    let countryName: CountryName
    let mapCoordinates: String?
    let countryCode: CountryCode

    enum CodingKeys: String, CodingKey {
        case id, name, capacity
        case cityName = "city_name"
        case countryName = "country_name"
        case mapCoordinates = "map_coordinates"
        case countryCode = "country_code"
    }
}
