//
//  ICSCalendar.swift
//
//  A minimal RFC 5545 serializer for the subscribable schedule feeds
//  (`/cal/team/:id.ics`, `/cal/league/:id.ics`). Pure and deterministic given its
//  inputs, so it is unit-tested directly.
//
//  The rules that matter for Apple Calendar and Google Calendar:
//  - every line ends in CRLF;
//  - content lines longer than 75 octets are folded (CRLF + one space), never inside
//    a UTF-8 sequence;
//  - TEXT values escape `\`, `;`, `,` and newlines;
//  - every VEVENT has a UID and a DTSTAMP, and times are UTC (`…Z`).
//

import Foundation

struct ICSEvent: Equatable {
    enum Timing: Equatable {
        /// A timed event, both ends in UTC.
        case timed(start: Date, end: Date)
        /// An all-day event; `endExclusive` is the day after the last day (RFC 5545).
        case allDay(start: Date, endExclusive: Date)
    }

    var uid: String
    var timing: Timing
    var summary: String
    var description: String?
    var location: String?
    var url: String?
    var cancelled: Bool = false
}

struct ICSCalendar {
    var name: String
    var description: String?
    var url: String?
    /// Hint to clients for how often to re-fetch (REFRESH-INTERVAL / X-PUBLISHED-TTL).
    var refreshInterval: String = "PT6H"
    var events: [ICSEvent]

    /// The whole VCALENDAR, CRLF-terminated.
    func render(stamp: Date) -> String {
        var lines: [String] = []
        lines.reserveCapacity(events.count * 10 + 12)
        lines.append("BEGIN:VCALENDAR")
        lines.append("VERSION:2.0")
        lines.append("PRODID:-//Scoreline//Schedules//EN")
        lines.append("CALSCALE:GREGORIAN")
        lines.append("METHOD:PUBLISH")
        lines.append("NAME:" + ICS.escapeText(name))
        lines.append("X-WR-CALNAME:" + ICS.escapeText(name))
        if let description {
            lines.append("X-WR-CALDESC:" + ICS.escapeText(description))
        }
        if let url {
            lines.append("URL:" + url)
        }
        lines.append("REFRESH-INTERVAL;VALUE=DURATION:" + refreshInterval)
        lines.append("X-PUBLISHED-TTL:" + refreshInterval)
        let dtstamp = ICS.utcStamp(stamp)
        for event in events {
            ICS.append(event, dtstamp: dtstamp, to: &lines)
        }
        lines.append("END:VCALENDAR")

        var out = ""
        for line in lines {
            out += ICS.fold(line)
            out += "\r\n"
        }
        return out
    }
}

enum ICS {
    static func append(_ event: ICSEvent, dtstamp: String, to lines: inout [String]) {
        lines.append("BEGIN:VEVENT")
        lines.append("UID:" + escapeText(event.uid))
        lines.append("DTSTAMP:" + dtstamp)
        switch event.timing {
        case .timed(let start, let end):
            lines.append("DTSTART:" + utcStamp(start))
            lines.append("DTEND:" + utcStamp(end))
        case .allDay(let start, let endExclusive):
            lines.append("DTSTART;VALUE=DATE:" + utcDay(start))
            lines.append("DTEND;VALUE=DATE:" + utcDay(endExclusive))
        }
        lines.append("SUMMARY:" + escapeText(event.summary))
        if let description = event.description, !description.isEmpty {
            lines.append("DESCRIPTION:" + escapeText(description))
        }
        if let location = event.location, !location.isEmpty {
            lines.append("LOCATION:" + escapeText(location))
        }
        if let url = event.url {
            lines.append("URL:" + url)
        }
        lines.append(event.cancelled ? "STATUS:CANCELLED" : "STATUS:CONFIRMED")
        lines.append("TRANSP:TRANSPARENT")
        lines.append("END:VEVENT")
    }

    /// RFC 5545 §3.3.11 TEXT escaping. CRs are dropped; a CRLF or LF becomes `\n`.
    static func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case ";": out += "\\;"
            case ",": out += "\\,"
            case "\n": out += "\\n"
            case "\r": break
            default:
                // Other control characters are not allowed in TEXT; drop them.
                if ch.value < 0x20 && ch != "\t" { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    /// Folds a content line to at most 75 octets per physical line (RFC 5545 §3.1).
    /// Continuation lines start with one space, which counts toward their 75. Breaks
    /// only between Unicode scalars, so a multi-byte UTF-8 character is never split.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var out = ""
        var current = 0
        for ch in line.unicodeScalars {
            let size = String(ch).utf8.count
            if current + size > 75 {
                out += "\r\n "
                current = 1
            }
            out.unicodeScalars.append(ch)
            current += size
        }
        return out
    }

    static func utcStamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }

    static func utcDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    nonisolated(unsafe) private static let stampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return df
    }()

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyyMMdd"
        return df
    }()
}
