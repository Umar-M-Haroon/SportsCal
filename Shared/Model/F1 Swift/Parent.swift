// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let parent = try? newJSONDecoder().decode(Parent.self, from: jsonData)

import Foundation

// MARK: - Parent
struct Parent: Codable {
    let id, parentDescription, type: String
    let singleEvent: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case parentDescription = "description"
        case type
        case singleEvent = "single_event"
    }
}
