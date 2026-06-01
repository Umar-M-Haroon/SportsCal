//
//  ActivityModel.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 11/1/22.
//

import Foundation
import SportsCalModel
import Vapor
import APNSCore
import Crypto

public struct ContentState: Codable, Hashable {
    var homeScore: Int
    var awayScore: Int
    var status: String?
    var progress: String?
    var lastPlay: String? = nil

    /// Deterministic content hash, safe to share across processes. Swift's
    /// `Hashable.hashValue` uses a per-process random seed and cannot be used
    /// as a Redis claim key.
    func stableHash() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct LiveSportAttributes: Codable, Sendable {
    var homeTeam: String
    var awayTeam: String
    var eventID: String
    /// Optional league-style short abbreviations (e.g. "PHI", "BOS") — when
    /// available, the iOS widget uses these in the Dynamic Island compact and
    /// minimal slots where raster team logos get tinted to silhouettes. Defaults
    /// to nil so existing code paths and the iOS Codable decoder both stay happy.
    var homeTeamShort: String? = nil
    var awayTeamShort: String? = nil
}

/// Which APNS gateway a given device token belongs to. Sandbox tokens come
/// from Xcode-built dev devices (development entitlement); production tokens
/// come from TestFlight / App Store builds. The two are not interchangeable —
/// a token sent to the wrong gateway returns `BadDeviceToken`.
enum APNSEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

struct PushToStartRegistration: Codable, Content {
    var token: String
    var favorites: [String]
    var eventIDs: [String]? = nil
}

/// One blob per install. Persisting token+favorites+events together means a
/// token rotation just overwrites the install's record; no orphan keys, and
/// the ESPNFetchJob scan iterates over installs instead of having to merge
/// two per-token keyspaces (favorites vs eventIDs) into one logical entry.
struct PushToStartInstall: Codable {
    var installID: String
    var token: String
    var favorites: [String]
    var eventIDs: [String]
    var environment: APNSEnvironment
}

/// Wire format for `POST /liveActivity` registration. The token lived in the URL
/// path on a prior `GET /liveActivity/:token/:eventID` route; moving it into a
/// POST body keeps the device token out of access logs (it's a capability —
/// useless without the APNS auth key, but still user-identifying).
struct LiveActivityRegistration: Codable, Content {
    var token: String
    var eventID: String
    var homeTeam: String? = nil
    var awayTeam: String? = nil
}

/// Wire format for the DELETE counterparts of the two POST routes above. Token
/// in the body keeps it out of access logs, same as the POSTs.
struct DeregisterRequest: Codable, Content {
    var token: String
}

/// Stored in Redis for each APNS-{token} registration.
/// Includes team names so the APNSJob can match by team even when event IDs differ.
/// `environment` records which APNS gateway issued the token so jobs can route
/// the push correctly even on a server that handles both sandbox and production.
struct APNSRegistration: Codable {
    var eventID: String
    var homeTeam: String? = nil
    var awayTeam: String? = nil
    var environment: APNSEnvironment? = nil
}

// MARK: - APNSClientProtocol extension for push-to-start
extension APNSClientProtocol {
    @discardableResult
    @inlinable
    public func sendStartLiveActivityNotification<Attributes: Encodable & Sendable, ContentState: Encodable & Sendable>(
        _ notification: APNSStartLiveActivityNotification<Attributes, ContentState>,
        deviceToken: String,
        collapseID: String? = nil
    ) async throws -> APNSResponse {
        let request = APNSRequest(
            message: notification,
            deviceToken: deviceToken,
            pushType: .liveactivity,
            expiration: notification.expiration,
            priority: notification.priority,
            apnsID: notification.apnsID,
            topic: notification.topic,
            collapseID: collapseID
        )
        return try await send(request)
    }
}

