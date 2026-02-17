// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let address = try? newJSONDecoder().decode(Address.self, from: jsonData)

import Foundation

// MARK: - Address
public struct Address: Codable {
    public var city, state: String?

    public init(city: String, state: String) {
        self.city = city
        self.state = state
    }
}
