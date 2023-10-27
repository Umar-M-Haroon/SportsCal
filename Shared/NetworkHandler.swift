//
//  NetworkHandler.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/2/21.
//

import Foundation
import SportsCalModel

enum NetworkState: String {
    case loading = "Loading"
    case loaded = "Loaded"
    case failed = "Failed"
}
enum ImageSize: String {
    case preview
    case tiny
    case none = ""
}
struct NetworkHandler {
    
    static func handleCall(debug: Bool = false) async throws -> LiveScore {
        var urlString = "https://sportscal.komodollc.com/schedules"
        if debug {
            urlString = "https://debug.sportscal.komodollc.com/schedules"
        }
        if let host = ProcessInfo.processInfo.environment["host"] {
            urlString = "\(host)/schedules"
        }
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        return try decoder.decode(LiveScore.self, from: data)
    }
    
    static func getScheduleFor(sport: SportType, debug: Bool = false) async throws -> LiveEvent {
        var urlString = "https://sportscal.komodollc.com/sport/\(sport.rawValue)"
        if debug {
            urlString = "https://debug.sportscal.komodollc.com/sport/\(sport.rawValue)"
        }
        if let host = ProcessInfo.processInfo.environment["host"] {
            urlString = "\(host)/sport/\(sport.rawValue)"
        }
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode(LiveEvent.self, from: data)
    }
    
    static func getTeams(debug: Bool = false) async throws -> [Team] {
        var urlString = "https://sportscal.komodollc.com/teams"
        if debug {
            urlString = "https://debug.sportscal.komodollc.com/teams"
        }
        if let host = ProcessInfo.processInfo.environment["host"] {
            urlString = "\(host)/teams"
        }
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode([Team].self, from: data)
    }
    
    static func getLiveSnapshot(debug: Bool = false) async throws -> LiveScore {
        var urlString = "https://sportscal.komodollc.com"
        if debug {
            urlString = "https://debug.sportscal.komodollc.com"
        }
        if let host = ProcessInfo.processInfo.environment["host"] {
            urlString = "\(host)"
        }
        var urlPath = "/live"

        if let _ = ProcessInfo.processInfo.environment["mock-live"] {
            urlPath = "/live-debug"
            return LiveScore(nba: LiveEvent(events: [Game(idLiveScore: "401469290", idEvent: "401469290", strSport: "basketball", idLeague: "4387", strLeague: "NBA", idHomeTeam: "9", idAwayTeam: "3", strHomeTeam: "Golden State Warriors", strAwayTeam: "New Orleans Pelicans", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "60", intAwayScore: "73", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "in", strProgress: "6:43 - 3rd", strEventTime: "2023-03-29T02:00Z", dateEvent: "2023-03-29T02:00Z", updated: nil, strTimestamp: "2023-03-29T02:00Z", lastPlay: "CJ McCollum makes 11-foot driving floating jump shot (Jonas Valanciunas assists)", isCompleted: false, isoDate: Date.now)]))
        }
        urlString += urlPath
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode(LiveScore.self, from: data)
    }
    
    static func connectWebSocketForLive(debug: Bool = false) -> URLSessionWebSocketTask {
        var urlString = "wss://sportscal.komodollc.com/"
        if debug {
            urlString = "wss://debug.sportscal.komodollc.com/"
        }
        if let host = ProcessInfo.processInfo.environment["websockethost"] {
            urlString = "\(host)/"
        }
        var urlPath = "ws"
        if let _ = ProcessInfo.processInfo.environment["mock-live"] {
            urlPath = "livedebug"
        }
        urlString += urlPath
        let url = URL(string: urlString)!
        let task = URLSession.shared.webSocketTask(with: url)
        return task
    }
    
    static func subscribeToLiveActivityUpdate(token: String, eventID: String, debug: Bool = false) async throws {
        var urlString = "https://sportscal.komodollc.com/liveActivity/\(token)/\(eventID)"
        if debug {
            urlString = "https://debug.sportscal.komodollc.com/liveActivity/\(token)/\(eventID)"
        }
        if let host = ProcessInfo.processInfo.environment["host"] {
            urlString = "\(host)/liveActivity/\(token)/\(eventID)"
        }
        let url = URL(string: urlString)!
        _ = try await URLSession.shared.data(from: url)
    }
    
    static func getImageFor(url: String, size: ImageSize) async throws -> Data {
        let url = URL(string: url)!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
