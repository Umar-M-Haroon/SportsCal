// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let position = try? newJSONDecoder().decode(Position.self, from: jsonData)

import Foundation

// MARK: - Position
public struct Position: Codable {
    public var abbreviation: String

    public init(abbreviation: String) {
        self.abbreviation = abbreviation
    }
}
