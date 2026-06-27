import Foundation

// MARK: - Team Detail

/// Extended profile for a single team: descriptive metadata plus its current roster.
/// Served by `GET /team/:id/info` (TheSportsDB-sourced, Redis-cached) and rendered by
/// the iOS `TeamDetailView`'s "Roster & Stats" section. Both fields are optional/empty-
/// tolerant so the client degrades gracefully when the upstream data is incomplete.
public struct TeamDetail: Codable, Hashable, Sendable {
    public var idTeam: String?
    public var profile: TeamProfile?
    public var players: [TeamPlayer]

    public init(idTeam: String? = nil, profile: TeamProfile? = nil, players: [TeamPlayer] = []) {
        self.idTeam = idTeam
        self.profile = profile
        self.players = players
    }
}

/// Descriptive team metadata (stadium, founding year, blurb, …). Mirrors the subset of
/// TheSportsDB `lookup/team` fields worth surfacing in the app.
public struct TeamProfile: Codable, Hashable, Sendable {
    public var name: String?
    public var badge: String?
    public var fanart: String?
    public var country: String?
    public var league: String?
    public var stadium: String?
    public var stadiumLocation: String?
    public var stadiumCapacity: String?
    public var formedYear: String?
    public var website: String?
    public var descriptionText: String?

    public init(name: String? = nil, badge: String? = nil, fanart: String? = nil,
                country: String? = nil, league: String? = nil, stadium: String? = nil,
                stadiumLocation: String? = nil, stadiumCapacity: String? = nil,
                formedYear: String? = nil, website: String? = nil, descriptionText: String? = nil) {
        self.name = name
        self.badge = badge
        self.fanart = fanart
        self.country = country
        self.league = league
        self.stadium = stadium
        self.stadiumLocation = stadiumLocation
        self.stadiumCapacity = stadiumCapacity
        self.formedYear = formedYear
        self.website = website
        self.descriptionText = descriptionText
    }
}

/// A single roster member.
public struct TeamPlayer: Codable, Hashable, Identifiable, Sendable {
    public var idPlayer: String?
    public var name: String
    public var position: String?
    public var number: String?
    public var nationality: String?
    /// Transparent cutout headshot when available, else a thumbnail.
    public var headshotURL: String?

    public var id: String { idPlayer ?? name }

    public init(idPlayer: String? = nil, name: String, position: String? = nil,
                number: String? = nil, nationality: String? = nil, headshotURL: String? = nil) {
        self.idPlayer = idPlayer
        self.name = name
        self.position = position
        self.number = number
        self.nationality = nationality
        self.headshotURL = headshotURL
    }
}
