//
//  RevenueCatEntitlements.swift
//  App
//
//  Server-side check of the app's `Pro` entitlement (the identifier
//  `SubscriptionManager` reads: `customerInfo.entitlements["Pro"]`), so a client can't
//  claim Pro to lift the custom alert cap. RevenueCat REST API v1:
//  `GET https://api.revenuecat.com/v1/subscribers/{app_user_id}` with the secret key
//  from `REVENUECAT_SECRET_KEY`.
//
//  Fails closed: no key, no app user ID, a non-2xx answer, a network error or a body
//  that doesn't parse all mean "free" (and log a warning). Only a successful answer is
//  cached (6h, `RevenueCatPro-{sha256(appUserID)}`), so a RevenueCat outage doesn't
//  pin a paying user to free for hours.
//

import Foundation
import Vapor
import Logging
import Crypto

/// Whether an install is Pro, and whether that was actually verified.
struct ProEntitlementCheck: Equatable, Sendable {
    var isPro: Bool
    /// False when RevenueCat couldn't be asked (no key, error); `isPro` is then false.
    var verified: Bool

    static let unverified = ProEntitlementCheck(isPro: false, verified: false)
}

protocol ProEntitlementChecking: Sendable {
    func check(appUserID: String?) async -> ProEntitlementCheck
}

struct RevenueCatEntitlementChecker: ProEntitlementChecking {
    static let entitlementID = "Pro"
    static let cacheTTL: TimeInterval = 6 * 60 * 60
    static let baseURL = "https://api.revenuecat.com/v1/subscribers/"

    /// One GET: URL and secret key in, HTTP status and body out. Injected so tests
    /// never reach RevenueCat.
    typealias Fetch = @Sendable (_ url: String, _ secretKey: String) async throws -> (status: UInt, body: Data)

    let secretKey: String?
    let kv: KeyValueStore
    let logger: Logger
    let now: @Sendable () -> Date
    let fetch: Fetch

    init(secretKey: String?, kv: KeyValueStore, logger: Logger,
         now: @escaping @Sendable () -> Date = { Date() }, fetch: @escaping Fetch) {
        self.secretKey = secretKey
        self.kv = kv
        self.logger = logger
        self.now = now
        self.fetch = fetch
    }

    static func cacheKey(appUserID: String) -> String {
        let digest = SHA256.hash(data: Data(appUserID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "RevenueCatPro-\(digest.prefix(32))"
    }

    func check(appUserID: String?) async -> ProEntitlementCheck {
        guard let appUserID, !appUserID.isEmpty, appUserID.count <= 200 else { return .unverified }
        let cacheKey = Self.cacheKey(appUserID: appUserID)
        if let cached = try? await kv.getString(cacheKey) {
            return ProEntitlementCheck(isPro: cached == "1", verified: true)
        }
        guard let secretKey, !secretKey.isEmpty else {
            logger.warning("REVENUECAT_SECRET_KEY is not set: custom alerts treat every install as free")
            return .unverified
        }
        // RFC 3986 unreserved only: anonymous IDs carry "$" and ":".
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = appUserID.addingPercentEncoding(withAllowedCharacters: unreserved) ?? appUserID
        do {
            let (status, body) = try await fetch(Self.baseURL + encoded, secretKey)
            guard (200..<300).contains(status) else {
                logger.warning("RevenueCat subscriber lookup failed with HTTP \(status): treating install as free")
                return .unverified
            }
            guard let isPro = Self.hasActiveEntitlement(body: body, now: now()) else {
                logger.warning("RevenueCat subscriber response didn't parse: treating install as free")
                return .unverified
            }
            try? await kv.setString(cacheKey, value: isPro ? "1" : "0", ttl: Self.cacheTTL)
            return ProEntitlementCheck(isPro: isPro, verified: true)
        } catch {
            logger.warning("RevenueCat subscriber lookup failed: \(error). Treating install as free")
            return .unverified
        }
    }

    /// Whether the v1 subscriber body has an active `Pro` entitlement: no expiry
    /// (lifetime) or one in the future, or a billing grace period still running. Nil
    /// when the body isn't a subscriber response.
    static func hasActiveEntitlement(body: Data, now: Date) -> Bool? {
        struct Response: Decodable {
            struct Subscriber: Decodable { let entitlements: [String: Entitlement]? }
            struct Entitlement: Decodable {
                let expires_date: String?
                let grace_period_expires_date: String?
            }
            let subscriber: Subscriber
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: body) else { return nil }
        guard let entitlement = response.subscriber.entitlements?[entitlementID] else { return false }
        guard let expires = entitlement.expires_date else { return true }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func parse(_ raw: String?) -> Date? { raw.flatMap { formatter.date(from: $0) ?? fractional.date(from: $0) } }
        if let date = parse(expires), date > now { return true }
        if let grace = parse(entitlement.grace_period_expires_date), grace > now { return true }
        // An expiry we can't read: don't grant.
        return false
    }
}

extension RevenueCatEntitlementChecker {
    /// The production checker: Vapor's HTTP client, key from the environment.
    static func live(app: Application) -> RevenueCatEntitlementChecker {
        let client = app.client
        return RevenueCatEntitlementChecker(
            secretKey: Environment.get("REVENUECAT_SECRET_KEY"),
            kv: app.kv,
            logger: Logger(label: "com.sportscal.revenuecat"),
            fetch: { url, key in
                let response = try await client.get(URI(string: url)) { request in
                    request.headers.bearerAuthorization = BearerAuthorization(token: key)
                    request.headers.replaceOrAdd(name: .accept, value: "application/json")
                    request.timeout = .seconds(8)
                }
                let body = response.body.map { Data($0.readableBytesView) } ?? Data()
                return (response.status.code, body)
            }
        )
    }
}

struct ProEntitlementCheckerKey: StorageKey {
    typealias Value = ProEntitlementChecking
}

extension Application {
    /// Tests swap in a stub; production builds the RevenueCat checker on first use.
    var proEntitlements: ProEntitlementChecking {
        get { storage[ProEntitlementCheckerKey.self] ?? RevenueCatEntitlementChecker.live(app: self) }
        set { storage[ProEntitlementCheckerKey.self] = newValue }
    }
}
