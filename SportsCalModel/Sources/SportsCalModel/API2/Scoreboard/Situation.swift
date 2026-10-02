// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let situation = try? newJSONDecoder().decode(Situation.self, from: jsonData)

import Foundation

// MARK: - Situation
/// ESPN's live game state (`competition.situation`), present only while a game is in
/// progress. Which fields appear depends on the sport: baseball sends the count, outs,
/// runners and the current matchup; football sends down, distance, field position and
/// timeouts; basketball and football attach win probability to `lastPlay`.
///
/// Every field is decoded with `try?`. This struct sits inside the scoreboard decode, so
/// one field changing type upstream would otherwise throw away the whole league's
/// scoreboard rather than just that field.
public struct Situation: Codable {
    public var lastPlay: LastPlay?

    // Baseball
    public var balls: Int?
    public var strikes: Int?
    public var outs: Int?
    public var onFirst: Bool?
    public var onSecond: Bool?
    public var onThird: Bool?
    public var batter: SituationAthlete?
    public var pitcher: SituationAthlete?

    // Football
    public var down: Int?
    public var distance: Int?
    public var yardLine: Int?
    public var downDistanceText: String?
    public var shortDownDistanceText: String?
    public var possessionText: String?
    /// ESPN team ID of the side with the ball.
    public var possession: String?
    public var isRedZone: Bool?
    public var homeTimeouts: Int?
    public var awayTimeouts: Int?

    public init(lastPlay: LastPlay?) {
        self.lastPlay = lastPlay
    }

    enum CodingKeys: String, CodingKey {
        case lastPlay
        case balls, strikes, outs, onFirst, onSecond, onThird, batter, pitcher
        case down, distance, yardLine, downDistanceText, shortDownDistanceText, possessionText
        case possession, isRedZone, homeTimeouts, awayTimeouts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastPlay = try? c.decodeIfPresent(LastPlay.self, forKey: .lastPlay)
        balls = try? c.decodeIfPresent(Int.self, forKey: .balls)
        strikes = try? c.decodeIfPresent(Int.self, forKey: .strikes)
        outs = try? c.decodeIfPresent(Int.self, forKey: .outs)
        onFirst = try? c.decodeIfPresent(Bool.self, forKey: .onFirst)
        onSecond = try? c.decodeIfPresent(Bool.self, forKey: .onSecond)
        onThird = try? c.decodeIfPresent(Bool.self, forKey: .onThird)
        batter = try? c.decodeIfPresent(SituationAthlete.self, forKey: .batter)
        pitcher = try? c.decodeIfPresent(SituationAthlete.self, forKey: .pitcher)
        down = try? c.decodeIfPresent(Int.self, forKey: .down)
        distance = try? c.decodeIfPresent(Int.self, forKey: .distance)
        yardLine = try? c.decodeIfPresent(Int.self, forKey: .yardLine)
        downDistanceText = try? c.decodeIfPresent(String.self, forKey: .downDistanceText)
        shortDownDistanceText = try? c.decodeIfPresent(String.self, forKey: .shortDownDistanceText)
        possessionText = try? c.decodeIfPresent(String.self, forKey: .possessionText)
        // Usually a string team ID; tolerate a bare number.
        if let id = try? c.decodeIfPresent(String.self, forKey: .possession) {
            possession = id
        } else if let id = try? c.decodeIfPresent(Int.self, forKey: .possession) {
            possession = String(id)
        }
        isRedZone = try? c.decodeIfPresent(Bool.self, forKey: .isRedZone)
        homeTimeouts = try? c.decodeIfPresent(Int.self, forKey: .homeTimeouts)
        awayTimeouts = try? c.decodeIfPresent(Int.self, forKey: .awayTimeouts)
    }
}

/// The batter or pitcher in a baseball `situation`: the athlete plus their line for the
/// game so far (`"1-3, HR"`, `"6.0 IP, 2 ER, 7 K"`).
public struct SituationAthlete: Codable {
    public var athlete: Name?
    public var summary: String?

    public struct Name: Codable {
        public var displayName: String?
        public var shortName: String?
    }

    public init(athlete: Name?, summary: String?) {
        self.athlete = athlete
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey { case athlete, summary }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        athlete = try? c.decodeIfPresent(Name.self, forKey: .athlete)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
    }
}

/// ESPN's win probability, attached to `situation.lastPlay` (basketball, football) and to
/// every entry of a summary's `winprobability` series. Values are 0...1.
public struct WinProbabilityValue: Codable, Equatable, Hashable, Sendable {
    public var homeWinPercentage: Double?
    public var awayWinPercentage: Double?
    public var tiePercentage: Double?

    public init(homeWinPercentage: Double?, awayWinPercentage: Double? = nil, tiePercentage: Double? = nil) {
        self.homeWinPercentage = homeWinPercentage
        self.awayWinPercentage = awayWinPercentage
        self.tiePercentage = tiePercentage
    }
}
