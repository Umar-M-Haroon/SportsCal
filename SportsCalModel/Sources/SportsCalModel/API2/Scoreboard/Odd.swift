// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let odd = try? newJSONDecoder().decode(Odd.self, from: jsonData)

import Foundation

// MARK: - Odd
public struct Odd: Codable {
    public var provider: Provider?
    public var details: String?
    public var overUnder: Double?

    public init(provider: Provider, details: String, overUnder: Double) {
        self.provider = provider
        self.details = details
        self.overUnder = overUnder
    }
}
