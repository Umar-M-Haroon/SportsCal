// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let event = try? newJSONDecoder().decode(Event.self, from: jsonData)

import Foundation

// MARK: - Event
public struct Event: Codable {
    public var id, uid, date, name: String
    public var shortName: String?
    public var competitions: [Competition]?
    public var groupings: [EventGrouping]?
    public var links: [EventLink]?
    public var status: Status?

    public init(id: String, uid: String, date: String, name: String, shortName: String? = nil, competitions: [Competition]? = nil, groupings: [EventGrouping]? = nil, links: [EventLink]? = nil, status: Status? = nil) {
        self.id = id
        self.uid = uid
        self.date = date
        self.name = name
        self.shortName = shortName
        self.competitions = competitions
        self.groupings = groupings
        self.links = links
        self.status = status
    }
}

// MARK: - EventGrouping
/// Used by tennis — matches are nested under groupings instead of top-level competitions
public struct EventGrouping: Codable {
    public var competitions: [Competition]?
}
