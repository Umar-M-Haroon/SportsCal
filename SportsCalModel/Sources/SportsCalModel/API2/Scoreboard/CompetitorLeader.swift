// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let competitorLeader = try? newJSONDecoder().decode(CompetitorLeader.self, from: jsonData)

import Foundation

// MARK: - CompetitorLeader
public struct CompetitorLeader: Codable {
    public var name, displayName, shortDisplayName, abbreviation: String
    public var leaders: [LeaderLeader]

    public init(name: String, displayName: String, shortDisplayName: String, abbreviation: String, leaders: [LeaderLeader]) {
        self.name = name
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName
        self.abbreviation = abbreviation
        self.leaders = leaders
    }
}
