// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let provider = try? newJSONDecoder().decode(Provider.self, from: jsonData)

import Foundation

// MARK: - Provider
public struct Provider: Codable {
    public var id, name: String
    public var priority: Int

    public init(id: String, name: String, priority: Int) {
        self.id = id
        self.name = name
        self.priority = priority
    }
}
