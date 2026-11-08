//
//  ScoreboardDetails.swift
//  SportsCalModel
//
//  Scoreboard blocks ESPN sends that we used to drop: a competition's `details` (goals
//  and cards), a competitor's `probables` (MLB starting pitchers), and the status's
//  `featuredAthletes` (MLB winning / losing / saving pitchers). See `ScoreboardExtras`
//  for what reaches the app.
//
//  Every decoder here is lenient field by field: these are extras, and one odd value
//  must never fail the scoreboard (and every game on it) the way a strict synthesized
//  decoder would.
//

import Foundation

/// A team reference inside a scoreboard block: just the ESPN id.
public struct ESPNTeamRef: Codable {
    public var id: String?

    public init(id: String?) { self.id = id }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
    }
}

/// The name fields of an athlete inside a scoreboard block.
public struct ESPNAthleteRef: Codable {
    public var displayName: String?
    public var shortName: String?
    public var team: ESPNTeamRef?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
        shortName = (try? container.decodeIfPresent(String.self, forKey: .shortName)) ?? nil
        team = (try? container.decodeIfPresent(ESPNTeamRef.self, forKey: .team)) ?? nil
    }
}

/// A stat on a probable or featured athlete ("ERA" "3.21").
public struct ESPNAthleteStat: Codable {
    public var name: String?
    public var abbreviation: String?
    public var displayValue: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        abbreviation = (try? container.decodeIfPresent(String.self, forKey: .abbreviation)) ?? nil
        displayValue = (try? container.decodeIfPresent(String.self, forKey: .displayValue)) ?? nil
    }
}

/// One entry of `competition.details`: a goal, card, penalty or shootout kick.
public struct ESPNCompetitionDetail: Codable {
    public struct DetailType: Codable {
        public var id: String?
        public var text: String?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
            text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? nil
        }
    }

    public struct Clock: Codable {
        public var value: Double?
        public var displayValue: String?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = (try? container.decodeIfPresent(Double.self, forKey: .value)) ?? nil
            displayValue = (try? container.decodeIfPresent(String.self, forKey: .displayValue)) ?? nil
        }
    }

    public var type: DetailType?
    public var clock: Clock?
    public var team: ESPNTeamRef?
    public var scoringPlay: Bool?
    public var redCard: Bool?
    public var yellowCard: Bool?
    public var penaltyKick: Bool?
    public var ownGoal: Bool?
    public var shootout: Bool?
    public var athletesInvolved: [ESPNAthleteRef]?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decodeIfPresent(DetailType.self, forKey: .type)) ?? nil
        clock = (try? container.decodeIfPresent(Clock.self, forKey: .clock)) ?? nil
        team = (try? container.decodeIfPresent(ESPNTeamRef.self, forKey: .team)) ?? nil
        scoringPlay = (try? container.decodeIfPresent(Bool.self, forKey: .scoringPlay)) ?? nil
        redCard = (try? container.decodeIfPresent(Bool.self, forKey: .redCard)) ?? nil
        yellowCard = (try? container.decodeIfPresent(Bool.self, forKey: .yellowCard)) ?? nil
        penaltyKick = (try? container.decodeIfPresent(Bool.self, forKey: .penaltyKick)) ?? nil
        ownGoal = (try? container.decodeIfPresent(Bool.self, forKey: .ownGoal)) ?? nil
        shootout = (try? container.decodeIfPresent(Bool.self, forKey: .shootout)) ?? nil
        athletesInvolved = (try? container.decodeIfPresent([ESPNAthleteRef].self, forKey: .athletesInvolved)) ?? nil
    }
}

/// One entry of a competitor's `probables` — a probable starting pitcher.
public struct ESPNProbable: Codable {
    public var name: String?
    public var abbreviation: String?
    public var athlete: ESPNAthleteRef?
    public var statistics: [ESPNAthleteStat]?
    /// ESPN's own line, e.g. "(10-5, 3.21)", where it sends one.
    public var record: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        abbreviation = (try? container.decodeIfPresent(String.self, forKey: .abbreviation)) ?? nil
        athlete = (try? container.decodeIfPresent(ESPNAthleteRef.self, forKey: .athlete)) ?? nil
        statistics = (try? container.decodeIfPresent([ESPNAthleteStat].self, forKey: .statistics)) ?? nil
        record = (try? container.decodeIfPresent(String.self, forKey: .record)) ?? nil
    }
}

/// One entry of `status.featuredAthletes` — MLB's winning, losing and saving pitchers.
public struct ESPNFeaturedAthlete: Codable {
    /// "winningPitcher", "losingPitcher", "savingPitcher".
    public var name: String?
    /// "W", "L", "SV".
    public var abbreviation: String?
    public var athlete: ESPNAthleteRef?
    public var team: ESPNTeamRef?
    public var statistics: [ESPNAthleteStat]?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        abbreviation = (try? container.decodeIfPresent(String.self, forKey: .abbreviation)) ?? nil
        athlete = (try? container.decodeIfPresent(ESPNAthleteRef.self, forKey: .athlete)) ?? nil
        team = (try? container.decodeIfPresent(ESPNTeamRef.self, forKey: .team)) ?? nil
        statistics = (try? container.decodeIfPresent([ESPNAthleteStat].self, forKey: .statistics)) ?? nil
    }
}

/// A number ESPN sometimes sends as a string ("4"), decoded either way.
public struct ESPNFlexibleNumber: Codable {
    public var value: Double?

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
