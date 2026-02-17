// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let day = try? newJSONDecoder().decode(Day.self, from: jsonData)

import Foundation

// MARK: - Day
public struct Day: Codable {
    public var date: String

    public init(date: String) {
        self.date = date
    }
}
