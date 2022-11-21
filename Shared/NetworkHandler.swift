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
    
    static func handleCall() async throws -> LiveScore {
        let urlString = "https://sportscal.komodollc.com/schedules"
        #if DEBUG
//            urlString = "http://localhost:8080/schedules"
        #endif
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode(LiveScore.self, from: data)
    }
    
    static func getScheduleFor(sport: SportType) async throws -> LiveEvent {
        let urlString = "https://sportscal.komodollc.com/sport/\(sport.rawValue)"
//#if DEBUG
//        urlString = "http://localhost:8080/sport/\(sport.rawValue)"
//#endif
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode(LiveEvent.self, from: data)
    }
    
    static func getTeams() async throws -> [Team] {
        let urlString = "https://sportscal.komodollc.com/teams"
        #if DEBUG
//            urlString = "http://localhost:8080/teams"
        #endif
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode([Team].self, from: data)
    }
    
    static func connectWebSocketForLive(debug: Bool = false) -> URLSessionWebSocketTask {
        
        var urlString = "wss://sportscal.komodollc.com/"
//        #if DEBUG
//            urlString = "ws://localhost:8080/"
//        #endif
        let urlPath = debug ? "livedebug" : "ws"
        urlString += urlPath
        let url = URL(string: urlString)!
        let task = URLSession.shared.webSocketTask(with: url)
        return task
    }
    
    static func subscribeToLiveActivityUpdate(token: String, eventID: String) async throws {
        let urlString = "https://sportscal.komodollc.com/liveActivity/\(token)/\(eventID)"
//        #if DEBUG
//        urlString = "http://localhost:8080/liveActivity/\(token)/\(eventID)"
//        #endif
        let url = URL(string: urlString)!
        _ = try await URLSession.shared.data(from: url)
    }
    
    static func getImageFor(url: String, size: ImageSize) async throws -> Data {
        let url = URL(string: url)!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
