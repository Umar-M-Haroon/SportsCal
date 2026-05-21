import Foundation
@testable import App

/// Records every push attempt and lets tests stage errors per device token.
/// Thread-safe. Use `recorded` to assert payload/count; use `setError(for:)`
/// to simulate APNS failure modes (unregistered, rate-limited, etc).
final class MockAPNSClient: APNSSending, @unchecked Sendable {
    struct RecordedSend: Sendable, Equatable {
        enum Kind: String, Sendable, Equatable { case update, end, start }
        let kind: Kind
        let deviceToken: String
        let appID: String
        let contentState: ContentState?
        let attributes: LiveSportAttributes?
        let alertTitle: String?
        let alertBody: String?
        let timestamp: Int
        let environment: APNSEnvironment
    }

    private let lock = NSLock()
    private var _recorded: [RecordedSend] = []
    private var errors: [String: [APNSSendError]] = [:] // token → FIFO queue of errors
    private var globalError: APNSSendError?

    var recorded: [RecordedSend] {
        lock.lock()
        defer { lock.unlock() }
        return _recorded
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _recorded.removeAll()
        errors.removeAll()
        globalError = nil
    }

    /// Queue one or more errors for a specific device token. Consumed FIFO — the
    /// next `sendX` to this token throws the first queued error, then behaves
    /// normally on subsequent calls.
    func queueError(_ error: APNSSendError, for token: String, times: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        errors[token, default: []].append(contentsOf: Array(repeating: error, count: times))
    }

    /// Force every send to throw this error until cleared via `reset()` or `clearGlobalError()`.
    func setGlobalError(_ error: APNSSendError) {
        lock.lock()
        defer { lock.unlock() }
        globalError = error
    }

    func clearGlobalError() {
        lock.lock()
        defer { lock.unlock() }
        globalError = nil
    }

    func recordedCount(for token: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _recorded.filter { $0.deviceToken == token }.count
    }

    // MARK: - APNSSending

    func sendLiveActivityUpdate(
        deviceToken: String,
        appID: String,
        contentState: ContentState,
        isFinal: Bool,
        timestamp: Int,
        environment: APNSEnvironment
    ) async throws -> APNSSendResult {
        try consumeErrorIfAny(for: deviceToken)
        let record = RecordedSend(
            kind: isFinal ? .end : .update,
            deviceToken: deviceToken,
            appID: appID,
            contentState: contentState,
            attributes: nil,
            alertTitle: nil,
            alertBody: nil,
            timestamp: timestamp,
            environment: environment
        )
        append(record)
        return APNSSendResult(
            kind: isFinal ? .end : .update,
            deviceToken: deviceToken,
            appID: appID,
            timestamp: timestamp,
            topic: nil
        )
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
        try consumeErrorIfAny(for: deviceToken)
        let record = RecordedSend(
            kind: .start,
            deviceToken: deviceToken,
            appID: appID,
            contentState: contentState,
            attributes: attributes,
            alertTitle: alertTitle,
            alertBody: alertBody,
            timestamp: timestamp,
            environment: environment
        )
        append(record)
        return APNSSendResult(
            kind: .start,
            deviceToken: deviceToken,
            appID: appID,
            timestamp: timestamp,
            topic: nil
        )
    }

    // MARK: - Internals

    private func append(_ record: RecordedSend) {
        lock.lock()
        defer { lock.unlock() }
        _recorded.append(record)
    }

    private func consumeErrorIfAny(for token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let global = globalError {
            throw global
        }
        if var queue = errors[token], !queue.isEmpty {
            let next = queue.removeFirst()
            errors[token] = queue
            throw next
        }
    }
}

// Equatable for LiveSportAttributes + ContentState so tests can assert on
// recorded values directly. Both are already Codable in production; the extra
// conformance lives here in tests so production types stay minimal.
extension LiveSportAttributes: Equatable {
    public static func == (lhs: LiveSportAttributes, rhs: LiveSportAttributes) -> Bool {
        lhs.homeTeam == rhs.homeTeam && lhs.awayTeam == rhs.awayTeam && lhs.eventID == rhs.eventID
    }
}
