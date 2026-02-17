// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let liveEvent = try? newJSONDecoder().decode(LiveEvent.self, from: jsonData)

import Foundation

// MARK: - LiveEvent
public struct Scoreboard: Codable {
    public var leagues: [League]
    public var day: Day?
    public var events: [Event]

    public init(leagues: [League], day: Day, events: [Event]) {
        self.leagues = leagues
        self.day = day
        self.events = events
    }
}
