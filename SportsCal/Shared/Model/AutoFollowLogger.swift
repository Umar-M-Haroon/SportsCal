//
//  AutoFollowLogger.swift
//  SportsCal (iOS)
//
//  Structured event log for the auto-follow → live activity pipeline.
//  Only compiled in DEBUG builds. Displayed in DebugLiveActivityTestView.
//

import Foundation
import os

@MainActor @Observable
final class AutoFollowLogger {
    static let shared = AutoFollowLogger()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
        let level: Level
    }

    enum Level {
        case info, success, warning, error

        var symbol: String {
            switch self {
            case .info:    return "ℹ️"
            case .success: return "✅"
            case .warning: return "⚠️"
            case .error:   return "❌"
            }
        }
    }

    private(set) var entries: [Entry] = []

    func log(_ message: String, level: Level = .info) {
        entries.append(Entry(date: .now, message: message, level: level))
        switch level {
        case .info, .success: AppLogger.autoFollow.info("\(message)")
        case .warning:        AppLogger.autoFollow.notice("\(message)")
        case .error:          AppLogger.autoFollow.error("\(message)")
        }
    }

    func clear() { entries.removeAll() }
}
