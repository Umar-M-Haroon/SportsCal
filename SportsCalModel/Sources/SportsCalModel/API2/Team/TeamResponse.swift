// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let teamResponse = try? newJSONDecoder().decode(TeamResponse.self, from: jsonData)

import Foundation

// MARK: - TeamResponse
public struct TeamResponse: Codable {
    public var sports: [Sport]
    public var teams: [ESPNTeam]? {
        sports.compactMap({$0})
            .compactMap({$0.leagues})
            .flatMap({$0})
            .compactMap({$0.teams})
            .flatMap({$0})
            .compactMap({$0.team})
    }

    public init(sports: [Sport]) {
        self.sports = sports
    }
}
