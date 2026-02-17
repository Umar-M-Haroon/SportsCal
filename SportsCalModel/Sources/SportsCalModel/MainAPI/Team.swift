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
}
