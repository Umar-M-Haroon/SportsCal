// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let athlete = try? newJSONDecoder().decode(Athlete.self, from: jsonData)

import Foundation

// MARK: - Athlete
public struct Athlete: Codable {
    public var id, fullName, displayName, shortName: String?
    public var links: [AthleteLink]?
    public var headshot: String?
    public var jersey: String?
    public var position: Position?
    public var active: Bool?

    public init(id: String, fullName: String, displayName: String, shortName: String, links: [AthleteLink], headshot: String, jersey: String?, position: Position, active: Bool) {
        self.id = id
        self.fullName = fullName
        self.displayName = displayName
        self.shortName = shortName
        self.links = links
        self.headshot = headshot
        self.jersey = jersey
        self.position = position
        self.active = active
    }
}
