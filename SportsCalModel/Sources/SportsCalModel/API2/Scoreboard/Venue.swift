// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let venue = try? newJSONDecoder().decode(Venue.self, from: jsonData)

import Foundation

// MARK: - Venue
public struct Venue: Codable {
    public var id: String?
    public var fullName: String?
    public var address: Address?
    public var capacity: Int?
    public var indoor: Bool?

    public init(id: String? = nil, fullName: String? = nil, address: Address? = nil, capacity: Int? = nil, indoor: Bool? = nil) {
        self.id = id
        self.fullName = fullName
        self.address = address
        self.capacity = capacity
        self.indoor = indoor
    }
}
