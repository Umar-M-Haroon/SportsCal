//
//  DateFormatters.swift
//  SportsCal
//
//  Created by Umar Haroon on 10/23/22.
//

import Foundation
import os

/// Shared date formatters.
///
/// These are *configured once and never mutated*. Callers used to reach in and reassign
/// `dateFormat` / `timeStyle` / `timeZone` on a single shared instance per call, which
/// cost a full `CFDateFormatter` rebuild every time (row rendering hit this through
/// `Date.formatToDate`) and raced whenever two threads did it at once — the WebSocket
/// decode task, the widget extension and the main actor all touch these.
///
/// For a format string not covered by a named formatter, use ``formatter(for:)``: it
/// memoizes one immutable formatter per format string behind a lock.
enum DateFormatters {
    static let isoFormatter = ISO8601DateFormatter()

    /// Locale-aware short time ("7:30 PM"), the common case for a game's start.
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static let relativeFormatter = RelativeDateTimeFormatter()

    private static let cacheLock = OSAllocatedUnfairLock(initialState: [String: DateFormatter]())

    /// One immutable formatter per format string, created on first use.
    ///
    /// The app uses a small fixed set of format strings (the user's date-format
    /// preference plus a handful of fixed layouts), so this stays tiny — but it is not
    /// keyed on anything user-supplied, so it can't grow without bound either.
    static func formatter(for format: String) -> DateFormatter {
        cacheLock.withLock { cache in
            if let existing = cache[format] { return existing }
            let f = DateFormatter()
            f.dateFormat = format
            cache[format] = f
            return f
        }
    }

    /// One immutable formatter per (date style, relative) pair — the shape the user's
    /// `dateFormat` preference takes. There are four styles and two relative modes, so
    /// the cache tops out at eight entries.
    static func styled(dateStyle: DateFormatter.Style, relative: Bool) -> DateFormatter {
        let key = "style:\(dateStyle.rawValue)|rel:\(relative)"
        return cacheLock.withLock { cache in
            if let existing = cache[key] { return existing }
            let f = DateFormatter()
            f.dateStyle = dateStyle
            f.timeStyle = .none
            f.doesRelativeDateFormatting = relative
            cache[key] = f
            return f
        }
    }
}
