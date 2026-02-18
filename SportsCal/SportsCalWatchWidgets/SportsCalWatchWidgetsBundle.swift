//
//  SportsCalWatchWidgetsBundle.swift
//  SportsCalWatchWidgets
//
//  Watch widget extension entry point.
//  Provides complications: Circular, Rectangular, Inline, Corner, ExtraLarge.
//  Shared files (Provider, WidgetAppIntents, complication views) are included
//  via Xcode target membership from SportsWidget/.
//

import WidgetKit
import SwiftUI

@main
struct SportsCalWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SportsCalWatchWidget()
    }
}
