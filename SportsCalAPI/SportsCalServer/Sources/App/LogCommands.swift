import Foundation
import Logging

/// Reads stdin commands in a background task to control terminal log filtering.
func startLogCommands() {
    Task.detached {
        let handle = FileHandle.standardInput
        while true {
            guard let data = try? handle.availableData, !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let command = parts[0].lowercased()

            switch command {
            case "level":
                if parts.count > 1, let level = Logger.Level(parts[1].lowercased()) {
                    await LogBroadcaster.shared.setTerminalLevel(level)
                    print("[log] Terminal level set to: \(level)")
                } else {
                    print("[log] Usage: level debug|info|notice|warning|error|critical")
                }

            case "filter":
                if parts.count > 1 {
                    let arg = parts[1].lowercased()
                    if arg == "clear" {
                        await LogBroadcaster.shared.setTerminalLabelFilter(nil)
                        print("[log] Label filter cleared")
                    } else {
                        let labels = Set(arg.split(separator: ",").map(String.init))
                        await LogBroadcaster.shared.setTerminalLabelFilter(labels)
                        print("[log] Filtering to labels: \(labels.sorted().joined(separator: ", "))")
                    }
                } else {
                    print("[log] Usage: filter espn,apns | filter clear")
                }

            case "search":
                if parts.count > 1 {
                    let text = parts[1]
                    if text.lowercased() == "clear" {
                        await LogBroadcaster.shared.setTerminalSearchText(nil)
                        print("[log] Search filter cleared")
                    } else {
                        await LogBroadcaster.shared.setTerminalSearchText(text)
                        print("[log] Searching for: \"\(text)\"")
                    }
                } else {
                    print("[log] Usage: search <text> | search clear")
                }

            case "status":
                let status = await LogBroadcaster.shared.getTerminalStatus()
                print("[log] \(status)")

            case "help":
                print("""
                [log] Available commands:
                  level debug|info|notice|warning|error  — set minimum log level
                  filter espn,apns                       — show only matching subsystems
                  filter clear                           — clear label filter
                  search <text>                          — only show entries containing text
                  search clear                           — clear search filter
                  status                                 — print current filter settings
                  help                                   — show this help
                """)

            default:
                print("[log] Unknown command: '\(command)'. Type 'help' for available commands.")
            }
        }
    }
}

// Parse Logger.Level from string
extension Logger.Level {
    init?(_ string: String) {
        switch string {
        case "trace": self = .trace
        case "debug": self = .debug
        case "info": self = .info
        case "notice": self = .notice
        case "warning": self = .warning
        case "error": self = .error
        case "critical": self = .critical
        default: return nil
        }
    }
}
