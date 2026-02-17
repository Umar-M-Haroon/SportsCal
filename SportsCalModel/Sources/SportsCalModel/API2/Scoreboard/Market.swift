// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let market = try? newJSONDecoder().decode(Market.self, from: jsonData)

import Foundation

// MARK: - Market
public struct Market: Codable {
    public var id, type: String

    public init(id: String, type: String) {
        self.id = id
        self.type = type
    }
}
