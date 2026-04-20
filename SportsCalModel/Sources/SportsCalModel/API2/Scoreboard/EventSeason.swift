// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let eventSeason = try? newJSONDecoder().decode(EventSeason.self, from: jsonData)

import Foundation

// MARK: - EventSeason
/// Some ESPN endpoints (tennis, etc.) return a season object without a slug, or
/// without year/type. Everything is optional so a missing field never aborts the
/// entire scoreboard decode.
public struct EventSeason: Codable {
    public var year: Int?
    public var type: Int?
    public var slug: String?

    public init(year: Int? = nil, type: Int? = nil, slug: String? = nil) {
        self.year = year
        self.type = type
        self.slug = slug
    }
}
