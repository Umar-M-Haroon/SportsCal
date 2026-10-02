// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let lastPlay = try? newJSONDecoder().decode(LastPlay.self, from: jsonData)

import Foundation

// MARK: - LastPlay
public struct LastPlay: Codable {
    public var id: String
    public var type: LastPlayType
    public var text: String
    public var scoreValue: Int
    /// The team the play belongs to.
    public var team: LastPlayTeam?
    /// Win probability after this play. Basketball and football only.
    public var probability: WinProbabilityValue?

    public struct LastPlayTeam: Codable {
        public var id: String?
    }

    public init(id: String, type: LastPlayType, text: String, scoreValue: Int, team: LastPlayTeam? = nil, probability: WinProbabilityValue? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.scoreValue = scoreValue
        self.team = team
        self.probability = probability
    }

    enum CodingKeys: String, CodingKey { case id, type, text, scoreValue, team, probability }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(LastPlayType.self, forKey: .type)
        text = try c.decode(String.self, forKey: .text)
        scoreValue = try c.decode(Int.self, forKey: .scoreValue)
        // The additions decode leniently: an odd shape here must not cost us the play.
        team = try? c.decodeIfPresent(LastPlayTeam.self, forKey: .team)
        probability = try? c.decodeIfPresent(WinProbabilityValue.self, forKey: .probability)
    }
}
