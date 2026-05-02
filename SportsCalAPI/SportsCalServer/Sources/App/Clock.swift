import Foundation
import Vapor

protocol AppClock: Sendable {
    var now: Date { get }
}

struct SystemClock: AppClock {
    var now: Date { Date() }
}

struct AppClockKey: StorageKey {
    typealias Value = AppClock
}

extension Application {
    var appClock: AppClock {
        get { storage[AppClockKey.self] ?? SystemClock() }
        set { storage[AppClockKey.self] = newValue }
    }
}

extension Request {
    var appClock: AppClock { application.appClock }
}
