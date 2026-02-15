//
//  APNSJob.swift
//
//
//  Created by Umar Haroon on 11/1/22.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import VaporAPNS
import APNSCore
import NIOCore
import Logging

struct APNSJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.apns-job")

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development

        guard context.application.storage[APNSConfiguredKey.self] == true else { return }

        let keyPrefix = isDebug ? "debug-APNS-" : "APNS-"

        guard let keys = try await context.application.redis.send(command: "keys", with: ["\(keyPrefix)*".convertedToRESPValue()])
            .array?
            .compactMap({ $0.string })
            .map({ RedisKey($0) }),
              !keys.isEmpty else { return }

        let liveScore = try await context.application.redis.get(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: isDebug), asJSON: LiveScore.self)

        var events = liveScore?.mlb?.events ?? []
        events.append(contentsOf: liveScore?.nfl?.events ?? [])
        events.append(contentsOf: liveScore?.nba?.events ?? [])
        events.append(contentsOf: liveScore?.soccer?.events ?? [])
        events.append(contentsOf: liveScore?.nhl?.events ?? [])
        events.append(contentsOf: liveScore?.golf?.events ?? [])
        events.append(contentsOf: liveScore?.tennis?.events ?? [])
        events.append(contentsOf: liveScore?.racing?.events ?? [])

        let eventIDs = try await context.application.redis.mget(keys).get()
        let apnsClient = isDebug
            ? await context.application.apns.client(.development)
            : await context.application.apns.client(.production)

        for (index, key) in keys.enumerated() {
            guard let eventID = eventIDs[index].string,
                  let event = events.first(where: { $0.idEvent == eventID }),
                  let homeScore = Int(event.intHomeScore ?? ""),
                  let awayScore = Int(event.intAwayScore ?? "") else { continue }

            let tokenString = String(key.rawValue.split(separator: "-").last!)

            if !event.hasDoneStatus {
                let contentState = ContentState(homeScore: homeScore, awayScore: awayScore, status: event.strStatus, progress: event.strProgress)
                let savedState = try await context.application.redis.get(RedisEndpoint.eventState(event.id).getValue(isDebug: isDebug), asJSON: ContentState.self)
                if savedState != contentState {
                    try await context.application.redis.setex(RedisEndpoint.eventState(event.id).getValue(isDebug: isDebug), toJSON: contentState, expirationInSeconds: 60 * 60 * 8).get()
                    do {
                        try await apnsClient.sendLiveActivityNotification(
                            APNSLiveActivityNotification(
                                expiration: .immediately,
                                priority: .immediately,
                                appID: "com.KomodoLLC.SportsCal",
                                contentState: contentState,
                                event: .update,
                                timestamp: Int(Date().timeIntervalSince1970)
                            ),
                            deviceToken: tokenString
                        )
                    } catch {
                        Self.logger.error("Failed to send APNS update for \(event.id): \(error)")
                        if let apnsError = error as? APNSError, apnsError.reason == .unregistered {
                            _ = try await context.application.redis.delete([key]).get()
                        }
                    }
                }
            } else {
                Self.logger.info("Ending live activity for game \(key)")
                let contentState = ContentState(homeScore: homeScore, awayScore: awayScore, status: event.strStatus, progress: event.strProgress)
                do {
                    try await apnsClient.sendLiveActivityNotification(
                        APNSLiveActivityNotification(
                            expiration: .none,
                            priority: .immediately,
                            appID: "com.KomodoLLC.SportsCal",
                            contentState: contentState,
                            event: .end,
                            timestamp: Int(Date().timeIntervalSince1970)
                        ),
                        deviceToken: tokenString
                    )
                } catch {
                    Self.logger.error("Failed to send APNS end for \(event.id): \(error)")
                }
                let contentStateToDelete = RedisEndpoint.eventState(event.id).getValue(isDebug: isDebug)
                _ = try await context.application.redis.delete([key, contentStateToDelete]).get()
            }
        }
    }
}
