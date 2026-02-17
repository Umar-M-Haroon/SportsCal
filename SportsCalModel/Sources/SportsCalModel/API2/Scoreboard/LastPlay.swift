// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let lastPlay = try? newJSONDecoder().decode(LastPlay.self, from: jsonData)

import Foundation

// MARK: - LastPlay
public struct LastPlay: Codable {
    public var id: String
    public var type: LastPlayType
    public var text: String
    public var scoreValue: Int

    public init(id: String, type: LastPlayType, text: String, scoreValue: Int) {
        self.id = id
        self.type = type
        self.text = text
        self.scoreValue = scoreValue
    }
}
