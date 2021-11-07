// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let sportEventContext = try? newJSONDecoder().decode(SportEventContext.self, from: jsonData)

import Foundation

// MARK: - SportEventContext
struct SportEventContext: Codable {
    let sport: Competition
    let category: Category
    let competition: Competition
    let season: Season
    let stage: Stage
    let round: Round
    let groups: [Competition]
}
