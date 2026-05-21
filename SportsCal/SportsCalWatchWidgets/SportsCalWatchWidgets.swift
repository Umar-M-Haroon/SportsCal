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

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryCircular:
            SportsWidgetCircularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            SportsWidgetRectangularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            SportsWidgetInlineView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCorner:
            SportsWidgetCornerView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryExtraLarge:
            SportsWidgetExtraLargeView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        default:
            SportsWidgetCircularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
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
