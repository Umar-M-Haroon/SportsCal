// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let teamLink = try? newJSONDecoder().decode(TeamLink.self, from: jsonData)

import Foundation

// MARK: - TeamLink
public struct TeamLink: Codable {
    public var href: String?
    public var text: String?
    public var isExternal, isPremium: Bool?

    public init(href: String, text: String, isExternal: Bool, isPremium: Bool) {
        self.href = href
        self.text = text
        self.isExternal = isExternal
        self.isPremium = isPremium
    }
}
