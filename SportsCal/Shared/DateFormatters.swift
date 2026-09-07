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
    static var shortTime: DateFormatter { styled(dateStyle: .none, relative: false, timeStyle: .short) }

    static let relativeFormatter = RelativeDateTimeFormatter()

    private static let cacheLock = OSAllocatedUnfairLock(initialState: [String: DateFormatter]())

    /// A `DateFormatter` resolves `timeZone` and `locale` once, at init.
    ///
    /// That was harmless when every caller built a fresh one, or reassigned
    /// `timeZone = .current` on each use — which is exactly what the mutating callers
    /// this file replaced were doing. Caching the formatters instead means a traveller
    /// crossing a time zone, or anyone changing region in Settings, would keep seeing
    /// kickoff times in the old zone until they relaunched. So the cache is dropped
    /// whenever the system tells us those changed.
    private static let invalidationObservers: Void = {
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: nil
            ) { _ in
                cacheLock.withLock { $0.removeAll() }
            }
        }
    }()

    /// One immutable formatter per format string, created on first use.
    ///
    /// The app uses a small fixed set of format strings (the user's date-format
    /// preference plus a handful of fixed layouts), so this stays tiny — but it is not
    /// keyed on anything user-supplied, so it can't grow without bound either.
    static func formatter(for format: String) -> DateFormatter {
        cached(key: "fmt:\(format)") { f in f.dateFormat = format }
    }

    /// One immutable formatter per (date style, time style, relative) combination — the
    /// shape the user's `dateFormat` preference takes. A handful of entries at most.
    static func styled(
        dateStyle: DateFormatter.Style,
        relative: Bool,
        timeStyle: DateFormatter.Style = .none
    ) -> DateFormatter {
        cached(key: "style:\(dateStyle.rawValue)|time:\(timeStyle.rawValue)|rel:\(relative)") { f in
            f.dateStyle = dateStyle
            f.timeStyle = timeStyle
            f.doesRelativeDateFormatting = relative
        }
    }

    private static func cached(key: String, configure: (DateFormatter) -> Void) -> DateFormatter {
        _ = invalidationObservers
        return cacheLock.withLock { cache in
            if let existing = cache[key] { return existing }
            let f = DateFormatter()
            // Pinned rather than left implicit, so the value a cached formatter holds is
            // the one the invalidation above is responsible for refreshing.
            f.timeZone = .current
            f.locale = .current
            configure(f)
            cache[key] = f
            return f
        }
    }
}
