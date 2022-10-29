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
struct NetworkHandler {
    
    static func handleCall(type: SportType? = nil, debug: Bool = false) async throws -> LiveScore {
        var urlString = "https://sportscal.komodollc.com"
        if debug {
            urlString = "http://localhost:8080/schedules"
        }
        if let type = type {
            urlString += "/\(type.rawValue)"
        }
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode(LiveScore.self, from: data)
    }
    
    static func getTeams(debug: Bool = false) async throws -> [Team] {
        var urlString = "https://sportscal.komodollc.com/teams"
        if debug {
            urlString = "http://localhost:8080/teams"
        }
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        
        return try decoder.decode([Team].self, from: data)
    }
    
    static func connectWebSocketForLive(debug: Bool = false) -> URLSessionWebSocketTask {
        var urlString = "ws://sportscal.komodollc.com/ws"
        if debug {
            urlString = "ws://localhost:8080/livedebug"
//            urlString = "ws://localhost:8080/ws"
        }
        let url = URL(string: urlString)!
        let task = URLSession.shared.webSocketTask(with: url)
        return task
    }
    
}
