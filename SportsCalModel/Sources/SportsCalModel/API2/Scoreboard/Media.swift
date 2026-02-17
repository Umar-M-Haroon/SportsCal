// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let media = try? newJSONDecoder().decode(Media.self, from: jsonData)

import Foundation

// MARK: - Media
public struct Media: Codable {
    public var shortName: String

    public init(shortName: String) {
        self.shortName = shortName
    }
}
