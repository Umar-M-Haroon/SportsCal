// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let status = try? newJSONDecoder().decode(Status.self, from: jsonData)

import Foundation

// MARK: - Status
public struct Status: Codable {
    public var clock: Double?
    public var displayClock: String?
    public var period: Int?
    public var type: StatusType

    public init(clock: Double?, displayClock: String?, period: Int?, type: StatusType) {
        self.clock = clock
        self.displayClock = displayClock
        self.period = period
        self.type = type
    }
}
