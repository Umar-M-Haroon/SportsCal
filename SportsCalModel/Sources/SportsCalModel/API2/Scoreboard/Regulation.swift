// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let regulation = try? newJSONDecoder().decode(Regulation.self, from: jsonData)

import Foundation

// MARK: - Regulation
public struct Regulation: Codable {
    public var periods: Int?

    public init(periods: Int) {
        self.periods = periods
    }
}
