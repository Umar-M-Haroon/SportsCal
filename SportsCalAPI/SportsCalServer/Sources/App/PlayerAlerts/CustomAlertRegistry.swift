//
//  CustomAlertRegistry.swift
//  App
//
//  Where custom alert registrations live, and how `CustomAlertJob` finds the few
//  that matter for the games on right now without reading them all.
//
//  Redis (every key `debug-`-prefixed for sandbox tokens):
//  - `CustomAlertDevice-{install}`: the install's `CustomAlertDevice` (token, accepted
//    rules, verified Pro state). 30-day TTL, refreshed by each registration.
//  - `CustomAlertScope-{scope}`: SET of device keys with a rule in that scope. A scope
//    is `team:{sport}:{teamID}` (player rules, and situations for one team) or
//    `sport:{sport}` (situations for every game of the sport's main league).
//  - `CustomAlertScopes`: SET of the scopes in use, so the job only touches the scope
//    sets of teams that are actually playing.
//  Expired devices are pruned from scope sets when the job finds them gone.
//

import Foundation
import Vapor
import SportsCalModel

/// One install's custom alert registration.
struct CustomAlertDevice: Codable, Equatable, Sendable {
    var installID: String
    var token: String
    var revenueCatAppUserID: String?
    /// The rules accepted at registration (the free cap already applied when not Pro).
    var rules: [AlertRule]
    /// Pro as RevenueCat said at `proCheckedAt`. The job re-checks a Pro device once
    /// that's older than `proRecheckInterval`, and caps it if Pro has lapsed.
    var isPro: Bool
    var proCheckedAt: Date

    static let ttl: TimeInterval = 30 * 24 * 60 * 60
    static let proRecheckInterval: TimeInterval = 6 * 60 * 60

    static func key(installID: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "CustomAlertDevice-\(installID)"
    }

    /// The index scopes this device's rules sit in.
    var scopes: Set<String> {
        Set(rules.compactMap(CustomAlertIndex.scope(for:)))
    }
}

enum CustomAlertIndex {
    static func scope(for rule: AlertRule) -> String? {
        if let teamID = rule.teamID { return teamScope(sport: rule.sport, teamID: teamID) }
        return rule.kind == .gameSituation ? sportScope(rule.sport) : nil
    }

    static func teamScope(sport: SportType, teamID: String) -> String { "team:\(sport.rawValue):\(teamID)" }
    static func sportScope(_ sport: SportType) -> String { "sport:\(sport.rawValue)" }

    static func scopesKey(sandbox: Bool) -> String { (sandbox ? "debug-" : "") + "CustomAlertScopes" }
    static func scopeKey(_ scope: String, sandbox: Bool) -> String { (sandbox ? "debug-" : "") + "CustomAlertScope-\(scope)" }

    static func add(_ deviceKey: String, to scopes: Set<String>, sandbox: Bool, kv: KeyValueStore) async {
        guard !scopes.isEmpty, let sets = kv as? RedisSetStore else { return }
        for scope in scopes {
            try? await sets.setAdd(scopeKey(scope, sandbox: sandbox), members: [deviceKey])
        }
        // After the scope sets, so the job never sees a scope whose set lacks the device.
        try? await sets.setAdd(scopesKey(sandbox: sandbox), members: Array(scopes))
    }

    static func remove(_ deviceKey: String, from scopes: Set<String>, sandbox: Bool, kv: KeyValueStore) async {
        guard !scopes.isEmpty, let sets = kv as? RedisSetStore else { return }
        for scope in scopes {
            try? await sets.setRemove(scopeKey(scope, sandbox: sandbox), members: [deviceKey])
        }
    }

    static func scopesInUse(sandbox: Bool, kv: KeyValueStore) async -> Set<String> {
        guard let sets = kv as? RedisSetStore else { return [] }
        return Set((try? await sets.setMembers(scopesKey(sandbox: sandbox))) ?? [])
    }

    static func devices(in scope: String, sandbox: Bool, kv: KeyValueStore) async -> [String] {
        guard let sets = kv as? RedisSetStore else { return [] }
        return (try? await sets.setMembers(scopeKey(scope, sandbox: sandbox))) ?? []
    }
}

/// Per-game mutes from the "Mute this player for this game" action, 24h.
enum CustomAlertMute {
    static let ttl: TimeInterval = 24 * 60 * 60

    static func athleteKey(installID: String, eventID: String, athleteID: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "CustomAlertMute-\(installID)-\(eventID)-athlete-\(athleteID)"
    }

    static func ruleKey(installID: String, eventID: String, ruleID: String, sandbox: Bool) -> String {
        (sandbox ? "debug-" : "") + "CustomAlertMute-\(installID)-\(eventID)-rule-\(ruleID)"
    }
}

enum CustomAlertRegistry {
    struct InvalidRegistration: Error {}

    /// Most rules a request may carry before validation (the Pro ceiling is lower).
    static let maxRequestRules = 200

    /// `POST /notifications/custom`: verify Pro, apply the tier's cap, store the
    /// accepted rules and move the device between scope sets.
    static func register(
        _ registration: CustomAlertRegistration,
        installID: String,
        sandbox: Bool,
        kv: KeyValueStore,
        entitlements: ProEntitlementChecking,
        now: Date
    ) async throws -> CustomAlertRegistrationResponse {
        guard !registration.token.isEmpty, registration.token.count <= 200,
              registration.rules.count <= maxRequestRules else { throw InvalidRegistration() }
        let check = await entitlements.check(appUserID: registration.revenueCatAppUserID)
        let limits = CustomAlertLimits.limits(isPro: check.isPro)
        let (accepted, dropped) = limits.apply(to: registration.rules.map(trimmed))
        let response = CustomAlertRegistrationResponse(rules: accepted, droppedRuleIDs: dropped, isPro: check.isPro, limits: limits)

        let key = CustomAlertDevice.key(installID: installID, sandbox: sandbox)
        let previous = try? await kv.getJSON(key, as: CustomAlertDevice.self)
        guard !accepted.isEmpty else {
            _ = try? await kv.delete([key])
            await CustomAlertIndex.remove(key, from: previous?.scopes ?? [], sandbox: sandbox, kv: kv)
            return response
        }
        let device = CustomAlertDevice(
            installID: installID, token: registration.token,
            revenueCatAppUserID: registration.revenueCatAppUserID.map { String($0.prefix(200)) },
            rules: accepted, isPro: check.isPro, proCheckedAt: now
        )
        try await kv.setJSON(key, value: device, ttl: CustomAlertDevice.ttl)
        let scopes = device.scopes
        await CustomAlertIndex.add(key, to: scopes, sandbox: sandbox, kv: kv)
        await CustomAlertIndex.remove(key, from: (previous?.scopes ?? []).subtracting(scopes), sandbox: sandbox, kv: kv)
        return response
    }

    /// `DELETE /notifications/custom`.
    static func unregister(installID: String, sandbox: Bool, kv: KeyValueStore) async {
        let key = CustomAlertDevice.key(installID: installID, sandbox: sandbox)
        let previous = try? await kv.getJSON(key, as: CustomAlertDevice.self)
        _ = try? await kv.delete([key])
        await CustomAlertIndex.remove(key, from: previous?.scopes ?? [], sandbox: sandbox, kv: kv)
    }

    /// `POST /notifications/custom/mute`.
    static func mute(_ request: CustomAlertMuteRequest, installID: String, sandbox: Bool, kv: KeyValueStore) async throws {
        guard !request.eventID.isEmpty, request.eventID.count <= 64 else { throw InvalidRegistration() }
        let key: String
        if let athleteID = request.athleteID, !athleteID.isEmpty, athleteID.count <= 32 {
            key = CustomAlertMute.athleteKey(installID: installID, eventID: request.eventID, athleteID: athleteID, sandbox: sandbox)
        } else if let ruleID = request.ruleID, !ruleID.isEmpty, ruleID.count <= 64 {
            key = CustomAlertMute.ruleKey(installID: installID, eventID: request.eventID, ruleID: ruleID, sandbox: sandbox)
        } else {
            throw InvalidRegistration()
        }
        try await kv.setString(key, value: "1", ttl: CustomAlertMute.ttl)
    }

    /// Bounds the free-text fields a client sends.
    private static func trimmed(_ rule: AlertRule) -> AlertRule {
        var rule = rule
        rule.athleteName = rule.athleteName.map { String($0.prefix(80)) }
        if let types = rule.playTypes {
            var seen = Set<AlertPlayType>()
            rule.playTypes = types.filter { seen.insert($0).inserted }
        }
        return rule
    }
}
