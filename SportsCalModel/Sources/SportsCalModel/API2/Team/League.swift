// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let league = try? newJSONDecoder().decode(League.self, from: jsonData)

import Foundation

// MARK: - League
public struct League: Codable {
    public var id: String
    public var uid, name, abbreviation: String?
    public var shortName, slug: String?
    public var teams: [TeamElement]?

    public init(id: String, uid: String?, name: String?, abbreviation: String?, shortName: String?, slug: String?, teams: [TeamElement]?) {
        self.id = id
        self.uid = uid
        self.name = name
        self.abbreviation = abbreviation
        self.shortName = shortName
        self.slug = slug
        self.teams = teams
    }
}
