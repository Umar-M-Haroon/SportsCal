// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let teamElement = try? newJSONDecoder().decode(TeamElement.self, from: jsonData)

import Foundation

// MARK: - TeamElement
public struct TeamElement: Codable {
    public var team: ESPNTeam?

    public init(team: ESPNTeam?) {
        self.team = team
    }
}
