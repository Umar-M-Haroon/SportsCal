// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let ticket = try? newJSONDecoder().decode(Ticket.self, from: jsonData)

import Foundation

// MARK: - Ticket
public struct Ticket: Codable {
    public var summary: String
    public var numberAvailable: Int
    public var links: [TicketLink]

    public init(summary: String, numberAvailable: Int, links: [TicketLink]) {
        self.summary = summary
        self.numberAvailable = numberAvailable
        self.links = links
    }
}
