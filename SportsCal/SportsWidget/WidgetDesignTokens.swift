//
//  WidgetDesignTokens.swift
//  SportsWidgetExtension — Design System (Phase G, minimum viable)
//
//  The Phase A `Color.app*` / `Font.app*` / `CGFloat.appSpace*` tokens
//  live under `SportsCal/Shared/DesignSystem/` and are members of the
//  iOS app target only — adding them to the widget target requires
//  multi-target pbxproj membership edits that the Xcode MCP doesn't
//  expose. Until those tokens are promoted to a shared SPM module, this
//  file gives widget views the subset they need: surface + ink colors,
//  the "Updated Xm ago" timestamp helper, and corner-radius constants.
//
//  Definitions are kept in sync with `Color+App.swift` /
//  `CGFloat+Space.swift`. Update both sides when tokens change.
//

import SwiftUI
import WidgetKit
import SportsCalModel

enum WidgetTokens {
    // MARK: - Surfaces (matches Color.app*)
    static let surface = Color(light: 0xFFFFFF, dark: 0x171A21)
    static let background = Color(light: 0xF7F5F0, dark: 0x0E1014)
    static let alt = Color(light: 0xEFECE4, dark: 0x1F232C)
    static let ink = Color(light: 0x1A1612, dark: 0xF4F3EE)
    static let inkSoft = Color(light: 0x1A1612, dark: 0xF4F3EE).opacity(0.62)
    static let inkFaint = Color(light: 0x1A1612, dark: 0xF4F3EE).opacity(0.36)
    static let live = Color(light: 0xD63B2F, dark: 0xFF5D52)
    static let star = Color(light: 0xA87613, dark: 0xFFD966)

    // MARK: - Radii (matches CGFloat.appRadius*)
    static let radiusXS: CGFloat = 4
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
    static let radiusXL: CGFloat = 22

    // MARK: - Spacing (matches CGFloat.appSpace*)
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16

    // MARK: - Sport accents (matches Color.app(_:))
    static func sport(_ sport: SportType) -> Color {
        switch sport {
        case .basketball: return Color(light: 0xA05C0E, dark: 0xE8B070)
        case .soccer:     return Color(light: 0x1B6F45, dark: 0x7DC79E)
        case .hockey:     return Color(light: 0x2A5C9A, dark: 0x9CBEEB)
        case .mlb:        return Color(light: 0xA14829, dark: 0xE89F84)
        case .nfl:        return Color(light: 0x7B3D8C, dark: 0xC8A2DA)
        case .racing:     return Color(light: 0xA53B26, dark: 0xEA9787)
        case .tennis:     return Color(light: 0x5C7821, dark: 0xB3CC78)
        case .golf:       return Color(light: 0x1F7A65, dark: 0x85CDB7)
        }
    }
    static func sportTint(_ sport: SportType) -> Color { WidgetTokens.sport(sport).opacity(0.18) }
}

// MARK: - Adaptive color hex helper (mirrors Color+App.swift but takes Int hex)

private extension Color {
    init(light: Int, dark: Int) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor(dynamicProvider: { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(rgbHex: dark)
                : UIColor(rgbHex: light)
        }))
        #else
        self.init(rgbHex: light)
        #endif
    }
    init(rgbHex: Int) {
        self.init(.sRGB,
                  red: Double((rgbHex >> 16) & 0xFF) / 255,
                  green: Double((rgbHex >> 8) & 0xFF) / 255,
                  blue: Double(rgbHex & 0xFF) / 255,
                  opacity: 1)
    }
}

#if canImport(UIKit)
import UIKit
private extension UIColor {
    convenience init(rgbHex: Int) {
        self.init(red: CGFloat((rgbHex >> 16) & 0xFF) / 255,
                  green: CGFloat((rgbHex >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgbHex & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif

// MARK: - WidgetBackground — family-aware containerBackground content
//
// Use as the *content* of `.containerBackground(for: .widget) { ... }`:
//
//   .containerBackground(for: .widget) { WidgetBackground() }
//
// Renders an opaque WidgetTokens.background on home-screen families
// (small / medium / large / extraLarge) so the design system's surface
// shows through, and Color.clear on lock-screen accessory families so
// they composite over the wallpaper (otherwise iOS clips the inset).

import WidgetKit

struct WidgetBackground: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if isAccessory {
            Color.clear
        } else {
            WidgetTokens.background
        }
    }

    private var isAccessory: Bool {
        switch family {
        #if os(iOS)
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        #endif
        #if os(watchOS)
        case .accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        #endif
        default:
            return false
        }
    }
}

// MARK: - "Updated Xm ago" — widgets aren't real-time, surface freshness

enum WidgetUpdated {
    /// Compact "now" / "4m ago" / "2h ago" string for the freshness label
    /// every widget should display per Design System §14.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let secs = Int(now.timeIntervalSince(date))
        if secs < 30 { return "Just now" }
        if secs < 60 { return "\(secs)s ago" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        let days = hrs / 24
        return "\(days)d ago"
    }
}

// MARK: - UpdatedTimestampLabel — drop-in widget footer

/// Tiny mono label "Updated 4m ago". Use as a footer in every widget
/// (the design system explicitly calls this out — widgets aren't
/// real-time, so users need a freshness signal).
struct WidgetUpdatedLabel: View {
    let date: Date

    var body: some View {
        Text("Updated \(WidgetUpdated.ago(date))")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(WidgetTokens.inkFaint)
            .accessibilityLabel(Text("Last updated \(WidgetUpdated.ago(date))"))
    }
}
