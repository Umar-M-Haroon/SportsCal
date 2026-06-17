import Foundation
import Vapor
import APNSCore
import VaporAPNS

/// Alert content attached to a Live Activity update so iOS surfaces a banner +
/// plays the notification sound/haptic — i.e. the phone vibrates on the lock
/// screen when a goal is scored. A plain (non-alerting) update only redraws the
/// activity silently.
struct LiveActivityAlert: Sendable, Equatable {
    let title: String
    let body: String
}

/// Recorded metadata for a push send attempt. Tests use this to assert that the
/// right payload went to the right device token without touching real APNS.
struct APNSSendResult: Sendable {
    enum Kind: Sendable { case update, end, start, alert }
    let kind: Kind
    let deviceToken: String
    let appID: String
    let timestamp: Int
    let topic: String?
}

/// Structured error type surfaced through the seam so tests can simulate specific
/// APNS failure modes without constructing a real `APNSError`. Production code
/// only branches on `isUnregistered` / `isBadDeviceToken` today, so that's all we
/// expose for now; extend as new branches get added.
struct APNSSendError: Error, Sendable, Equatable {
    enum Reason: String, Sendable, Equatable {
        case unregistered
        case badDeviceToken
        case tooManyRequests
        case payloadTooLarge
        case internalServerError
        case tokenAuthFailure
        case other
    }
    let reason: Reason
    let underlying: String?

    var isUnregistered: Bool { reason == .unregistered }
    var isBadDeviceToken: Bool { reason == .badDeviceToken }
    /// Either `.unregistered` or `.badDeviceToken` — both are terminal signals
    /// that the token is permanently dead and should be cleaned up from storage.
    var isStaleToken: Bool { isUnregistered || isBadDeviceToken }
}

extension APNSSendError {
    /// Normalize a thrown error (real APNSError or anything else) into our domain type.
    static func from(_ error: Error) -> APNSSendError {
        if let apnsError = error as? APNSError {
            switch apnsError.reason {
            case .unregistered: return .init(reason: .unregistered, underlying: "\(apnsError)")
            case .badDeviceToken: return .init(reason: .badDeviceToken, underlying: "\(apnsError)")
            case .tooManyRequests: return .init(reason: .tooManyRequests, underlying: "\(apnsError)")
            case .payloadTooLarge: return .init(reason: .payloadTooLarge, underlying: "\(apnsError)")
            case .internalServerError: return .init(reason: .internalServerError, underlying: "\(apnsError)")
            case .invalidProviderToken, .expiredProviderToken, .missingProviderToken:
                return .init(reason: .tokenAuthFailure, underlying: "\(apnsError)")
            default:
                return .init(reason: .other, underlying: "\(apnsError)")
            }
        }
        return .init(reason: .other, underlying: "\(error)")
    }
}

/// Thin abstraction over the two APNS send shapes our code actually uses:
/// live-activity update/end, and push-to-start. Tests swap in `MockAPNSClient`
/// to record calls and simulate errors.
///
/// `environment` is per-call, not per-instance: a single server may serve both
/// sandbox tokens (Xcode dev devices) and production tokens (TestFlight / App
/// Store) at the same time, and each token must be sent to its own APNS gateway.
protocol APNSSending: Sendable {
    func sendLiveActivityUpdate(
        deviceToken: String,
        appID: String,
        contentState: ContentState,
        isFinal: Bool,
        alert: LiveActivityAlert?,
        timestamp: Int,
        environment: APNSEnvironment
    ) async throws -> APNSSendResult

    func sendPushToStart(
        deviceToken: String,
        appID: String,
        attributes: LiveSportAttributes,
        contentState: ContentState,
        alertTitle: String,
        alertBody: String,
        timestamp: Int,
        environment: APNSEnvironment
    ) async throws -> APNSSendResult
}

/// Production implementation that delegates to `VaporAPNS`. Picks the APNS
/// gateway per call from the supplied `environment` so a single server can
/// dispatch both sandbox and production tokens.
final class VaporAPNSSending: APNSSending {
    let application: Application

    init(application: Application) {
        self.application = application
    }

    private func client(for environment: APNSEnvironment) async -> APNSGenericClient {
        switch environment {
        case .sandbox: return await application.apns.client(.development)
        case .production: return await application.apns.client(.production)
        }
    }

    func sendLiveActivityUpdate(
        deviceToken: String,
        appID: String,
        contentState: ContentState,
        isFinal: Bool,
        alert: LiveActivityAlert?,
        timestamp: Int,
        environment: APNSEnvironment
    ) async throws -> APNSSendResult {
        let client = await client(for: environment)
        let notification = APNSLiveActivityNotification(
            expiration: isFinal ? .none : .immediately,
            priority: .immediately,
            appID: appID,
            contentState: contentState,
            event: isFinal ? .end : .update,
            alert: alert.map {
                APNSAlertNotificationContent(title: .raw($0.title), body: .raw($0.body))
            },
            timestamp: timestamp
        )
        do {
            try await client.sendLiveActivityNotification(notification, deviceToken: deviceToken)
            return APNSSendResult(
                kind: isFinal ? .end : .update,
                deviceToken: deviceToken,
                appID: appID,
                timestamp: timestamp,
                topic: nil
            )
        } catch {
            throw APNSSendError.from(error)
        }
    }

    func sendPushToStart(
        deviceToken: String,
        appID: String,
        attributes: LiveSportAttributes,
        contentState: ContentState,
        alertTitle: String,
        alertBody: String,
        timestamp: Int,
        environment: APNSEnvironment
    ) async throws -> APNSSendResult {
        let client = await client(for: environment)
        let notification = APNSStartLiveActivityNotification(
            expiration: .immediately,
            priority: .immediately,
            appID: appID,
            contentState: contentState,
            timestamp: timestamp,
            attributes: attributes,
            attributesType: "LiveSportActivityAttributes",
            alert: APNSAlertNotificationContent(
                title: .raw(alertTitle),
                body: .raw(alertBody)
            )
        )
        do {
            // collapseID = eventID coalesces any APNS retry/redelivery into the
            // same Live Activity instead of spawning a duplicate on the device.
            try await client.sendStartLiveActivityNotification(
                notification,
                deviceToken: deviceToken,
                collapseID: attributes.eventID
            )
            return APNSSendResult(
                kind: .start,
                deviceToken: deviceToken,
                appID: appID,
                timestamp: timestamp,
                topic: nil
            )
        } catch {
            throw APNSSendError.from(error)
        }
    }
}

struct APNSSendingKey: StorageKey {
    typealias Value = APNSSending
}

extension Application {
    var apnsSending: APNSSending {
        get { storage[APNSSendingKey.self] ?? VaporAPNSSending(application: self) }
        set { storage[APNSSendingKey.self] = newValue }
    }
}

extension Request {
    var apnsSending: APNSSending { application.apnsSending }
}
