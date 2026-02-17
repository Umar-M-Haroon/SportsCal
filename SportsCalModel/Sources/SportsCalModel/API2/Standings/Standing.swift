//
//  File.swift
//  
//
//  Created by Umar Haroon on 3/15/24.
//

import Foundation
public struct Standing: Codable {
    public init(id: Leagues, standings: StandingsResponse) {
        self.id = id
        self.standings = standings
    }
    
    public var id: Leagues
    public var standings: StandingsResponse
}
