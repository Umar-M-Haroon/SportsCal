// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let eventSeason = try? newJSONDecoder().decode(EventSeason.self, from: jsonData)

import Foundation

// MARK: - EventSeason
public struct EventSeason: Codable {
    public var year, type: Int
    public var slug: String

    public init(year: Int, type: Int, slug: String) {
        self.year = year
        self.type = type
        self.slug = slug
    }
}
