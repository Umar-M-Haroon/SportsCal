import Foundation
import Vapor
import APNSCore
import VaporAPNS

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
protocol APNSSending: Sendable {
    func sendLiveActivityUpdate(
        deviceToken: String,
        appID: String,
        contentState: ContentState,
        isFinal: Bool,
        timestamp: Int
    ) async throws -> APNSSendResult

    func sendPushToStart(
        deviceToken: String,
        appID: String,
        attributes: LiveSportAttributes,
        contentState: ContentState,
        alertTitle: String,
        alertBody: String,
        timestamp: Int
    ) async throws -> APNSSendResult
}

/// Production implementation that delegates to `VaporAPNS`. Chooses between
/// `.development` and `.production` APNS environments based on `Application.environment`.
final class VaporAPNSSending: APNSSending {
    let application: Application

    init(application: Application) {
        self.application = application
    }

    private var client: APNSGenericClient {
        get async {
            application.environment == .development
                ? await application.apns.client(.development)
                : await application.apns.client(.production)
        }
    }

    func sendLiveActivityUpdate(
        deviceToken: String,
        appID: String,
        contentState: ContentState,
        isFinal: Bool,
        timestamp: Int
    ) async throws -> APNSSendResult {
        let client = await client
        let notification = APNSLiveActivityNotification(
            expiration: isFinal ? .none : .immediately,
            priority: .immediately,
            appID: appID,
            contentState: contentState,
            event: isFinal ? .end : .update,
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
        timestamp: Int
    ) async throws -> APNSSendResult {
        let client = await client
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
            try await client.sendStartLiveActivityNotification(notification, deviceToken: deviceToken)
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
