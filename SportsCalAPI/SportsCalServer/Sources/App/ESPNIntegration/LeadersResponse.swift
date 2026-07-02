//
//  LeadersResponse.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 2/16/26.
//

import Foundation

/// Decodes the ESPN leaders API response.
/// Endpoint: site.api.espn.com/apis/site/v2/sports/{sport}/{slug}/leaders
struct LeadersResponse: Decodable {
    let leaders: [LeaderCategory]?

    struct LeaderCategory: Decodable {
        let name: String?
        let displayName: String?
        let abbreviation: String?
        let leaders: [LeaderEntry]?
    }

    struct LeaderEntry: Decodable {
        let displayValue: String?
        let athlete: LeaderAthlete?
        let team: LeaderTeam?
    }

    struct LeaderAthlete: Decodable {
        let id: String?
        let displayName: String?
        let shortName: String?
        let headshot: Headshot?
        let position: Position?

        struct Headshot: Decodable {
            let href: String?
        }

        struct Position: Decodable {
            let abbreviation: String?
        }
    }

    struct LeaderTeam: Decodable {
        let id: String?
        let displayName: String?
        let abbreviation: String?
        let color: String?
        let logos: [TeamLogo]?

        struct TeamLogo: Decodable {
            let href: String?
        }
    }
}

/// Decodes the ESPN league statistics API response — the current source for
/// per-competition leaders (the `/leaders` route 404s for soccer competitions
/// as of the 2026 World Cup; this endpoint carries `goalsLeaders` and
/// `assistsLeaders` with athlete + national-team info inline).
/// Endpoint: site.api.espn.com/apis/site/v2/sports/{sport}/{slug}/statistics
struct LeagueStatisticsResponse: Decodable {
    let stats: [StatCategory]?

    struct StatCategory: Decodable {
        let name: String?
        let displayName: String?
        let leaders: [StatLeader]?
    }

    struct StatLeader: Decodable {
        let displayValue: String?
        let shortDisplayValue: String?
        let value: Double?
        let athlete: StatAthlete?
    }

    struct StatAthlete: Decodable {
        let id: String?
        let displayName: String?
        let shortName: String?
        let jersey: String?
        let team: LeadersResponse.LeaderTeam?
    }
}
