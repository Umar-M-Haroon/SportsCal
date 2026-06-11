import Foundation

// MARK: - Team
public struct Teams: Codable, Hashable {
    public init(teams: [Team]) {
        self.teams = teams
    }
    
    public var teams: [Team]
}
public struct Team: Codable, Hashable {
    public init(idTeam: String? = nil, strTeam: String? = nil, strTeamShort: String? = nil, strAlternate: String? = nil, strTeamBadge: String? = nil) {
        self.idTeam = idTeam
        self.strTeam = strTeam
        self.strTeamShort = strTeamShort
        self.strAlternate = strAlternate
        self.strTeamBadge = strTeamBadge
    }
    
    public let idTeam: String?
    public let strTeam: String?
    public let strTeamShort: String?
    public let strAlternate: String?
    public let strTeamBadge: String?
    
    enum CodingKeys: String, CodingKey {
        case idTeam = "idTeam"
        case strTeam = "strTeam"
        case strTeamShort = "strTeamShort"
        case strAlternate = "strAlternate"
        case strTeamBadge = "strTeamBadge"
    }

    /// Curated abbreviation corrections keyed by the stable TheSportsDB `idTeam`.
    /// ESPN reports 2-letter codes for a handful of teams (e.g. Knicks "NY",
    /// Warriors "GS") where the league convention is a 3-letter tricode. Applied at
    /// decode time so every consumer — app, widgets, server enrichment — shows the
    /// corrected code without depending on a server redeploy. Keep in sync with
    /// `baseline-teams.json`.
    public static let canonicalAbbreviationOverrides: [String: String] = [
        "134862": "NYK", // New York Knicks (NBA)
        "134865": "GSW", // Golden State Warriors (NBA)
        "134878": "NOP", // New Orleans Pelicans (NBA)
        "134879": "SAS", // San Antonio Spurs (NBA)
        "134852": "LAK", // Los Angeles Kings (NHL)
        "134840": "NJD", // New Jersey Devils (NHL)
        "134853": "SJS", // San Jose Sharks (NHL)
        "134836": "TBL", // Tampa Bay Lightning (NHL)
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .idTeam)
        let decodedShort = try container.decodeIfPresent(String.self, forKey: .strTeamShort)
        self.idTeam = id
        self.strTeam = try container.decodeIfPresent(String.self, forKey: .strTeam)
        // Apply the curated correction so e.g. the Knicks' stored "NY" surfaces as "NYK".
        self.strTeamShort = Team.canonicalAbbreviationOverrides[id ?? ""] ?? decodedShort
        self.strAlternate = try container.decodeIfPresent(String.self, forKey: .strAlternate)
        self.strTeamBadge = try container.decodeIfPresent(String.self, forKey: .strTeamBadge)
    }
}

public extension Team {
    /// Display abbreviation: the real `strTeamShort` when present, otherwise the
    /// initials of each word in the name ("New York Knicks" → "NYK"). Never returns
    /// the broken first-3-characters value ("New York Knicks" → "NEW").
    static func shortCode(strTeamShort: String?, name: String) -> String {
        // Use a provided short code only when it's already a clean 3-letter
        // abbreviation; otherwise derive a 3-letter code from the name.
        if let short = strTeamShort?.folding(options: .diacriticInsensitive, locale: .current),
           short.count == 3, short.allSatisfy(\.isLetter) {
            return short.uppercased()
        }
        // Strip diacritics so "Türkiye" → "TUR", not "TÜRKIYE".
        let clean = name.folding(options: .diacriticInsensitive, locale: .current)
        let words = clean.split(separator: " ")
        if words.count >= 2 {
            let initials = String(words.prefix(3).compactMap(\.first))
            if initials.count >= 3 { return initials.uppercased() }
            // 2-word name → first letter + first two of the second word (e.g.
            // "South Korea" → "SKO") so it's always a 3-letter code.
            return (String(words[0].prefix(1)) + String(words[1].prefix(2))).uppercased()
        }
        // Single word (most nations): first three letters — "Czechia" → "CZE".
        return String(clean.prefix(3)).uppercased()
    }

    /// Display abbreviation for this team, falling back to its own name.
    var shortCode: String { Team.shortCode(strTeamShort: strTeamShort, name: strTeam ?? "") }
}
