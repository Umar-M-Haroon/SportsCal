//
//  SportsCalWatchWidgets.swift
//  SportsCalWatchWidgets
//
//  Watch-specific widget definition and entry view router.
//  Reuses Provider, SimpleEntry, and SportsWidgetIntent from the shared
//  SportsWidget/ files (included via Xcode target membership).
//

import WidgetKit
import SwiftUI
import SportsCalModel

// MARK: - Watch Entry View Router

struct WatchWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                SportsWidgetCircularView(entry: entry)
            case .accessoryRectangular:
                SportsWidgetRectangularView(entry: entry)
            case .accessoryInline:
                SportsWidgetInlineView(entry: entry)
            case .accessoryCorner:
                SportsWidgetCornerView(entry: entry)
            case .accessoryExtraLarge:
                SportsWidgetExtraLargeView(entry: entry)
            @unknown default:
                SportsWidgetCircularView(entry: entry)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Watch Widget

struct SportsCalWatchWidget: Widget {
    let kind: String = "SportsCalWatchWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SportsWidgetIntent.self,
            provider: Provider()
        ) { entry in
            WatchWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sports Widget")
        .description("Show upcoming games for a sport")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
            .accessoryExtraLarge
        ])
        .contentMarginsDisabled()
    }
}
