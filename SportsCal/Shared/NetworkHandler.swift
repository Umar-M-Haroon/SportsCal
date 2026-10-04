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
#if os(watchOS)
/// The session token the paired iPhone last relayed over WatchConnectivity.
///
/// watchOS has no `DCAppAttestService`, so the watch can never attest for
/// itself. The phone — which has — mints it a restricted `ios-proxy-watch`
/// token and pushes it across in the WatchConnectivity application context.
/// That token is valid for reads and refused by every write route, which suits
/// the watch exactly: it only ever calls `getWidgetScheduleFor` and
/// `getLiveSnapshot`.
///
/// Everything here degrades to nil, and nil means "send the shared API key" —
/// an unpaired, out-of-range, or never-yet-synced watch keeps working unchanged
/// until the server reaches `AUTH_POLICY=jwt-strict`.
enum WatchRelayedToken {
    private static let tokenKey  = "attest.relayedToken"
    private static let expiryKey = "attest.relayedTokenExpiresAt"

    static func store(_ token: String, expiresAt: Date) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: expiryKey)
    }

    /// The relayed token, or nil once it is within 30s of expiry. The watch
    /// cannot refresh one itself, so a token it cannot use is the same as none.
    static func current(now: Date = Date()) -> String? {
        guard let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty else { return nil }
        let expiry = UserDefaults.standard.double(forKey: expiryKey)
        guard expiry > 0, Date(timeIntervalSince1970: expiry).timeIntervalSince(now) > 30 else { return nil }
        return token
    }

    /// True when the phone should be asked for a fresh one. Deliberately more
    /// eager than `current()` so a refresh is requested while the existing
    /// token still works, rather than after it has already lapsed.
    static func needsRefresh(now: Date = Date()) -> Bool {
        let expiry = UserDefaults.standard.double(forKey: expiryKey)
        guard expiry > 0 else { return true }
        return Date(timeIntervalSince1970: expiry).timeIntervalSince(now) < 5 * 60
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }
}
#endif

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

    /// App Attest attests the *main app's* App ID. Extensions (widgets) run under
    /// a different bundle identifier, so a token minted there would fail the
    /// server's relying-party check — they stay on the shared API key.
    private static let isMainApp = Bundle.main.bundleIdentifier == "com.KomodoLLC.SportsCal"

    /// Build a URLRequest with the API key header attached, plus an App Attest
    /// bearer token when one is available.
    ///
    /// The bearer token is deliberately best-effort. During the 3.2 rollout the
    /// server accepts either credential (EitherAuthMiddleware), so a device that
    /// can't attest — simulator against prod, old hardware, MDM-restricted,
    /// Apple's attestation service having a bad day — keeps working on the
    /// shared key instead of losing access. Once adoption is high enough to
    /// require JWT on write routes, this has to become a hard failure with a
    /// 401 retry; see docs/app-attest-plan.md phase 2.
    private static func authenticatedRequest(url: URL) async -> URLRequest {
        var request = apiKeyRequest(url: url)
        if let jwt = await bearerToken() {
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Where this process gets a session token, which differs per target
    /// because only the main app can attest:
    ///
    ///   - **main app** — mints and refreshes its own via `Attestation`.
    ///   - **widget extension** — reads the app's token from the App Group. It
    ///     has a different bundle ID, so a token it attested for itself would
    ///     fail the server's relying-party check.
    ///   - **watch** — uses whatever the phone last relayed over
    ///     WatchConnectivity. watchOS has no `DCAppAttestService` at all.
    ///
    /// nil everywhere means "send the shared API key alone", which stays valid
    /// until the server moves to `AUTH_POLICY=jwt-strict`.
    private static func bearerToken() async -> String? {
        #if os(iOS)
        if isMainApp { return try? await Attestation.shared.getValidJWT() }
        return SharedAttestToken.current()
        #elseif os(watchOS)
        return WatchRelayedToken.current()
        #else
        return nil
        #endif
    }

    /// Sends an authenticated request, retrying once on 401 with a fresh token.
    ///
    /// Required before any route can demand a JWT: a token can be rejected for
    /// reasons the client can't see coming — the server rotated
    /// `JWT_SIGNING_KEY`, the device slept through its own expiry, a clock
    /// skew — and without a retry those all surface as a hard failure on a
    /// route that would have worked a moment later.
    ///
    /// Only the main app retries, because only the main app can mint. The
    /// widget and watch hold relayed tokens they cannot refresh; for them a 401
    /// is terminal for this request and the next one picks up whatever the app
    /// has since published.
    private static func performAuthorized(
        url: URL,
        session: URLSession = .shared,
        customize: (inout URLRequest) -> Void = { _ in }
    ) async throws -> (Data, URLResponse) {
        var request = await authenticatedRequest(url: url)
        customize(&request)
        let (data, response) = try await session.data(for: request)

        guard (response as? HTTPURLResponse)?.statusCode == 401 else { return (data, response) }

        #if os(iOS)
        guard isMainApp else { return (data, response) }
        // Drop the rejected token but keep the Secure Enclave key: the retry
        // then costs one cheap assertion refresh, not a full re-attestation.
        // Only an explicit `X-Attest-Action: re-attest` from the attest routes
        // justifies discarding the key (see Attestation.postJSON).
        await Attestation.shared.invalidateCachedToken()
        var retry = await authenticatedRequest(url: url)
        customize(&retry)
        return try await session.data(for: retry)
        #else
        return (data, response)
        #endif
    }

    /// Handshake request for the live WebSocket.
    ///
    /// `URLSessionWebSocketTask` does carry `URLRequest` headers — that is how
    /// `X-API-Key` has always travelled — so the token goes in `Authorization`
    /// like everywhere else, NOT in a query parameter. A query parameter would
    /// put a live credential into every access log and proxy trace it passes.
    ///
    /// The token is read synchronously from the last one published, because the
    /// three call sites are synchronous (one inside a `Timer` callback) and
    /// making them async would ripple through `GameViewModel`, which compiles
    /// into the widget target too. That is sound here: the app refreshes its
    /// token 60s before expiry, and a socket that opens with a stale one is
    /// closed and retried by the existing reconnect path.
    private static func webSocketRequest(url: URL) -> URLRequest {
        var request = apiKeyRequest(url: url)
        if let jwt = cachedBearerToken() {
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Best-effort token read with no `await`, for synchronous construction
    /// paths. Returns whatever was last published — the main app writes the App
    /// Group copy on every mint, so for it this is its own current token.
    private static func cachedBearerToken() -> String? {
        #if os(iOS)
        return SharedAttestToken.current()
        #elseif os(watchOS)
        return WatchRelayedToken.current()
        #else
        return nil
        #endif
    }

    /// Shared-key-only request. The base for every other builder; on its own it
    /// is used where no token is available or wanted.
    private static func apiKeyRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Constants.apiKey, forHTTPHeaderField: "X-API-Key")
        // Bound the fetch: a silently-stalled connection must fail (and surface the
        // stale-data banner / retry path) rather than pin the refresh task forever.
        request.timeoutInterval = 30
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

    /// Whether the user has college football on. The server leaves college games out of
    /// its schedule and live payloads unless a request asks (`cfb=1`): they're ~1.4 MB of
    /// schedule and a large share of every live frame on a Saturday, and app versions that
    /// predate them would only download and drop them.
    static var wantsCollegeFootball: Bool {
        #if os(watchOS)
        let defaults: UserDefaults? = .standard
        #else
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
        return FootballPreference(defaults: defaults).showCollege
    }

    /// `?cfb=1` when the user wants college football, else nothing.
    private static var collegeQuery: String { wantsCollegeFootball ? "?cfb=1" : "" }

    /// Whether the live socket currently open was asked for college games. The view model
    /// reconnects when this stops matching `wantsCollegeFootball`.
    nonisolated(unsafe) static var socketIncludesCollege = false

    /// The `/schedules` URL for the current environment and college-football variant.
    /// The variant is part of the URL, so it is also what keys the stored ETag: a
    /// validator for the `?cfb=1` payload must never be sent for the plain one.
    static func scheduleURL() -> URL {
        URL(string: "\(baseURL())/schedules\(collegeQuery)")!
    }

    /// Unconditional `/schedules` fetch. Used where there is no local snapshot to
    /// revalidate (tests, diagnostics).
    static func handleCall() async throws -> LiveScore {
        switch try await fetchSchedule(url: scheduleURL(), ifNoneMatch: nil) {
        case .fresh(let snapshot, _):
            return snapshot
        case .notModified:
            // Unreachable without an If-None-Match; fetchSchedule throws instead.
            throw URLError(.badServerResponse)
        }
    }

    /// Outcome of a conditional `/schedules` fetch.
    enum ScheduleFetchResult {
        /// `304 Not Modified`: the snapshot the sent ETag describes is still current.
        case notModified
        /// A full payload, with the validator the server attached to it (if any).
        case fresh(LiveScore, etag: String?)
    }

    /// Conditional `/schedules` fetch.
    ///
    /// The payload is multi-MB, and on most foregrounds it hasn't changed, so the
    /// client revalidates with `If-None-Match` and the server answers `304` with an
    /// empty body — no download, no decode, no `setGames` pass.
    ///
    /// The cache policy is `.reloadIgnoringLocalCacheData` on purpose. With the default
    /// policy URLSession keeps its own copy and may add its own validators; when the
    /// server says 304 it then hands back *its* cached 200, which would hide the 304 and
    /// make us decode the whole payload anyway. Ignoring the local cache means the
    /// 304 we asked for is the 304 we see.
    ///
    /// - Parameters:
    ///   - url: the schedule URL (see `scheduleURL()`); the caller keeps it so the
    ///     returned ETag can be stored against exactly what was requested.
    ///   - ifNoneMatch: the ETag of the snapshot the caller holds, or nil to force a
    ///     full response. Only pass one when that snapshot is actually available locally.
    /// - Returns: `.notModified` on 304, otherwise the decoded snapshot and its ETag.
    /// - Throws: transport and decoding errors; `URLError(.badServerResponse)` for a
    ///   304 the caller didn't ask for.
    static func fetchSchedule(url: URL, ifNoneMatch: String?) async throws -> ScheduleFetchResult {
        let (data, response) = try await performAuthorized(url: url) { request in
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let ifNoneMatch {
                request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
            }
        }
        let httpResponse = response as? HTTPURLResponse
        if let httpResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        if httpResponse?.statusCode == 304 {
            guard ifNoneMatch != nil else { throw URLError(.badServerResponse) }
            return .notModified
        }
        let snapshot = try Self.sharedDecoder.decode(LiveScore.self, from: data)
        return .fresh(snapshot, etag: httpResponse?.value(forHTTPHeaderField: "ETag"))
    }

    /// `yyyyMMdd` in the Gregorian calendar and POSIX locale — the server's day-key
    /// format, shared with `GameViewModel`'s on-demand day bookkeeping.
    static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// On-demand fetch of a single day's multi-sport schedule (YYYYMMDD), for
    /// browsing dates outside the cached /schedules window. Server fetches ESPN
    /// per-league for that day and returns a merged LiveScore.
    static func getSchedule(forDate date: Date) async throws -> LiveScore {
        let dateStr = Self.dayKeyFormatter.string(from: date)
        let urlString = "\(baseURL())/schedules/date/\(dateStr)\(collegeQuery)"
        let url = URL(string: urlString)!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode(LiveScore.self, from: data)
    }

    static func getScheduleFor(sport: SportType) async throws -> LiveEvent {
        var components = URLComponents(string: "\(baseURL())/sport/\(sport.rawValue)")!
        // Browse is for exploring, so it asks for all of FBS regardless of the user's
        // college coverage (the server leaves college out unless asked).
        if sport == .nfl {
            components.queryItems = [
                URLQueryItem(name: "cfb", value: "1"),
                URLQueryItem(name: "cfbSel", value: CollegeFootballSelection.allFBS.rawValue),
            ]
        }
        let url = components.url!
        let (data, response) = try await performAuthorized(url: url)
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
        components.queryItems?.append(contentsOf: collegeFootballQueryItems(sports: sports))
        let url = components.url!
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        AppLogger.widget.info("[widgetFetch] requesting \(url.absoluteString)")
        let (data, response) = try await performAuthorized(url: url, session: session)
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.widget.info("[widgetFetch] response \(httpResponse.statusCode), \(data.count) bytes")
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoded = try Self.sharedDecoder.decode(WidgetResponse.self, from: data)
        AppLogger.widget.info("[widgetFetch] decoded \(decoded.games.count) games, \(decoded.teams.count) teams")
        return (decoded.games, decoded.teams)
    }

    /// College football opt-in for flat game lists. The server leaves college games out of
    /// them unless asked — app versions that predate college football can't handle them —
    /// and applies the user's college picks before its `limit`, so a 60-game Saturday
    /// can't crowd the NFL out of a short list.
    ///
    /// No sports means "games for these favorites", which only ever returns followed teams'
    /// games, so college is always in.
    private static func collegeFootballQueryItems(sports: [SportType]) -> [URLQueryItem] {
        guard sports.isEmpty || sports.contains(.nfl) else { return [] }
        #if os(watchOS)
        let defaults: UserDefaults? = .standard
        #else
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
        let football = FootballPreference(defaults: defaults)
        if sports.isEmpty { return [URLQueryItem(name: "cfb", value: "1")] }
        var items: [URLQueryItem] = []
        if football.showCollege {
            items.append(URLQueryItem(name: "cfb", value: "1"))
            items.append(URLQueryItem(name: "cfbSel", value: football.college.rawValue))
        }
        if !football.showNFL {
            items.append(URLQueryItem(name: "nfl", value: "0"))
        }
        return items
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
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            if httpResponse.statusCode == 404 { throw PlayByPlayNotAvailable() }
        }
        let decoder = Self.sharedDecoder
        return try decoder.decode(CachedPlays.self, from: data)
    }

    /// Post-session race story (lap chart, safety cars, weather, tyres) for the F1 Race or
    /// Sprint that started at `start`. Nil when the server hasn't built it yet (it backfills
    /// finished sessions hourly) or the session isn't a race.
    static func fetchF1SessionDetail(start: Date) async throws -> F1SessionDetail? {
        var components = URLComponents(string: "\(baseURL())/f1/session")!
        components.queryItems = [URLQueryItem(name: "start", value: ISO8601DateFormatter().string(from: start))]
        let (data, response) = try await performAuthorized(url: components.url!)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            if httpResponse.statusCode == 404 { return nil }
        }
        return try Self.sharedDecoder.decode(F1SessionDetail.self, from: data)
    }

    /// Fetches play-by-play directly from **production**, regardless of the currently
    /// resolved environment. Used by the developer replay feature: `/replay` only exists on
    /// a local/dev server, but the recorded play-by-play lives on prod — so the app sources
    /// the plays from prod and hands them to the local replay server.
    static func fetchPlayByPlayFromProduction(
        eventID: String,
        sport: String? = nil,
        league: String? = nil
    ) async throws -> CachedPlays {
        var components = URLComponents(string: "https://\(prodHost)/v2025/plays/\(eventID)")!
        var queryItems: [URLQueryItem] = []
        if let sport { queryItems.append(URLQueryItem(name: "sport", value: sport)) }
        if let league { queryItems.append(URLQueryItem(name: "league", value: league)) }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        let url = components.url!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            throw PlayByPlayNotAvailable()
        }
        return try Self.sharedDecoder.decode(CachedPlays.self, from: data)
    }

    static func getTeams() async throws -> [Team] {
        let urlString = "\(baseURL())/teams"
        let url = URL(string: urlString)!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        let decoder = Self.sharedDecoder
        return try decoder.decode([Team].self, from: data)
    }

    /// Extended profile + roster for a single team (TheSportsDB `idTeam`).
    /// Backed by the server's `GET /team/:id/info` (Redis-cached, 24h).
    static func getTeamDetail(teamID: String) async throws -> TeamDetail {
        let encoded = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? teamID
        let urlString = "\(baseURL())/team/\(encoded)/info"
        let url = URL(string: urlString)!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode(TeamDetail.self, from: data)
    }

    /// League ranks on the stats that matter for one team, or nil where the league has
    /// none (soccer) or ESPN doesn't know the team (404).
    static func getTeamSeasonStats(teamID: String, league: Leagues) async throws -> TeamSeasonStats? {
        let encoded = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? teamID
        var components = URLComponents(string: "\(baseURL())/team/\(encoded)/season-stats")!
        components.queryItems = [URLQueryItem(name: "league", value: String(league.rawValue))]
        let (data, response) = try await performAuthorized(url: components.url!)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            if httpResponse.statusCode == 404 { return nil }
        }
        return try Self.sharedDecoder.decode(TeamSeasonStats.self, from: data)
    }

    static func getLiveSnapshot() async throws -> LiveScore {
        let isMockLive = ProcessInfo.processInfo.environment["mock-live"] != nil

        // Fetch real live data
        let urlString = "\(baseURL())/live\(collegeQuery)"
        let url = URL(string: urlString)!
        var realLiveScore: LiveScore?
        do {
            let (data, response) = try await performAuthorized(url: url)
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

    /// Developer "replay a game as live" target. When set, `connectWebSocketForLive`
    /// dials the server's `/replay/:eventID` endpoint instead of the live `/ws`. The
    /// caller must then send the selected `Game` shell as the first WebSocket message.
    nonisolated(unsafe) static var replayTarget: (eventID: String, speed: Double)?

    static func connectWebSocketForLive(session: URLSession? = nil) -> URLSessionWebSocketTask {
        let (_, wsBase) = rootURL()
        let urlString: String
        if let replay = replayTarget, !replay.eventID.isEmpty {
            let id = replay.eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? replay.eventID
            urlString = "\(wsBase)/v2025/replay/\(id)?speed=\(replay.speed)"
        } else {
            if ProcessInfo.processInfo.environment["mock-live"] != nil {
                urlString = "\(wsBase)/v2025/livedebug"
            } else {
                // Ask for delta frames: a full snapshot on connect, then only the games
                // whose state moved. The full snapshot ran ~4.76 MB and was re-sent on
                // every change. Safe to request unconditionally — a server that doesn't
                // know the parameter ignores it and keeps sending bare snapshots, which
                // the receive path still accepts.
                // College games only when the user has them on (see `wantsCollegeFootball`).
                let college = wantsCollegeFootball
                socketIncludesCollege = college
                urlString = "\(wsBase)/v2025/ws?frames=v2" + (college ? "&cfb=1" : "")
            }
        }
        let url = URL(string: urlString)!
        let request = webSocketRequest(url: url)
        let task = (session ?? URLSession.shared).webSocketTask(with: request)
        // The initial `/ws` snapshot grew past the old 4 MB cap once World Cup
        // plus a full live slate were in play (~4.76 MB observed), which made the
        // socket die on its first frame and reconnect forever. 16 MB gives ample
        // headroom; the server should still gzip/chunk this payload long-term.
        task.maximumMessageSize = 16 * 1024 * 1024 // 16 MB
        return task
    }

    /// True when a WebSocket error is the fatal "incoming frame exceeds
    /// `maximumMessageSize`" case (POSIX `EMSGSIZE` / "Message too long").
    /// Reconnecting can't fix this — the server's next frame is the same size —
    /// so the caller backs off to REST polling instead of hammering the socket.
    static func isOversizedFrameError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == 40 { return true } // EMSGSIZE
        return ns.localizedDescription.localizedCaseInsensitiveContains("message too long")
    }

    static func subscribeToLiveActivityUpdate(token: String, eventID: String, homeTeam: String? = nil, awayTeam: String? = nil) async throws {
        let url = URL(string: "\(baseURL())/liveActivity")!
        var body: [String: Any] = ["token": token, "eventID": eventID]
        if let homeTeam { body["homeTeam"] = homeTeam }
        if let awayTeam { body["awayTeam"] = awayTeam }
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await performAuthorized(url: url) { request in
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Token + APNS-env hint travel in the body and a custom header,
            // respectively, instead of in the URL — keeps both out of access logs.
            request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
            request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
            request.httpBody = encoded
        }
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
        let encoded = try JSONSerialization.data(withJSONObject: ["token": token])
        // Short timeout so an unreachable previous host doesn't block re-registration.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        _ = try await performAuthorized(url: url, session: session) { request in
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
            request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
            request.httpBody = encoded
        }
    }

    /// `"sandbox"` or `"production"`, derived from the embedded provisioning
    /// profile's `aps-environment` entitlement — the same signal Apple uses to mint
    /// push tokens, and the value the server keys its APNS gateway on.
    ///
    /// Deliberately NOT `#if DEBUG`: a *Release*-configuration build run from Xcode
    /// on a device still carries a `development` aps-environment (so ActivityKit
    /// mints a *sandbox* push-to-start token) even though `#if DEBUG` is false.
    /// Reporting "production" for that token made APNS reject it as
    /// `badDeviceToken`, which is how automatic Live Activities silently failed.
    /// Resolved once — the profile is fixed for the process lifetime.
    private static let apnsEnvironmentHint: String = {
        let profileData = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return apnsEnvironment(fromProfile: profileData)
    }()

    /// Pure parser (testable): extracts `aps-environment` from a provisioning
    /// profile's CMS container. App Store / TestFlight builds ship no embedded
    /// profile (`nil` data) → production. Any parse failure also defaults to
    /// production, the safe choice for distribution builds.
    static func apnsEnvironment(fromProfile data: Data?) -> String {
        // The profile is a PKCS#7/CMS blob with the plist embedded as plain text;
        // slice out the <plist>…</plist> span instead of decrypting the wrapper.
        // Latin-1 maps every byte 1:1 so the binary wrapper can't corrupt decoding.
        guard let data,
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<?xml"),
              let end = raw.range(of: "</plist>"),
              let plistData = String(raw[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let apsEnvironment = entitlements["aps-environment"] as? String
        else {
            return "production"
        }
        return apsEnvironment == "development" ? "sandbox" : "production"
    }

    static func getStandings(for leagueID: String) async throws -> Standing {
        let urlString = "\(baseURL())/standings/\(leagueID)"
        let url = URL(string: urlString)!
        let (data, response) = try await performAuthorized(url: url)
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
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode(WorldCupBracket.self, from: data)
    }

    static func getWorldCupScorers() async throws -> [WorldCupScorer] {
        let url = URL(string: "\(baseURL())/worldcup/scorers")!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode([WorldCupScorer].self, from: data)
    }

    static func getWorldCupSquad(teamID: String) async throws -> WorldCupSquad {
        let encoded = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? teamID
        let url = URL(string: "\(baseURL())/worldcup/squad/\(encoded)")!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode(WorldCupSquad.self, from: data)
    }

    /// Error thrown when ESPN has nothing for a soccer match yet (or ever, for some
    /// lower-tier cup ties). Callers should treat this as an empty/unavailable state
    /// rather than a failure.
    struct SoccerMatchNotAvailable: Error {}

    /// Fetches the match centre (lineups, events, shots, momentum, commentary, form,
    /// head-to-head) for any soccer fixture. The server fetches+caches ESPN's per-event
    /// summary on demand. League, day and team names let it find the match on ESPN when
    /// the game carries a TheSportsDB id it hasn't mapped yet.
    /// Throws `SoccerMatchNotAvailable` on 404.
    static func getSoccerMatch(for game: Game, leagueSlug: String?) async throws -> SoccerMatchDetail {
        guard let eventID = game.idEvent else { throw SoccerMatchNotAvailable() }
        let encoded = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        guard var components = URLComponents(string: "\(baseURL())/soccer/match/\(encoded)") else {
            throw SoccerMatchNotAvailable()
        }
        var query = [
            URLQueryItem(name: "home", value: game.strHomeTeam),
            URLQueryItem(name: "away", value: game.strAwayTeam),
        ]
        if let leagueSlug { query.append(URLQueryItem(name: "league", value: leagueSlug)) }
        if let date = game.standardDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            let yyyymmdd = (day.year ?? 0) * 10000 + (day.month ?? 0) * 100 + (day.day ?? 0)
            query.append(URLQueryItem(name: "date", value: String(yyyymmdd)))
        }
        components.queryItems = query
        guard let url = components.url else { throw SoccerMatchNotAvailable() }
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            if httpResponse.statusCode == 404 { throw SoccerMatchNotAvailable() }
        }
        return try Self.sharedDecoder.decode(SoccerMatchDetail.self, from: data)
    }

    /// One soccer competition's table (zones, form) with its top scorers and assisters.
    /// Throws `SoccerMatchNotAvailable` on 404 (a cup with neither).
    static func getSoccerCompetition(league: Leagues) async throws -> SoccerCompetitionHub {
        let url = URL(string: "\(baseURL())/soccer/competition/\(league.rawValue)")!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            if httpResponse.statusCode == 404 { throw SoccerMatchNotAvailable() }
        }
        return try Self.sharedDecoder.decode(SoccerCompetitionHub.self, from: data)
    }

    /// A soccer player's bio, season lines, last five matches and next fixture, by
    /// ESPN athlete id. Throws `SoccerMatchNotAvailable` on 404.
    static func getSoccerPlayer(athleteID: String) async throws -> SoccerPlayerProfile {
        let encoded = athleteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? athleteID
        let url = URL(string: "\(baseURL())/soccer/player/\(encoded)")!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            if httpResponse.statusCode == 404 { throw SoccerMatchNotAvailable() }
        }
        return try Self.sharedDecoder.decode(SoccerPlayerProfile.self, from: data)
    }

    static func getStandingsHistory(leagueID: Int, days: Int = 30) async throws -> [StandingsHistoryDay] {
        let urlString = "\(baseURL())/standings/\(leagueID)/history?days=\(days)"
        let url = URL(string: urlString)!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode([StandingsHistoryDay].self, from: data)
    }

    static func getTeamStats(leagueID: Int) async throws -> [TeamStatEntry] {
        let urlString = "\(baseURL())/stats/\(leagueID)/teams"
        let url = URL(string: urlString)!
        let (data, response) = try await performAuthorized(url: url)
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
        return try Self.sharedDecoder.decode([TeamStatEntry].self, from: data)
    }

    /// Builds the push-to-start registration request. Separated from the send so
    /// tests can pin the wire format the server's `PushToStartRegistration`
    /// decoder and install-keyed dedup rely on (headers, body shape, and the
    /// `eventIDs` key being absent when empty).
    static func pushToStartRegistrationRequest(token: String, favorites: [String], eventIDs: [String]) async throws -> URLRequest {
        let urlString = "\(baseURL())/pushToStart/register"
        let url = URL(string: urlString)!
        var request = await authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
        request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
        var body: [String: Any] = ["token": token, "favorites": favorites]
        // Favorites are matched by name, and college shares names with other sports
        // (Duke, UConn). The server only starts college Live Activities for installs that
        // say they have college football on — older builds never send this.
        if wantsCollegeFootball {
            body["college"] = true
        }
        if !eventIDs.isEmpty {
            body["eventIDs"] = eventIDs
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Registers this install for soccer match alerts: the team names (as its games
    /// carry them) and alert kinds. Empty teams or kinds unregisters it.
    static func registerSoccerAlerts(_ registration: SoccerAlertRegistration) async throws {
        let url = URL(string: "\(baseURL())/notifications/soccer")!
        let body = try JSONEncoder().encode(registration)
        let (_, response) = try await performAuthorized(url: url) { request in
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
            request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
            request.httpBody = body
        }
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
            guard (200..<300).contains(httpResponse.statusCode) else { throw URLError(.badServerResponse) }
        }
    }

    static func registerPushToStart(token: String, favorites: [String], eventIDs: [String] = []) async throws {
        let url = URL(string: "\(baseURL())/pushToStart/register")!
        let prepared = try await pushToStartRegistrationRequest(token: token, favorites: favorites, eventIDs: eventIDs)
        let (_, response) = try await performAuthorized(url: url) { request in
            request.httpMethod = prepared.httpMethod
            request.httpBody = prepared.httpBody
            prepared.allHTTPHeaderFields?.forEach { key, value in
                // The freshly-built request already carries current credentials;
                // don't let the prepared copy's older ones overwrite them.
                guard key != "Authorization", key != "X-API-Key" else { return }
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let httpResponse = response as? HTTPURLResponse {
            APIVersionChecker.shared.checkVersion(from: httpResponse)
        }
    }

    /// DELETE companion to `registerPushToStart`. See `deregisterLiveActivity`
    /// for why we accept an explicit base URL instead of going through `baseURL()`.
    static func deregisterPushToStart(token: String, previousBaseURL: String) async throws {
        guard let url = URL(string: "\(previousBaseURL)/pushToStart/register") else { return }
        let encoded = try JSONSerialization.data(withJSONObject: ["token": token])
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        _ = try await performAuthorized(url: url, session: session) { request in
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apnsEnvironmentHint, forHTTPHeaderField: "X-APNS-Env")
            request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
            request.httpBody = encoded
        }
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
        /// Event IDs with a per-activity *update* token registered server-side — the
        /// path that drives live Lock Screen updates (distinct from push-to-start).
        /// Defaulted so an older server without the field still decodes.
        let activityUpdateEventIDs: [String]

        enum CodingKeys: String, CodingKey {
            case registered, favorites, eventIDs, sentNotifications, apnsConfigured, activityUpdateEventIDs
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            registered = try c.decode(Bool.self, forKey: .registered)
            favorites = try c.decode([String].self, forKey: .favorites)
            eventIDs = try c.decode([String].self, forKey: .eventIDs)
            sentNotifications = try c.decode([String].self, forKey: .sentNotifications)
            apnsConfigured = try c.decode(Bool.self, forKey: .apnsConfigured)
            activityUpdateEventIDs = try c.decodeIfPresent([String].self, forKey: .activityUpdateEventIDs) ?? []
        }
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
        let encoded = try JSONSerialization.data(withJSONObject: [
            "eventID": eventID,
            "homeTeam": homeTeam,
            "awayTeam": awayTeam
        ])
        _ = try await performAuthorized(url: url) { request in
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = encoded
        }
    }
}


/// The ETag of the `/schedules` snapshot currently persisted in the on-disk games cache.
///
/// Stored as one `(url, etag)` record rather than one per URL: the disk cache holds a
/// single snapshot, so only the validator for *that* snapshot may ever be sent. Keyed
/// per URL, toggling college football off and back on would send the `?cfb=1` ETag
/// while the cache held the plain payload, the server would answer 304, and the app
/// would keep showing the wrong variant.
///
/// Invariant: a record exists only while the matching snapshot is on disk. Writers
/// clear it before replacing the cache file and set it only after the atomic write
/// succeeds; readers clear it whenever the cache is missing or unreadable. A 304
/// therefore can never leave the app with nothing to show.
enum ScheduleETagStore {
    private static let defaultsKey = "schedules.etag.v1"
    private static var defaults: UserDefaults { .standard }

    /// The stored ETag, if it was issued for exactly `url`.
    static func etag(for url: URL) -> String? {
        guard let record = defaults.dictionary(forKey: defaultsKey) as? [String: String],
              record["url"] == url.absoluteString else { return nil }
        return record["etag"]
    }

    /// Records `etag` as the validator for the snapshot fetched from `url`; nil clears.
    static func store(_ etag: String?, for url: URL) {
        guard let etag, !etag.isEmpty else { clear(); return }
        defaults.set(["url": url.absoluteString, "etag": etag], forKey: defaultsKey)
    }

    static func clear() {
        defaults.removeObject(forKey: defaultsKey)
    }
}
