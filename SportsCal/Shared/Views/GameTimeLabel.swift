//
//  GameTimeLabel.swift
//  SportsCal
//

import SwiftUI

/// Context-aware time label that automatically picks the best format:
/// - Starting within the hour → live-updating relative ("in 42 min")
/// - Today → time only ("7:30 PM")
/// - This week → weekday + time ("Tue 7:30 PM")
/// - Further out → month, day + time ("Mar 28, 7:30 PM")
///
/// When `includeDate` is false (default), only shows time or relative —
/// use this in day-grouped lists where the date is already visible.
struct GameTimeLabel: View {
    let date: Date
    var includeDate: Bool = false

    private var startsWithinHour: Bool {
        let interval = date.timeIntervalSinceNow
        return interval > 0 && interval <= 3600
    }

    var body: some View {
        if startsWithinHour {
            Text(date, style: .relative)
        } else if !includeDate || Calendar.current.isDateInToday(date) {
            Text(date, style: .time)
        } else if date.timeIntervalSinceNow > 0 && date.timeIntervalSinceNow < 7 * 86400 {
            Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        } else {
            Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        }
    }
}
