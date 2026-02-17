// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let link = try? newJSONDecoder().decode(Link.self, from: jsonData)

import Foundation

// MARK: - Link
public struct Link: Codable {
    public var language: String?
    public var rel: [String]?
    public var href: String?
    public var text, shortText: String?
    public var isExternal, isPremium: Bool?

    public init(language: String?, rel: [String]?, href: String?, text: String?, shortText: String?, isExternal: Bool?, isPremium: Bool?) {
        self.language = language
        self.rel = rel
        self.href = href
        self.text = text
        self.shortText = shortText
        self.isExternal = isExternal
        self.isPremium = isPremium
    }
}
