//
//  File.swift
//  
//
//  Created by Umar Haroon on 3/16/23.
//

import Foundation
import Redis
enum RedisEndpoint {
    
    case eventState(String)//"EventState-\(event.id)"
    case teams
    case espn(ESPN)
    case sportsDB(SportsDB)
    case pushToStart(String) // "PushToStart-{token}"
    case pushToStartEvents(String) // "PushToStartEvents-{token}"
    case sentPushToStart(String, String) // "SentPushToStart-{token}-{eventID}"
    enum SportsDB {
        case latestLiveInfo
        case latestFullLiveInfo
        case teams
        public var value: RedisKey {
            switch self {
            case .latestFullLiveInfo:
                return "Latest Full Live Info (TSDB)"
            case .latestLiveInfo:
                return "Latest Live Info (TSDB)"
            case .teams:
                return "TSDB Teams"
            }
        }
        public var debugValue: RedisKey {
            switch self {
            case .latestFullLiveInfo:
                return "debug-Latest Full Live Info (TSDB)"
            case .latestLiveInfo:
                return "debug-Latest Live Info (TSDB)"
            case .teams:
                return "debug-TSDB Teams"
            }
        }
        public func getValue(isDebug: Bool = false) -> RedisKey {
            if isDebug {
                return debugValue
            }
            return value
        }
    }
    enum ESPN {
        case latestLiveInfo
        case latestFullLiveInfo
        case allSoccerScoreboards
        case latestSoccerScoreboards
        case allTennisScoreboards
        case latestTennisScoreboards
        case latestSchedule
        case scheduleLastUpdate
        case teams
        case f1Standings
        case f1Circuits
        case f1CircuitImages
        case f1EnrichmentLastUpdate
        case golfEnrichment
        case golfEnrichmentLastUpdate
        case injuries
        case injuriesLastUpdate
        case postseasonWindow
        case postseasonWindowLastUpdate
        public var value: RedisKey {
            switch self {
            case .latestLiveInfo:
                return "Latest Full Live Info"
            case .latestFullLiveInfo:
                return "Latest Detailed Full Live Info"
            case .allSoccerScoreboards:
                return "All Soccer Scoreboards"
            case .latestSoccerScoreboards:
                return "Latest Soccer Scoreboards"
            case .allTennisScoreboards:
                return "All Tennis Scoreboards"
            case .latestTennisScoreboards:
                return "Latest Tennis Scoreboards"
            case .latestSchedule:
                return "Latest Schedule"
            case .scheduleLastUpdate:
                return "Schedule Last Update"
            case .teams:
                return "ESPN Teams"
            case .f1Standings:
                return "F1 Standings"
            case .f1Circuits:
                return "F1 Circuits"
            case .f1CircuitImages:
                return "F1 Circuit Images"
            case .f1EnrichmentLastUpdate:
                return "F1 Enrichment Last Update"
            case .golfEnrichment:
                return "Golf Enrichment"
            case .golfEnrichmentLastUpdate:
                return "Golf Enrichment Last Update"
            case .injuries:
                return "Injuries"
            case .injuriesLastUpdate:
                return "Injuries Last Update"
            case .postseasonWindow:
                return "Postseason Window"
            case .postseasonWindowLastUpdate:
                return "Postseason Window Last Update"
            }
        }
        public var debugValue: RedisKey {
            switch self {
            case .latestLiveInfo:
                return "debug-Latest Full Live Info"
            case .latestFullLiveInfo:
                return "debug-Latest Detailed Full Live Info"
            case .allSoccerScoreboards:
                return "debug-All Soccer Scoreboards"
            case .latestSoccerScoreboards:
                return "debug-Latest Soccer Scoreboards"
            case .allTennisScoreboards:
                return "debug-All Tennis Scoreboards"
            case .latestTennisScoreboards:
                return "debug-Latest Tennis Scoreboards"
            case .latestSchedule:
                return "debug-Latest Schedule"
            case .scheduleLastUpdate:
                return "debug-Schedule Last Update"
            case .teams:
                return "debug-ESPN Teams"
            case .f1Standings:
                return "debug-F1 Standings"
            case .f1Circuits:
                return "debug-F1 Circuits"
            case .f1CircuitImages:
                return "debug-F1 Circuit Images"
            case .f1EnrichmentLastUpdate:
                return "debug-F1 Enrichment Last Update"
            case .golfEnrichment:
                return "debug-Golf Enrichment"
            case .golfEnrichmentLastUpdate:
                return "debug-Golf Enrichment Last Update"
            case .injuries:
                return "debug-Injuries"
            case .injuriesLastUpdate:
                return "debug-Injuries Last Update"
            case .postseasonWindow:
                return "debug-Postseason Window"
            case .postseasonWindowLastUpdate:
                return "debug-Postseason Window Last Update"
            }
        }
        public func getValue(isDebug: Bool = false) -> RedisKey {
            if isDebug {
                return debugValue
            }
            return value
        }
    }
    public var value: RedisKey {
        switch self {
        case .eventState(let string):
            return "EventState-\(string)"
        case .teams:
            return "Teams"
        case .espn(let endpoint):
            return endpoint.value
        case .sportsDB(let endpoint):
            return endpoint.value
        case .pushToStart(let token):
            return "PushToStart-\(token)"
        case .pushToStartEvents(let token):
            return "PushToStartEvents-\(token)"
        case .sentPushToStart(let token, let eventID):
            return "SentPushToStart-\(token)-\(eventID)"
        }
    }
    public var debugValue: RedisKey {
        switch self {
        case .eventState(let string):
            return "debug-EventState-\(string)"
        case .teams:
            return "debug-Teams"
        case .espn(let endpoint):
            return "debug-\(endpoint.value)"
        case .sportsDB(let endpoint):
            return "debug-\(endpoint.value)"
        case .pushToStart(let token):
            return "debug-PushToStart-\(token)"
        case .pushToStartEvents(let token):
            return "debug-PushToStartEvents-\(token)"
        case .sentPushToStart(let token, let eventID):
            return "debug-SentPushToStart-\(token)-\(eventID)"
        }
    }
    public func getValue(isDebug: Bool = false) -> RedisKey {
        if isDebug {
            return debugValue
        }
        return value
    }
}
