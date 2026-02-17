// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let geoBroadcast = try? newJSONDecoder().decode(GeoBroadcast.self, from: jsonData)

import Foundation

// MARK: - GeoBroadcast
public struct GeoBroadcast: Codable {
    public var type: GeoBroadcastType
    public var market: Market
    public var media: Media
    public var lang, region: String

    public init(type: GeoBroadcastType, market: Market, media: Media, lang: String, region: String) {
        self.type = type
        self.market = market
        self.media = media
        self.lang = lang
        self.region = region
    }
}
