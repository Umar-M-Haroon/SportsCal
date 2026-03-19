import Vapor
import Logging
import Foundation

/// A log entry that flows through the logging system.
struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: String
    let label: String
    let message: String
    let metadata: [String: String]
}

/// Per-WebSocket-connection filter state.
struct LogFilter: Sendable {
    var minLevel: Logger.Level = .debug
    var labels: Set<String>? = nil
    var searchText: String? = nil

    func accepts(_ entry: LogEntry) -> Bool {
        let entryLevel = logLevelOrder(entry.level)
        let minLevelOrder = logLevelOrder(minLevel.rawStringValue)
        if entryLevel < minLevelOrder { return false }
        if let labels, !labels.contains(entry.label) { return false }
        if let search = searchText, !search.isEmpty,
           !entry.message.localizedCaseInsensitiveContains(search) &&
           !entry.label.localizedCaseInsensitiveContains(search) {
            return false
        }
        return true
    }
}

private func logLevelOrder(_ level: String) -> Int {
    switch level {
    case "trace": return 0
    case "debug": return 1
    case "info": return 2
    case "notice": return 3
    case "warning": return 4
    case "error": return 5
    case "critical": return 6
    default: return 2
    }
}

// JSON message types for WebSocket
private struct InitialMessage: Encodable {
    let type = "initial"
    let entries: [LogEntry]
}

private struct EntryMessage: Encodable {
    let type = "entry"
    let entry: LogEntry
}

/// Singleton actor that receives log entries and broadcasts them to terminal and WebSocket subscribers.
actor LogBroadcaster {
    static let shared = LogBroadcaster()

    private var ringBuffer: [LogEntry] = []
    private let bufferSize = 1000

    // WebSocket subscribers with per-connection filters
    private var subscribers: [ObjectIdentifier: (ws: WebSocket, filter: LogFilter)] = [:]

    // Terminal filter state
    var terminalFilter = LogFilter(minLevel: .info)

    // ANSI color codes
    private let reset = "\u{001B}[0m"
    private let dim = "\u{001B}[2m"
    private let bold = "\u{001B}[1m"

    // Level colors
    private let levelColors: [String: String] = [
        "trace":    "\u{001B}[37m",
        "debug":    "\u{001B}[36m",
        "info":     "\u{001B}[32m",
        "notice":   "\u{001B}[34m",
        "warning":  "\u{001B}[33m",
        "error":    "\u{001B}[31m",
        "critical": "\u{001B}[1;31m",
    ]

    // Label color palette (deterministic by hash)
    private let labelColors: [String] = [
        "\u{001B}[38;5;39m",
        "\u{001B}[38;5;208m",
        "\u{001B}[38;5;170m",
        "\u{001B}[38;5;114m",
        "\u{001B}[38;5;215m",
        "\u{001B}[38;5;147m",
        "\u{001B}[38;5;80m",
        "\u{001B}[38;5;217m",
    ]

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {}

    /// Receive a new log entry from the log handler.
    func broadcast(_ entry: LogEntry) {
        // Store in ring buffer
        ringBuffer.append(entry)
        if ringBuffer.count > bufferSize {
            ringBuffer.removeFirst(ringBuffer.count - bufferSize)
        }

        // Print to terminal
        if terminalFilter.accepts(entry) {
            printToTerminal(entry)
        }

        // Send to WebSocket subscribers
        for (id, sub) in subscribers {
            if sub.filter.accepts(entry) {
                sendToWebSocket(entry, ws: sub.ws, id: id)
            }
        }
    }

    // MARK: - Terminal

    private func printToTerminal(_ entry: LogEntry) {
        let time = "\(dim)\(dateFormatter.string(from: entry.timestamp))\(reset)"

        let levelBadge = entry.level.uppercased()
        let levelPadded = levelBadge.padding(toLength: 5, withPad: " ", startingAt: 0)
        let levelColor = levelColors[entry.level] ?? ""
        let level = "\(levelColor)\(bold)\(levelPadded)\(reset)"

        let labelColor = colorForLabel(entry.label)
        let labelPadded = entry.label.padding(toLength: 16, withPad: " ", startingAt: 0)
        let label = "\(labelColor)\(labelPadded)\(reset)"

        let separator = "\(dim)\u{2502}\(reset)"

        var line = "\(time) \(level) \(label) \(separator) \(entry.message)"

        if !entry.metadata.isEmpty {
            let meta = entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            line += " \(dim)\(meta)\(reset)"
        }

        print(line)
    }

    private func colorForLabel(_ label: String) -> String {
        let index = abs(label.hashValue) % labelColors.count
        return labelColors[index]
    }

    // MARK: - Terminal Filter Control

    func setTerminalLevel(_ level: Logger.Level) {
        terminalFilter.minLevel = level
    }

    func setTerminalLabelFilter(_ labels: Set<String>?) {
        terminalFilter.labels = labels
    }

    func setTerminalSearchText(_ text: String?) {
        terminalFilter.searchText = text
    }

    func getTerminalStatus() -> String {
        var parts: [String] = []
        parts.append("Level: \(terminalFilter.minLevel)")
        if let labels = terminalFilter.labels {
            parts.append("Labels: \(labels.sorted().joined(separator: ", "))")
        } else {
            parts.append("Labels: all")
        }
        if let search = terminalFilter.searchText {
            parts.append("Search: \"\(search)\"")
        } else {
            parts.append("Search: none")
        }
        parts.append("Subscribers: \(subscribers.count)")
        parts.append("Buffer: \(ringBuffer.count)/\(bufferSize)")
        return parts.joined(separator: " | ")
    }

    // MARK: - WebSocket Subscribers

    func addSubscriber(_ ws: WebSocket) {
        let id = ObjectIdentifier(ws)
        subscribers[id] = (ws: ws, filter: LogFilter(minLevel: .debug))

        // Send ring buffer for initial context
        let entries = ringBuffer
        Task {
            do {
                let msg = InitialMessage(entries: entries)
                let data = try jsonEncoder.encode(msg)
                if let json = String(data: data, encoding: .utf8) {
                    try await ws.send(json)
                }
            } catch {
                // Ignore encoding errors on initial send
            }
        }
    }

    func removeSubscriber(_ ws: WebSocket) {
        let id = ObjectIdentifier(ws)
        subscribers.removeValue(forKey: id)
    }

    func updateSubscriberFilter(_ ws: WebSocket, filter: LogFilter) {
        let id = ObjectIdentifier(ws)
        if var sub = subscribers[id] {
            sub.filter = filter
            subscribers[id] = sub
        }
    }

    private func sendToWebSocket(_ entry: LogEntry, ws: WebSocket, id: ObjectIdentifier) {
        Task {
            do {
                let msg = EntryMessage(entry: entry)
                let data = try jsonEncoder.encode(msg)
                if let json = String(data: data, encoding: .utf8) {
                    try await ws.send(json)
                }
            } catch {
                // Remove failed subscriber
                subscribers.removeValue(forKey: id)
            }
        }
    }
}
