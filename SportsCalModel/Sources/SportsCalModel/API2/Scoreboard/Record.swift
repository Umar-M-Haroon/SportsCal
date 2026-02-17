// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let record = try? newJSONDecoder().decode(Record.self, from: jsonData)

import Foundation

// MARK: - Record
public struct Record: Codable {
    public var name: String
    public var abbreviation: String?
    public var type: String
    public var summary: String

    public init(name: String, abbreviation: String?, type: String, summary: String) {
        self.name = name
        self.abbreviation = abbreviation
        self.type = type
        self.summary = summary
    }
}
