// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let logo = try? newJSONDecoder().decode(Logo.self, from: jsonData)

import Foundation

// MARK: - Logo
public struct Logo: Codable {
    public var href: String
    public var width, height: Int?
    public var alt: String?
    public var rel: [String]?
    public var lastUpdated: String?

    public init(href: String, width: Int, height: Int, alt: String, rel: [String], lastUpdated: String) {
        self.href = href
        self.width = width
        self.height = height
        self.alt = alt
        self.rel = rel
        self.lastUpdated = lastUpdated
    }
}
