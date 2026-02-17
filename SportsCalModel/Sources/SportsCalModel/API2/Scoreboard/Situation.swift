// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let situation = try? newJSONDecoder().decode(Situation.self, from: jsonData)

import Foundation

// MARK: - Situation
public struct Situation: Codable {
    public var lastPlay: LastPlay?

    public init(lastPlay: LastPlay?) {
        self.lastPlay = lastPlay
    }
}
