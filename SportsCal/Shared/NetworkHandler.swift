//
//  NetworkHandler.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/2/21.
//

import Foundation
import Security
import SportsCalModel
import os

/// Persistent per-install identifier — UUID generated once and stored in the
/// Keychain so it survives uninstalls when the user reinstalls without wiping
/// the device. The server uses it as the durable key for push-to-start state
/// so an APNS token rotation can't leave a duplicate registration shadowing
/// the new token (the bug that caused two Live Activities per game).
enum InstallID {
    private static let keychainService = "com.KomodoLLC.SportsCal.installID"
    private static let keychainAccount = "installID"

    static func current() -> String {
        if let existing = readKeychain() { return existing }
        let new = UUID().uuidString
        writeKeychain(new)
        return new
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Pure, testable quadratic backoff for WebSocket reconnection.
enum WebSocketBackoff {
    /// Delay before reconnect `attempt` (1-based), capped at 60s.
    /// Sequence: 1→2, 2→8, 3→18, 4→32, 5→50, 6+→60.
    static func delaySeconds(forAttempt attempt: Int) -> TimeInterval {
        min(Double(attempt * attempt) * 2, 60)
    }
}

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

/// Server target environment. `.auto` resolves dynamically to whichever of
/// `.local`/`.dev`/`.prod` is reachable first.
enum ServerEnvironment: String, CaseIterable, Codable {
    case auto
    case local
    case dev
    case prod

    var displayName: String {
        switch self {
        case .auto:  return "Auto"
        case .local: return "Local (Bonjour)"
        case .dev:   return "Dev (Tailscale)"
        case .prod:  return "Prod"
        }
    }

    /// Whether this environment uses a development APNs push token pairing.
    /// Relevant for diagnosing sandbox/production token mismatches.
    var expectsSandboxAPNs: Bool {
        switch self {
        case .auto, .prod: return false
        case .local, .dev: return true
        }
    }
}

extension Notification.Name {
    /// Posted when the resolved server environment changes. Observers should
    /// invalidate any server-specific caches and re-register push tokens.
    static let serverEnvironmentDidChange = Notification.Name("serverEnvironmentDidChange")
}

/// Observable store for the last-known push registration outcome. Kept as a
/// singleton (and in NetworkHandler.swift so every target sees it) so the
/// view model can write and Settings can read without plumbing a new
/// environment object through every target membership.
@Observable
final class PushRegistrationDiagnostics {
    static let shared = PushRegistrationDiagnostics()

    var lastEnvironment: ServerEnvironment?
    var lastTokenPrefix: String?
    var lastRegisteredAt: Date?
    var lastError: String?
    var activeLiveActivities: Int = 0

    private init() {}

    @MainActor
    func recordSuccess(env: ServerEnvironment, tokenPrefix: String, liveActivities: Int) {
        lastEnvironment = env
        lastTokenPrefix = tokenPrefix
        lastRegisteredAt = Date()
        lastError = nil
        activeLiveActivities = liveActivities
    }

    @MainActor
    func recordFailure(env: ServerEnvironment, tokenPrefix: String?, error: String) {
        lastEnvironment = env
        lastTokenPrefix = tokenPrefix
        lastRegisteredAt = Date()
        lastError = error
    }
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

    /// Shared `JSONDecoder` instance reused across every decode in this file.
    /// `JSONDecoder` is documented thread-safe for concurrent `decode` calls once
    /// configured; allocating a fresh one per request was pointless overhead that
    /// added up on the 27 MB /schedules cold path.
    nonisolated(unsafe) static let sharedDecoder = JSONDecoder()

    // MARK: - Environment state

    /// App-group suite used to mirror the resolved environment for widgets.
    private static let appGroupSuite = "group.Komodo.SportsCal"
    private static let currentEnvKey = "serverEnvironment"
    private static let resolvedEnvKey = "resolvedServerEnvironment"

    /// User's selected environment (may be `.auto`). Reads from the app group
    /// so widgets share the same value.
    static var currentEnvironment: ServerEnvironment {
        get {
            let raw = UserDefaults(suiteName: appGroupSuite)?.string(forKey: currentEnvKey)
                ?? UserDefaults.standard.string(forKey: currentEnvKey)
                ?? ""
            return ServerEnvironment(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults(suiteName: appGroupSuite)?.set(newValue.rawValue, forKey: currentEnvKey)
            UserDefaults.standard.set(newValue.rawValue, forKey: currentEnvKey)
        }
    }

    /// The actually-in-use environment after auto-resolution. Never `.auto`.
    static var resolvedEnvironment: ServerEnvironment {
        get {
            let raw = UserDefaults(suiteName: appGroupSuite)?.string(forKey: resolvedEnvKey)
                ?? UserDefaults.standard.string(forKey: resolvedEnvKey)
                ?? ""
            let parsed = ServerEnvironment(rawValue: raw) ?? .prod
            return parsed == .auto ? .prod : parsed
        }
        set {
            let toStore = newValue == .auto ? ServerEnvironment.prod : newValue
            // Capture the *current* host before mutating so we can deregister
            // tokens against the host we're about to leave. baseURL() depends on
            // resolvedEnvironment (and on localServerHost for `.local`), so it
            // must be read before the UserDefaults write.
            let previousBaseURL = baseURL()
            let previous = resolvedEnvironment
            UserDefaults(suiteName: appGroupSuite)?.set(toStore.rawValue, forKey: resolvedEnvKey)
            UserDefaults.standard.set(toStore.rawValue, forKey: resolvedEnvKey)
            if previous != toStore {
                let userInfo: [String: Any] = [
                    "previousBaseURL": previousBaseURL,
                    "previousEnv": previous.rawValue,
                    "newEnv": toStore.rawValue,
                ]
                NotificationCenter.default.post(name: .serverEnvironmentDidChange, object: toStore, userInfo: userInfo)
            }
        }
    }

    /// Host discovered via Bonjour (e.g. "192.168.1.42:8080")
    static var localServerHost: String?

    #if DEBUG
    /// Tailscale IP of the dev server (reachable only from your Tailscale network).
    /// DEBUG-only so the dev IP is never compiled into the shipping Release binary.
    static let tailscaleHost = "100.68.255.93:8080"
    #endif

    /// Production host. Keep public so the Settings screen and parity tools can
    /// display / probe it without re-deriving the URL shape.
    static let prodHost = "api.sportscal.app"

    // MARK: - URL building

    /// Base URL for v2025 API endpoints.
    static func baseURL() -> String {
        #if DEBUG
        switch resolvedEnvironment {
        case .local:
            if let host = localServerHost { return "http://\(host)/v2025" }
            // Local was resolved but Bonjour dropped — fall through to Tailscale.
            return "http://\(tailscaleHost)/v2025"
        case .dev:
            return "http://\(tailscaleHost)/v2025"
        case .auto, .prod:
            return "https://\(prodHost)/v2025"
        }
        #else
        // Release always talks to production — dev hosts are not compiled in.
        return "https://\(prodHost)/v2025"
        #endif
    }

    /// Root server URL without version path (for WebSocket and admin).
    static func rootURL() -> (http: String, ws: String) {
        #if DEBUG
        switch resolvedEnvironment {
        case .local:
            if let host = localServerHost { return ("http://\(host)", "ws://\(host)") }
            return ("http://\(tailscaleHost)", "ws://\(tailscaleHost)")
        case .dev:
            return ("http://\(tailscaleHost)", "ws://\(tailscaleHost)")
        case .auto, .prod:
            return ("https://\(prodHost)", "wss://\(prodHost)")
        }
        #else
        return ("https://\(prodHost)", "wss://\(prodHost)")
        #endif
    }

    /// Build a URLRequest with the API key header attached.
    private static func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Constants.apiKey, forHTTPHeaderField: "X-API-Key")
        return request
    }

    // MARK: - Auto-resolve

    /// Probe a candidate env and mark the first reachable one as resolved. If
    /// `currentEnvironment` is an explicit choice, that value is used directly.
    /// Safe to call repeatedly; probing uses a 500 ms timeout per candidate.
    static func refreshEnvironment() async {
        #if DEBUG
        let desired = currentEnvironment
        if desired != .auto {
            resolvedEnvironment = desired
            return
        }

        if let host = localServerHost,
           await probe(baseURL: "http://\(host)") {
            resolvedEnvironment = .local
            return
        }

        if await probe(baseURL: "http://\(tailscaleHost)") {
            resolvedEnvironment = .dev
            return
        }

        resolvedEnvironment = .prod
        #else
        // Release builds only ever resolve to production.
        resolvedEnvironment = .prod
        #endif
    }

    /// HEAD `/ping` with a short timeout; any HTTP response counts as reachable.
    private static func probe(baseURL: String, timeoutSeconds: TimeInterval = 0.5) async -> Bool {
        guard let url = URL(string: "\(baseURL)/ping") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeoutSeconds
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                // Any HTTP response — even 404/403 — proves the host answered.
                return (100...599).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - API calls

    static func handleCall() async throws -> LiveScore {
        let urlString = "\(baseURL())/schedules"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = Self.sharedDecoder
        return try decoder.decode(LiveScore.self, from: data)
    }

    static func getScheduleFor(sport: SportType) async throws -> LiveEvent {
        let urlString = "\(baseURL())/sport/\(sport.rawValue)"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = Self.sharedDecoder
        return try decoder.decode(LiveEvent.self, from: data)
    }

    /// Lightweight combined schedule + teams fetch for widget extensions (30MB memory limit).
    /// Fetches pre-filtered, field-stripped games from the widget endpoint in a single request.
    static func getWidgetScheduleFor(sports: [SportType], limit: Int = 6, favorites: [String] = []) async throws -> (games: [Game], teams: [Team]) {
        var components = URLComponents(string: "\(baseURL())/widget/schedule")!
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
        let (data, response) = try await session.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.widget.info("[widgetFetch] response \(httpResponse.statusCode), \(data.count) bytes")
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoded = try Self.sharedDecoder.decode(WidgetResponse.self, from: data)
        AppLogger.widget.info("[widgetFetch] decoded \(decoded.games.count) games, \(decoded.teams.count) teams")
        return (decoded.games, decoded.teams)
    }

    /// Convenience wrapper for single-sport widget fetch.
    static func getWidgetScheduleFor(sport: SportType, limit: Int = 6) async throws -> [Game] {
        let result = try await getWidgetScheduleFor(sports: [sport], limit: limit)
        return result.games
    }

    /// Response type for the widget/schedule endpoint
    private struct WidgetResponse: Decodable {
        let games: [Game]
        let teams: [Team]
    }

    /// Error thrown when the server has no play-by-play data for a given event yet.
    /// Callers should treat this as an empty/loading state rather than a hard failure.
    struct PlayByPlayNotAvailable: Error {}

    /// Fetches the cached ESPN play-by-play array for a specific event (NBA/NFL/NHL/MLB).
    /// Throws `PlayByPlayNotAvailable` on 404 — the server hasn't captured plays yet for this event.
    static func fetchPlayByPlay(
        eventID: String,
        sport: String? = nil,
        league: String? = nil
    ) async throws -> CachedPlays {
        var components = URLComponents(string: "\(baseURL())/plays/\(eventID)")!
        var queryItems: [URLQueryItem] = []
        if let sport { queryItems.append(URLQueryItem(name: "sport", value: sport)) }
        if let league { queryItems.append(URLQueryItem(name: "league", value: league)) }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        let url = components.url!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            if httpResponse.statusCode == 404 { throw PlayByPlayNotAvailable() }
        }
        let decoder = Self.sharedDecoder
        return try decoder.decode(CachedPlays.self, from: data)
    }

    static func getTeams() async throws -> [Team] {
        let urlString = "\(baseURL())/teams"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = Self.sharedDecoder
        return try decoder.decode([Team].self, from: data)
    }

    static func getLiveSnapshot() async throws -> LiveScore {
        let isMockLive = ProcessInfo.processInfo.environment["mock-live"] != nil

        // Fetch real live data
        let urlString = "\(baseURL())/live"
        let url = URL(string: urlString)!
        var realLiveScore: LiveScore?
        do {
            let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse {
                APIVersionChecker.shared.checkVersion(from: httpResponse)
            }
            let decoder = Self.sharedDecoder
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

    static func connectWebSocketForLive(session: URLSession? = nil) -> URLSessionWebSocketTask {
        let (_, wsBase) = rootURL()
        let urlPath = ProcessInfo.processInfo.environment["mock-live"] != nil ? "livedebug" : "ws"
        let urlString = "\(wsBase)/v2025/\(urlPath)"
        let url = URL(string: urlString)!
        let request = authenticatedRequest(url: url)
        let task = (session ?? URLSession.shared).webSocketTask(with: request)
        task.maximumMessageSize = 4 * 1024 * 1024 // 4 MB
        return task
    }

    static func subscribeToLiveActivityUpdate(token: String, eventID: String, homeTeam: String? = nil, awayTeam: String? = nil) async throws {
        let url = URL(string: "\(baseURL())/liveActivity")!
        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Token + APNS-env hint travel in the body and a custom header,
        // respectively, instead of in the URL — keeps both out of access logs.
        request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
        request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
        var body: [String: Any] = ["token": token, "eventID": eventID]
        if let homeTeam { body["homeTeam"] = homeTeam }
        if let awayTeam { body["awayTeam"] = awayTeam }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
    }

    /// DELETE companion to `subscribeToLiveActivityUpdate`. Posts to an explicit
    /// `previousBaseURL` (carried in the `.serverEnvironmentDidChange` userInfo)
    /// so the env-flip handler can target the host the device just left, even
    /// though `resolvedEnvironment` already points at the new one. Failure is
    /// non-fatal — the previous host may be unreachable (e.g. Mac asleep), and
    /// the server-side TTL eventually frees the key.
    static func deregisterLiveActivity(token: String, previousBaseURL: String) async throws {
        guard let url = URL(string: "\(previousBaseURL)/liveActivity") else { return }
        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
        request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
        let body: [String: Any] = ["token": token]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Short timeout so an unreachable previous host doesn't block re-registration.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        _ = try await session.data(for: request)
    }

    /// "sandbox" for Xcode debug builds, "production" otherwise. Xcode debug
    /// builds carry the `aps-environment = development` entitlement and receive
    /// sandbox push tokens; archive builds (TestFlight / App Store) get
    /// production tokens. The server uses this to pick the right APNS gateway.
    private static var apnsEnvironmentHint: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func getStandings(for leagueID: String) async throws -> Standing {
        let urlString = "\(baseURL())/standings/\(leagueID)"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = Self.sharedDecoder
        return try decoder.decode(Standing.self, from: data)
    }

    struct StandingsHistoryDay: Codable, Identifiable {
        var id: String { date }
        let date: String
        let leagueID: Int
        let entries: [StandingsHistoryEntry]
    }

    struct StandingsHistoryEntry: Codable {
        let teamID: String?
        let teamName: String
        let teamAbbreviation: String?
        let teamColor: String?
        let teamLogo: String?
        let position: Int
        let division: String?
        let wins: Int?
        let losses: Int?
        let points: Int?
    }

    struct TeamStatEntry: Codable, Identifiable {
        var id: String { teamName }
        let teamName: String
        let teamAbbreviation: String
        let teamColor: String
        let teamLogo: String
        let division: String
        let stats: [String: String]

        func statValue(_ name: String) -> Double? {
            guard let str = stats[name] else { return nil }
            return Double(str)
        }
    }

    // MARK: - World Cup

    static func getWorldCupBracket() async throws -> WorldCupBracket {
        let url = URL(string: "\(baseURL())/worldcup/bracket")!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode(WorldCupBracket.self, from: data)
    }

    static func getWorldCupScorers() async throws -> [WorldCupScorer] {
        let url = URL(string: "\(baseURL())/worldcup/scorers")!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode([WorldCupScorer].self, from: data)
    }

    static func getWorldCupSquad(teamID: String) async throws -> WorldCupSquad {
        let encoded = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? teamID
        let url = URL(string: "\(baseURL())/worldcup/squad/\(encoded)")!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode(WorldCupSquad.self, from: data)
    }

    static func getStandingsHistory(leagueID: Int, days: Int = 30) async throws -> [StandingsHistoryDay] {
        let urlString = "\(baseURL())/standings/\(leagueID)/history?days=\(days)"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode([StandingsHistoryDay].self, from: data)
    }

    static func getTeamStats(leagueID: Int) async throws -> [TeamStatEntry] {
        let urlString = "\(baseURL())/stats/\(leagueID)/teams"
        let url = URL(string: urlString)!
        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest(url: url))
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode([TeamStatEntry].self, from: data)
    }

    static func registerPushToStart(token: String, favorites: [String], eventIDs: [String] = []) async throws {
        let urlString = "\(baseURL())/pushToStart/register"
        let url = URL(string: urlString)!
        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
        request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
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

    /// DELETE companion to `registerPushToStart`. See `deregisterLiveActivity`
    /// for why we accept an explicit base URL instead of going through `baseURL()`.
    static func deregisterPushToStart(token: String, previousBaseURL: String) async throws {
        guard let url = URL(string: "\(previousBaseURL)/pushToStart/register") else { return }
        var request = authenticatedRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
        request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
        let body: [String: Any] = ["token": token]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        _ = try await session.data(for: request)
    }

    /// Base URL for admin API endpoints (bypasses /v2025 versioning)
    private static func adminBaseURL() -> String {
        rootURL().http
    }

    struct DeviceRegistrationStatus: Decodable {
        let registered: Bool
        let favorites: [String]
        let eventIDs: [String]
        let sentNotifications: [String]
        let apnsConfigured: Bool
    }

    static func getDeviceRegistrationStatus(tokenPrefix: String) async throws -> DeviceRegistrationStatus {
        let urlString = "\(adminBaseURL())/api/admin/push-to-start/device-status?tokenPrefix=\(tokenPrefix)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try Self.sharedDecoder.decode(DeviceRegistrationStatus.self, from: data)
    }

    static func getImageFor(url: String, size: ImageSize) async throws -> Data {
        let url = URL(string: url)!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// Triggers a debug push-to-start notification from the current dev server.
    static func triggerDebugPushToStart(eventID: String, homeTeam: String, awayTeam: String) async throws {
        let urlString = "\(baseURL())/debug/trigger-push-to-start"
        guard let url = URL(string: urlString) else { return }
        var request = authenticatedRequest(url: url)
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
