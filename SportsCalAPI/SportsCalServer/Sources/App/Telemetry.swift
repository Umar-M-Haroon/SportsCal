import Foundation
import Vapor

/// Severity for a telemetry event. Maps 1:1 onto swift-log levels today and onto
/// Sentry levels later, so a future `SentryTelemetry` is a drop-in with no
/// call-site churn.
enum TelemetryLevel: String, Sendable {
    case info
    case warning
    case error
}

/// Structured observability seam for operational events — push delivery,
/// rate-limit rejections, registration outcomes. Deliberately tiny: one `record`
/// verb carrying an event name, a level, and small string fields. Every backend
/// we care about can represent that shape: a structured log line, a Redis
/// counter, or a Sentry event/breadcrumb.
///
/// `Application.telemetry` fans out (see `CompositeTelemetry`) to:
///   - `LoggingTelemetry`  — structured swift-log lines (greppable now).
///   - `RedisTelemetry`    — per-day counters that survive restarts/deploys,
///                           unlike the in-memory `PushMetrics`.
///
/// To add Sentry later: implement this protocol over the Sentry SDK
/// (`SentrySDK.capture` for `.error`, `addBreadcrumb` for the rest) and append
/// it to the composite in `Application.telemetry`. No existing call site changes.
protocol Telemetry: Sendable {
    func record(_ event: String, level: TelemetryLevel, fields: [String: String]) async
}

extension Telemetry {
    func info(_ event: String, _ fields: [String: String] = [:]) async {
        await record(event, level: .info, fields: fields)
    }
    func warning(_ event: String, _ fields: [String: String] = [:]) async {
        await record(event, level: .warning, fields: fields)
    }
    func error(_ event: String, _ fields: [String: String] = [:]) async {
        await record(event, level: .error, fields: fields)
    }
}

/// Emits each event as a structured swift-log line. The event name is the
/// message; fields become log metadata so they stay machine-parseable.
struct LoggingTelemetry: Telemetry {
    let logger: Logger

    func record(_ event: String, level: TelemetryLevel, fields: [String: String]) async {
        let metadata: Logger.Metadata = fields.reduce(into: [:]) { acc, pair in
            acc[pair.key] = .string(pair.value)
        }
        switch level {
        case .info: logger.info("\(event)", metadata: metadata)
        case .warning: logger.warning("\(event)", metadata: metadata)
        case .error: logger.error("\(event)", metadata: metadata)
        }
    }
}

/// Persists a per-day counter per event so questions like "how many push sends /
/// rate-limit rejections happened today (and yesterday)?" survive restarts and
/// deploys. Key shape: `telemetry:{event}:{epochDay}` → INCR with a 30-day TTL.
///
/// Epoch-day bucketing (floor(now / 86400)) avoids any timezone/formatter
/// surprises and sorts naturally. Fail-open by construction: `increment` is
/// best-effort and any throw is swallowed — telemetry must never break a request
/// or a job.
struct RedisTelemetry: Telemetry {
    let kv: KeyValueStore
    let clock: AppClock

    /// Retain ~30 days of daily counters; enough for week-over-week comparison
    /// without unbounded key growth.
    static let retention: TimeInterval = 60 * 60 * 24 * 30

    func record(_ event: String, level: TelemetryLevel, fields: [String: String]) async {
        let day = Int(clock.now.timeIntervalSince1970) / 86_400
        let key = "telemetry:\(event):\(day)"
        _ = try? await kv.increment(key, ttl: Self.retention)
    }
}

/// Fans a single event out to every backend. Order is preserved; a slow or
/// throwing backend can't starve the others because each `record` is itself
/// fail-open.
struct CompositeTelemetry: Telemetry {
    let backends: [Telemetry]

    func record(_ event: String, level: TelemetryLevel, fields: [String: String]) async {
        for backend in backends {
            await backend.record(event, level: level, fields: fields)
        }
    }
}

struct TelemetryKey: StorageKey {
    typealias Value = Telemetry
}

extension Application {
    /// Default fan-out: structured logs + persisted Redis counters. Override in
    /// tests by assigning a recording fake. When Sentry lands, append a
    /// `SentryTelemetry` to this composite — nothing else moves.
    var telemetry: Telemetry {
        get {
            if let existing = storage[TelemetryKey.self] { return existing }
            return CompositeTelemetry(backends: [
                LoggingTelemetry(logger: logger),
                RedisTelemetry(kv: kv, clock: appClock),
            ])
        }
        set { storage[TelemetryKey.self] = newValue }
    }
}

extension Request {
    /// Request-scoped accessor. Resolves to `application.telemetry` so tests can
    /// override centrally; pass request-identifying context (e.g. request-id) via
    /// `fields` at the call site when you need correlation.
    var telemetry: Telemetry { application.telemetry }
}
