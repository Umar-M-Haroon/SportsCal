import Logging
import Foundation

/// A `LogHandler` that creates `LogEntry` values and sends them to `LogBroadcaster`.
public struct PrettyLogHandler: LogHandler {
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level

    let label: String

    /// Shorten verbose labels: "codes.vapor.application" → "vapor"
    private let shortLabel: String

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public init(label: String, level: Logger.Level = .info) {
        self.label = label
        self.logLevel = level

        // Shorten label for display
        let parts = label.split(separator: ".")
        if parts.count >= 2 {
            self.shortLabel = String(parts[parts.count - 1])
        } else {
            self.shortLabel = label
        }
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        var merged: [String: String] = [:]
        for (k, v) in self.metadata {
            merged[k] = "\(v)"
        }
        if let extra = metadata {
            for (k, v) in extra {
                merged[k] = "\(v)"
            }
        }

        let entry = LogEntry(
            timestamp: Date(),
            level: level.rawStringValue,
            label: shortLabel,
            message: "\(message)",
            metadata: merged
        )

        Task {
            await LogBroadcaster.shared.broadcast(entry)
        }
    }
}

// Map Logger.Level to its string name
extension Logger.Level {
    var rawStringValue: String {
        switch self {
        case .trace: return "trace"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .warning: return "warning"
        case .error: return "error"
        case .critical: return "critical"
        }
    }
}
