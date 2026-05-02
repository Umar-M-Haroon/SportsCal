// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let competitorTeam = try? newJSONDecoder().decode(CompetitorTeam.self, from: jsonData)

import Foundation

// MARK: - CompetitorTeam
public struct CompetitorTeam: Codable {
    public var id, uid: String
    public var location: String?
    public var name: String?
    public var abbreviation: String?
    public var displayName, shortDisplayName: String
    public var color: String?
    public var alternateColor: String?
    public var isActive: Bool
    public var links: [TeamLink]
    public var logo: String?

    public init(id: String, uid: String, location: String?, name: String?, abbreviation: String?, displayName: String, shortDisplayName: String, color: String?, alternateColor: String?, isActive: Bool, links: [TeamLink], logo: String?) {
        self.id = id
        self.uid = uid
        self.location = location
        self.name = name
        self.abbreviation = abbreviation
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName
        self.color = color
        self.alternateColor = alternateColor
        self.isActive = isActive
        self.links = links
        self.logo = logo
    }
}
