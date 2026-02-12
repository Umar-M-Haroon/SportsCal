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

public struct ContentState: Codable, Hashable {
    var homeScore: Int
    var awayScore: Int
    var status: String?
    var progress: String?
}

public struct LiveSportAttributes: Codable, Sendable {
    var homeTeam: String
    var awayTeam: String
    var eventID: String
}

struct PushToStartRegistration: Codable, Content {
    var token: String
    var favorites: [String]
    var eventIDs: [String]?
}

// MARK: - APNSClientProtocol extension for push-to-start
extension APNSClientProtocol {
    @discardableResult
    @inlinable
    public func sendStartLiveActivityNotification<Attributes: Encodable & Sendable, ContentState: Encodable & Sendable>(
        _ notification: APNSStartLiveActivityNotification<Attributes, ContentState>,
        deviceToken: String
    ) async throws -> APNSResponse {
        let request = APNSRequest(
            message: notification,
            deviceToken: deviceToken,
            pushType: .liveactivity,
            expiration: notification.expiration,
            priority: notification.priority,
            apnsID: notification.apnsID,
            topic: notification.topic,
            collapseID: nil
        )
        return try await send(request)
    }
}

