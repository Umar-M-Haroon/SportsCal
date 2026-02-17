//
//  File.swift
//  
//
//  Created by Umar Haroon on 3/22/23.
//

import Foundation
// StandingsResponse.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let standingsResponse = try? newJSONDecoder().decode(StandingsResponse.self, from: jsonData)



// MARK: - StandingsResponse
public struct StandingsResponse: Codable {
    public var uid, id, name, shortName, abbreviation: String?
    public var children: [Child]?
    public var seasons: [Season]?
    
    public init(uid: String?, id: String?, name: String?, abbreviation: String?, children: [Child]?, seasons: [Season]?) {
        self.uid = uid
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.children = children
        self.seasons = seasons
    }
}

// Child.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let child = try? newJSONDecoder().decode(Child.self, from: jsonData)

import Foundation

// MARK: - Child
public struct Child: Codable {
    public var uid, id, name, abbreviation: String?
    public var standings: Standings?
    
    public init(uid: String?, id: String?, name: String?, abbreviation: String?, standings: Standings?) {
        self.uid = uid
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.standings = standings
    }
}

// Standings.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let standings = try? newJSONDecoder().decode(Standings.self, from: jsonData)

import Foundation

// MARK: - Standings
public struct Standings: Codable {
    public var id, name, displayName: String?
    public var links: [Link]?
    public var season, seasonType: Int?
    public var entries: [Entry]?
    
    public init(id: String?, name: String?, displayName: String?, links: [Link]?, season: Int?, seasonType: Int?, entries: [Entry]?) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.links = links
        self.season = season
        self.seasonType = seasonType
        self.entries = entries
    }
}

// Entry.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let entry = try? newJSONDecoder().decode(Entry.self, from: jsonData)

import Foundation

// MARK: - Entry
public struct Entry: Codable {
    public var team: ESPNTeam?
    public var note: Note?
    public var stats: [Stat]?
    
    public init(team: ESPNTeam?, note: Note?, stats: [Stat]?) {
        self.team = team
        self.note = note
        self.stats = stats
    }
}

// Note.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let note = try? newJSONDecoder().decode(Note.self, from: jsonData)

import Foundation

// MARK: - Note
public struct Note: Codable {
    public var color, description: String?
    public var rank: Int?
    
    public init(color: String?, description: String?, rank: Int?) {
        self.color = color
        self.description = description
        self.rank = rank
    }
}

// Stat.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let stat = try? newJSONDecoder().decode(Stat.self, from: jsonData)

import Foundation

// MARK: - Stat
public struct Stat: Codable {
    public var name, displayName, shortDisplayName, description: String?
    public var abbreviation, type: String?
    public var value: Double?
    public var displayValue, id, summary: String?
    
    public init(name: String?, displayName: String?, shortDisplayName: String?, description: String?, abbreviation: String?, type: String?, value: Double?, displayValue: String?, id: String?, summary: String?) {
        self.name = name
        self.displayName = displayName
        self.shortDisplayName = shortDisplayName
        self.description = description
        self.abbreviation = abbreviation
        self.type = type
        self.value = value
        self.displayValue = displayValue
        self.id = id
        self.summary = summary
    }
}

// Season.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let season = try? newJSONDecoder().decode(Season.self, from: jsonData)

import Foundation

// MARK: - Season
public struct Season: Codable {
    public var year: Int?
    public var startDate, endDate, displayName: String?
    public var types: [TypeElement]?
    
    public init(year: Int?, startDate: String?, endDate: String?, displayName: String?, types: [TypeElement]?) {
        self.year = year
        self.startDate = startDate
        self.endDate = endDate
        self.displayName = displayName
        self.types = types
    }
}

// TypeElement.swift

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let typeElement = try? newJSONDecoder().decode(TypeElement.self, from: jsonData)

import Foundation

// MARK: - TypeElement
public struct TypeElement: Codable {
    public var id, name, abbreviation, startDate: String?
    public var endDate: String?
    public var hasStandings: Bool?
    
    public init(id: String?, name: String?, abbreviation: String?, startDate: String?, endDate: String?, hasStandings: Bool?) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.startDate = startDate
        self.endDate = endDate
        self.hasStandings = hasStandings
    }
}

