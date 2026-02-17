// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let format = try? newJSONDecoder().decode(Format.self, from: jsonData)

import Foundation

// MARK: - Format
public struct Format: Codable {
    public var regulation: Regulation

    public init(regulation: Regulation) {
        self.regulation = regulation
    }
}
