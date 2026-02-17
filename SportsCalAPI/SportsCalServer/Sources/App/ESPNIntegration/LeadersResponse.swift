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
