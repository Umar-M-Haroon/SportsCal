// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let broadcast = try? newJSONDecoder().decode(Broadcast.self, from: jsonData)

import Foundation

// MARK: - Broadcast
public struct Broadcast: Codable {
    public var market: String
    public var names: [String]

    public init(market: String, names: [String]) {
        self.market = market
        self.names = names
    }
}
