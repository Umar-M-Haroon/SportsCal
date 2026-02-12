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
