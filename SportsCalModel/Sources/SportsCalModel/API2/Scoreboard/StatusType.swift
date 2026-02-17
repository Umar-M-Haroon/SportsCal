// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let statusType = try? newJSONDecoder().decode(StatusType.self, from: jsonData)

import Foundation

// MARK: - StatusType
public struct StatusType: Codable {
    public var id: String
    public var name: String?
    public var state: String
    public var completed: Bool
    public var description: String?
    public var detail, shortDetail: String?

    public init(id: String, name: String? = nil, state: String, completed: Bool, description: String? = nil, detail: String? = nil, shortDetail: String? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.completed = completed
        self.description = description
        self.detail = detail
        self.shortDetail = shortDetail
    }
}
