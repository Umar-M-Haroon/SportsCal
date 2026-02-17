// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let lastPlayType = try? newJSONDecoder().decode(LastPlayType.self, from: jsonData)

import Foundation

// MARK: - LastPlayType
public struct LastPlayType: Codable {
    public var id, text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}
