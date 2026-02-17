// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let statistic = try? newJSONDecoder().decode(Statistic.self, from: jsonData)

import Foundation

// MARK: - Statistic
public struct Statistic: Codable {
    public var name: String
    public var abbreviation: String
    public var displayValue: String
    public var rankDisplayValue: String?

    public init(name: String, abbreviation: String, displayValue: String, rankDisplayValue: String?) {
        self.name = name
        self.abbreviation = abbreviation
        self.displayValue = displayValue
        self.rankDisplayValue = rankDisplayValue
    }
}
