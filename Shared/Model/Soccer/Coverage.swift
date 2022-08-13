// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let coverage = try? newJSONDecoder().decode(Coverage.self, from: jsonData)

import Foundation

// MARK: - Coverage
struct Coverage: Codable {
    let type: CoverageType
    let sportEventProperties: SportEventProperties?

    enum CodingKeys: String, CodingKey {
        case type
        case sportEventProperties = "sport_event_properties"
    }
}
