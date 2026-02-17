// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let geoBroadcastType = try? newJSONDecoder().decode(GeoBroadcastType.self, from: jsonData)

import Foundation

// MARK: - GeoBroadcastType
public struct GeoBroadcastType: Codable {
    public var id, shortName: String

    public init(id: String, shortName: String) {
        self.id = id
        self.shortName = shortName
    }
}
