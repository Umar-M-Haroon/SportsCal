// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let category = try? newJSONDecoder().decode(Category.self, from: jsonData)

import Foundation

// MARK: - Category
struct Category: Codable {
    let id: String
    let name: String
    let countryCode: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case countryCode = "country_code"
    }
}
