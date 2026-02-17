// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let athleteLink = try? newJSONDecoder().decode(AthleteLink.self, from: jsonData)

import Foundation

// MARK: - AthleteLink
public struct AthleteLink: Codable {
    public var rel: [String]?
    public var href: String?

    public init(rel: [String], href: String) {
        self.rel = rel
        self.href = href
    }
}
