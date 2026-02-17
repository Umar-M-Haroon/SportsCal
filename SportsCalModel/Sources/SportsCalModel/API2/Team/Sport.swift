// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let sport = try? newJSONDecoder().decode(Sport.self, from: jsonData)

import Foundation

// MARK: - Sport
public struct Sport: Codable {
    public var id, uid, name, slug: String?
    public var leagues: [League]?

    public init(id: String?, uid: String?, name: String?, slug: String?, leagues: [League]?) {
        self.id = id
        self.uid = uid
        self.name = name
        self.slug = slug
        self.leagues = leagues
    }
}
