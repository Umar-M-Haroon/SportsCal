import Foundation
import Vapor

/// Lightweight in-process counters for push / live-activity delivery health.
/// Reset on server restart — not intended as long-term telemetry, but gives the
/// admin dashboard a live view of "is anything actually going out?" without
/// needing to tail logs.
///
/// A proper swift-metrics integration would emit these as Prometheus-compatible
/// counters/histograms; this implementation is deliberately narrow so we don't
/// add a dependency for observability that's only read from one endpoint.
actor PushMetrics {
    struct Snapshot: Content, Sendable {
        var sent: [String: Int]
        var errors: [String: Int]
        var tokenCleanup: [String: Int]
        var dedupHit: Int
        var dedupMiss: Int
        var scanProd: Int
        var scanSandbox: Int
        var lastRunSeconds: Double
        var lastUpdated: String
    }

    private var sent: [String: Int] = [:]            // keyed by kind: update, end, start
    private var errors: [String: Int] = [:]          // keyed by APNSSendError.Reason.rawValue
    private var tokenCleanup: [String: Int] = [:]    // keyed by reason: unregistered, badDeviceToken
    private var dedupHit: Int = 0
    private var dedupMiss: Int = 0
    private var scanProd: Int = 0
    private var scanSandbox: Int = 0
    private var lastRunSeconds: Double = 0
    private var lastUpdated: Date = .distantPast

    func recordSend(kind: APNSSendResult.Kind) {
        sent[String(describing: kind), default: 0] += 1
        lastUpdated = Date()
    }

    func recordError(_ reason: APNSSendError.Reason) {
        errors[reason.rawValue, default: 0] += 1
        lastUpdated = Date()
    }

    func recordCleanup(reason: String) {
        tokenCleanup[reason, default: 0] += 1
        lastUpdated = Date()
    }

    func recordDedup(hit: Bool) {
        if hit { dedupHit += 1 } else { dedupMiss += 1 }
        lastUpdated = Date()
    }

    /// Per-tick APNS keyspace cardinality — the early-warning signal for the
    /// scan/process cliff. Watch this climb as registrations grow.
    func recordScanSize(prod: Int, sandbox: Int) {
        scanProd = prod
        scanSandbox = sandbox
        lastUpdated = Date()
    }

    /// Wall-clock duration of the last APNS job run. Should stay well under the
    /// 50s JobLock TTL (target < 40s).
    func recordDuration(_ seconds: Double) {
        lastRunSeconds = seconds
        lastUpdated = Date()
    }

    func snapshot() -> Snapshot {
        let formatter = ISO8601DateFormatter()
        return Snapshot(
            sent: sent,
            errors: errors,
            tokenCleanup: tokenCleanup,
            dedupHit: dedupHit,
            dedupMiss: dedupMiss,
            scanProd: scanProd,
            scanSandbox: scanSandbox,
            lastRunSeconds: lastRunSeconds,
            lastUpdated: formatter.string(from: lastUpdated)
        )
    }
}

struct PushMetricsKey: StorageKey {
    typealias Value = PushMetrics
}

extension Application {
    var pushMetrics: PushMetrics {
        if let existing = storage[PushMetricsKey.self] { return existing }
        let created = PushMetrics()
        storage[PushMetricsKey.self] = created
        return created
    }
}
