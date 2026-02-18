//
//  NetworkHandler.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/2/21.
//

import Foundation
import SportsCalModel
import os

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

/// Tracks API version requirements from server responses
@Observable
final class APIVersionChecker {
    static let shared = APIVersionChecker()

    /// Whether the current app version is below the minimum required version
    var updateRequired: Bool = false

    /// The minimum app version required by the server
    private(set) var minAppVersion: String?

    /// Current API version from the server
    private(set) var apiVersion: String?

    private init() {}

    /// Check response headers for version requirements
    func checkVersion(from response: HTTPURLResponse) {
        if let apiVersion = response.value(forHTTPHeaderField: "X-API-Version") {
            self.apiVersion = apiVersion
        }

        if let minVersion = response.value(forHTTPHeaderField: "X-Min-App-Version") {
            self.minAppVersion = minVersion
            updateRequired = isCurrentVersionBelow(minVersion)
        }
    }

    /// Compare current app version with minimum required version
    private func isCurrentVersionBelow(_ minVersion: String) -> Bool {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return false
        }
        return currentVersion.compare(minVersion, options: .numeric) == .orderedAscending
    }
}

struct NetworkHandler {

    /// Host discovered via Bonjour (e.g. "192.168.1.42:8080")
    static var localServerHost: String?

    /// Base URL for v2025 API endpoints.
    /// Priority: Bonjour local server > SERVER_URL env var > legacy "host" env var > debug/prod
    static func baseURL(debug: Bool) -> String {
        if let local = localServerHost {
            return "http://\(local)/v2025"
        }
        if let serverURL = ProcessInfo.processInfo.environment["SERVER_URL"] {
            let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
            return base.hasSuffix("/v2025") ? base : "\(base)/v2025"
        }
        if let host = ProcessInfo.processInfo.environment["host"] {
            return host
        }
        if debug {
            return "https://debug.sportscal.komodollc.com/v2025"
        }
        return "https://sportscal.komodollc.com/v2025"
    }

    /// Root server URL without version path (for WebSocket and admin).
    /// Priority: Bonjour > SERVER_URL env var > debug/prod
    private static func rootURL(debug: Bool) -> (http: String, ws: String) {
        if let local = localServerHost {
            return ("http://\(local)", "ws://\(local)")
        }
        if let serverURL = ProcessInfo.processInfo.environment["SERVER_URL"] {
            let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
            // Strip /v2025 suffix if present
            let root = base.hasSuffix("/v2025") ? String(base.dropLast(6)) : base
            let wsRoot = root
                .replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")
            return (root, wsRoot)
        }
        if debug {
            return ("https://debug.sportscal.komodollc.com", "wss://debug.sportscal.komodollc.com")
        }
        return ("https://sportscal.komodollc.com", "wss://sportscal.komodollc.com")
    }

    static func handleCall(debug: Bool = false) async throws -> LiveScore {
        let urlString = "\(baseURL(debug: debug))/schedules"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(LiveScore.self, from: data)
    }
    
    static func getScheduleFor(sport: SportType, debug: Bool = false) async throws -> LiveEvent {
        let urlString = "\(baseURL(debug: debug))/sport/\(sport.rawValue)"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(LiveEvent.self, from: data)
    }

    /// Lightweight combined schedule + teams fetch for widget extensions (30MB memory limit).
    /// Fetches pre-filtered, field-stripped games from the widget endpoint in a single request.
    static func getWidgetScheduleFor(sports: [SportType], limit: Int = 6, favorites: [String] = [], debug: Bool = false) async throws -> (games: [Game], teams: [Team]) {
        var components = URLComponents(string: "\(baseURL(debug: debug))/widget/schedule")!
        components.queryItems = [
            URLQueryItem(name: "sports", value: sports.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if !favorites.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "favorites", value: favorites.joined(separator: ",")))
        }
        let url = components.url!
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        AppLogger.widget.info("[widgetFetch] requesting \(url.absoluteString)")
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.widget.info("[widgetFetch] response \(httpResponse.statusCode), \(data.count) bytes")
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoded = try JSONDecoder().decode(WidgetResponse.self, from: data)
        AppLogger.widget.info("[widgetFetch] decoded \(decoded.games.count) games, \(decoded.teams.count) teams")
        return (decoded.games, decoded.teams)
    }

    /// Convenience wrapper for single-sport widget fetch.
    static func getWidgetScheduleFor(sport: SportType, limit: Int = 6, debug: Bool = false) async throws -> [Game] {
        let result = try await getWidgetScheduleFor(sports: [sport], limit: limit, debug: debug)
        return result.games
    }

    /// Response type for the widget/schedule endpoint
    private struct WidgetResponse: Decodable {
        let games: [Game]
        let teams: [Team]
    }
    
    static func getTeams(debug: Bool = false) async throws -> [Team] {
        let urlString = "\(baseURL(debug: debug))/teams"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = JSONDecoder()
        return try decoder.decode([Team].self, from: data)
    }
    
    static func getLiveSnapshot(debug: Bool = false) async throws -> LiveScore {
        let isMockLive = ProcessInfo.processInfo.environment["mock-live"] != nil

        // Fetch real live data
        let urlString = "\(baseURL(debug: debug))/live"
        let url = URL(string: urlString)!
        var realLiveScore: LiveScore?
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                APIVersionChecker.shared.checkVersion(from: httpResponse)
            }
            let decoder = JSONDecoder()
            realLiveScore = try decoder.decode(LiveScore.self, from: data)
        } catch {
            if !isMockLive { throw error }
            // If mock-live is enabled, continue with just fake data
        }

        if isMockLive {
            let fakeScore = Self.mockLiveScore()
            return fakeScore.merging(with: realLiveScore)
        }

        return realLiveScore!
    }

    /// Fake live games for testing - covers multiple sports
    private static func mockLiveScore() -> LiveScore {
        LiveScore(
            nba: LiveEvent(events: [
                Game(idLiveScore: "mock-nba-1", idEvent: "mock-nba-1", strSport: "basketball", idLeague: "4387", strLeague: "NBA", idHomeTeam: "9", idAwayTeam: "3", strHomeTeam: "Golden State Warriors", strAwayTeam: "New Orleans Pelicans", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "60", intAwayScore: "73", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "in", strProgress: "6:43 - 3rd", strEventTime: "2023-03-29T02:00Z", dateEvent: "2023-03-29T02:00Z", updated: nil, strTimestamp: "2023-03-29T02:00Z", lastPlay: "CJ McCollum makes 11-foot driving floating jump shot (Jonas Valanciunas assists)", isCompleted: false, isoDate: Date.now),
                Game(idLiveScore: "mock-nba-2", idEvent: "mock-nba-2", strSport: "basketball", idLeague: "4387", strLeague: "NBA", idHomeTeam: "1", idAwayTeam: "2", strHomeTeam: "Los Angeles Lakers", strAwayTeam: "Boston Celtics", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "88", intAwayScore: "91", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "in", strProgress: "2:15 - 4th", strEventTime: "2023-03-29T02:00Z", dateEvent: "2023-03-29T02:00Z", updated: nil, strTimestamp: "2023-03-29T02:00Z", lastPlay: "LeBron James makes 24-foot three point jumper", isCompleted: false, isoDate: Date.now)
            ]),
            soccer: LiveEvent(events: [
                Game(idLiveScore: "mock-soccer-1", idEvent: "mock-soccer-1", strSport: "soccer", idLeague: "4328", strLeague: "English Premier League", idHomeTeam: "133602", idAwayTeam: "133612", strHomeTeam: "Arsenal", strAwayTeam: "Manchester City", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "2", intAwayScore: "1", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "in", strProgress: "67'", strEventTime: "2023-03-29T15:00Z", dateEvent: "2023-03-29T15:00Z", updated: nil, strTimestamp: "2023-03-29T15:00Z", lastPlay: "Bukayo Saka scores from outside the box", isCompleted: false, isoDate: Date.now)
            ]),
            nhl: LiveEvent(events: [
                Game(idLiveScore: "mock-nhl-1", idEvent: "mock-nhl-1", strSport: "hockey", idLeague: "4380", strLeague: "NHL", idHomeTeam: "134846", idAwayTeam: "134847", strHomeTeam: "Toronto Maple Leafs", strAwayTeam: "Montreal Canadiens", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "3", intAwayScore: "2", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "in", strProgress: "14:22 - 2nd", strEventTime: "2023-03-29T00:00Z", dateEvent: "2023-03-29T00:00Z", updated: nil, strTimestamp: "2023-03-29T00:00Z", lastPlay: "Auston Matthews scores on the power play", isCompleted: false, isoDate: Date.now)
            ])
        )
    }
    
    static func connectWebSocketForLive(session: URLSession? = nil, debug: Bool = false) -> URLSessionWebSocketTask {
        let (_, wsBase) = rootURL(debug: debug)
        let urlPath = ProcessInfo.processInfo.environment["mock-live"] != nil ? "livedebug" : "ws"
        let urlString = "\(wsBase)/v2025/\(urlPath)"
        let url = URL(string: urlString)!
        let task = (session ?? URLSession.shared).webSocketTask(with: url)
        task.maximumMessageSize = 4 * 1024 * 1024 // 4 MB
        return task
    }

    static func subscribeToLiveActivityUpdate(token: String, eventID: String, debug: Bool = false) async throws {
        let urlString = "\(baseURL(debug: debug))/liveActivity/\(token)/\(eventID)"
        let url = URL(string: urlString)!
        let (_, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
    }
    
    static func getStandings(for leagueID: String, debug: Bool = false) async throws -> Standing {
        let urlString = "\(baseURL(debug: debug))/standings/\(leagueID)"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(Standing.self, from: data)
    }

    static func registerPushToStart(token: String, favorites: [String], eventIDs: [String] = [], debug: Bool = false) async throws {
        let urlString = "\(baseURL(debug: debug))/pushToStart/register"
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["token": token, "favorites": favorites]
        if !eventIDs.isEmpty {
            body["eventIDs"] = eventIDs
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
    }

    /// Base URL for admin API endpoints (bypasses /v2025 versioning)
    private static func adminBaseURL(debug: Bool) -> String {
        rootURL(debug: debug).http
    }

    struct DeviceRegistrationStatus: Decodable {
        let registered: Bool
        let favorites: [String]
        let eventIDs: [String]
        let sentNotifications: [String]
        let apnsConfigured: Bool
    }

    static func getDeviceRegistrationStatus(tokenPrefix: String, debug: Bool = false) async throws -> DeviceRegistrationStatus {
        let urlString = "\(adminBaseURL(debug: debug))/api/admin/push-to-start/device-status?tokenPrefix=\(tokenPrefix)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(DeviceRegistrationStatus.self, from: data)
    }

    static func getImageFor(url: String, size: ImageSize) async throws -> Data {
        let url = URL(string: url)!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// Triggers a debug push-to-start notification from the local dev server.
    static func triggerDebugPushToStart(eventID: String, homeTeam: String, awayTeam: String, debug: Bool = true) async throws {
        let urlString = "\(baseURL(debug: debug))/debug/trigger-push-to-start"
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "eventID": eventID,
            "homeTeam": homeTeam,
            "awayTeam": awayTeam
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await URLSession.shared.data(for: request)
    }
}
