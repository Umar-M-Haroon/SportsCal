// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let competitionType = try? newJSONDecoder().decode(CompetitionType.self, from: jsonData)

import Foundation

// MARK: - CompetitionType
public struct CompetitionType: Codable {
    public var id: String
    public var abbreviation: String?

    public init(id: String, abbreviation: String? = nil) {
        self.id = id
        self.abbreviation = abbreviation
    }
}
