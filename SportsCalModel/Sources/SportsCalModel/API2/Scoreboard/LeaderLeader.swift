// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let leaderLeader = try? newJSONDecoder().decode(LeaderLeader.self, from: jsonData)

import Foundation

// MARK: - LeaderLeader
public struct LeaderLeader: Codable {
    public var displayValue: String
    public var value: Double
    public var athlete: Athlete?

    public init(displayValue: String, value: Double, athlete: Athlete?) {
        self.displayValue = displayValue
        self.value = value
        self.athlete = athlete
    }
}
