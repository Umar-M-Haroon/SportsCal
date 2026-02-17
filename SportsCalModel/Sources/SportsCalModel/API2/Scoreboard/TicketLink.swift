// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let ticketLink = try? newJSONDecoder().decode(TicketLink.self, from: jsonData)

import Foundation

// MARK: - TicketLink
public struct TicketLink: Codable {
    public var href: String?

    public init(href: String) {
        self.href = href
    }
}
