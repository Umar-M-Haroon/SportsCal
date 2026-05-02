import Foundation
@testable import App

/// Thread-safe advanceable clock for time-sensitive tests (TTL expiry, job ticks).
/// Accessed via an internal lock so tests that drive the clock from multiple
/// tasks don't race.
final class MutableClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self._now = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }

    func set(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        _now = date
    }
}
