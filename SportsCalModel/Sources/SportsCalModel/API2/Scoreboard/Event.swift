// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let event = try? newJSONDecoder().decode(Event.self, from: jsonData)

import Foundation

// MARK: - Event
public struct Event: Codable {
    public var id, uid, date, name: String
    public var shortName: String?
    public var season: EventSeason?
    public var competitions: [Competition]?
    public var groupings: [EventGrouping]?
    public var links: [EventLink]?
    public var status: Status?

    public init(id: String, uid: String, date: String, name: String, shortName: String? = nil, season: EventSeason? = nil, competitions: [Competition]? = nil, groupings: [EventGrouping]? = nil, links: [EventLink]? = nil, status: Status? = nil) {
        self.id = id
        self.uid = uid
        self.date = date
        self.name = name
        self.shortName = shortName
        self.season = season
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
    /// Which draw these matches belong to — men's singles, women's doubles, and so on.
    ///
    /// This is the only thing that says which tour a tennis match belongs to. ESPN serves
    /// a combined slam's *entire* draw on both the `atp` and the `wta` board — byte for
    /// byte the same 625 matches, women's included — so the board a match arrived on says
    /// nothing about it. Taking the tour from the board instead of from here is what put
    /// every US Open women's match under ATP.
    public var grouping: GroupingInfo?

    public init(competitions: [Competition]? = nil, grouping: GroupingInfo? = nil) {
        self.competitions = competitions
        self.grouping = grouping
    }
}

// MARK: - GroupingInfo
/// The draw descriptor on a tennis `EventGrouping`.
public struct GroupingInfo: Codable {
    /// ESPN's stable draw identifier: `mens-singles`, `womens-singles`, `mens-doubles`,
    /// `womens-doubles`, `mixed-doubles`.
    public var slug: String?

    public init(slug: String? = nil) {
        self.slug = slug
    }
}
