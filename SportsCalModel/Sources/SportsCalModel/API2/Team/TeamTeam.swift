// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let ESPNTeam = try? newJSONDecoder().decode(ESPNTeam.self, from: jsonData)

import Foundation

// MARK: - ESPNTeam
public struct ESPNTeam: Codable {
    public var id, uid, slug, abbreviation: String?
    public var displayName, shortDisplayName, name, nickname: String?
    public var location, color, alternateColor: String?
    public var isActive, isAllStar: Bool?
    public var logos: [Logo]?
    public var links: [Link]?

    public init(id: String?, uid: String?, slug: String?, abbreviation: String?, displayName: String?, shortDisplayName: String?, name: String?, nickname: String?, location: String?, color: String?, alternateColor: String?, isActive: Bool?, isAllStar: Bool?, logos: [Logo]?, links: [Link]?) {
        self.id = id
        self.uid = uid
        self.slug = slug
        self.abbreviation = abbreviation
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName
        self.name = name
        self.nickname = nickname
        self.location = location
        self.color = color
        self.alternateColor = alternateColor
        self.isActive = isActive
        self.isAllStar = isAllStar
        self.logos = logos
        self.links = links
    }
}
