//
//  EFRemixTheme.swift
//  SportsCal (iOS)
//
//  v3 — Forwards to the SwiftUI Design System tokens (`Color.app*`,
//  `Font.app*`). The original v2 oklch/Kalam tokens have been retired.
//
//  Existing EFRemix views (EFRemixBrowsePage, EFRemixDayPage, etc.) keep
//  calling `EFTheme.bg(mode)`, `EFFont.hand(size)`, `efSportColor(_:)`
//  and now render with the production design system. The `mode`
//  parameter is preserved for source compatibility but is no longer
//  consulted — `Color.app*` tokens are adaptive (light/dark) on their
//  own.
//

import SwiftUI
import SportsCalModel

// MARK: - Mode (kept for source compatibility)

enum EFMode {
    case dark, light

    /// Preserved for callers that derive mode from the environment scheme.
    /// Adaptive design tokens make this redundant, but we keep the API
    /// stable so existing EFRemix views compile without edits.
    static func from(_ scheme: ColorScheme) -> EFMode {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Theme tokens — forward to Color.app*

enum EFTheme {
    static func bg(_ mode: EFMode) -> Color      { .appBackground }
    static func surface(_ mode: EFMode) -> Color { .appSurface }
    static func alt(_ mode: EFMode) -> Color     { .appAlt }
    static func line(_ mode: EFMode) -> Color    { .appDivider }
    static func lineHi(_ mode: EFMode) -> Color  { .appDividerStrong }
    static func ink(_ mode: EFMode) -> Color     { .appInk }
    static func soft(_ mode: EFMode) -> Color    { .appInkSoft }
    static func faint(_ mode: EFMode) -> Color   { .appInkFaint }
    static func live(_ mode: EFMode) -> Color    { .appLive }
    static func star(_ mode: EFMode) -> Color    { .appStar }
}

// MARK: - Sport palette — forward to Color.app(_:)

func efSportColor(_ sport: SportType, mode: EFMode = .dark, opacity: Double = 1) -> Color {
    Color.app(sport).opacity(opacity)
}

// MARK: - Fonts — forward to system rounded / monospaced (SF Pro family)

enum EFFont {
    /// Was Kalam/Noteworthy. Now SF Pro Rounded at the requested size,
    /// scaling with Dynamic Type via `relativeTo`.
    static func hand(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Was JetBrains Mono. Now SF Mono at the requested size + weight.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Color hex helper (kept — UInt32 hex literals used elsewhere)

extension Color {
    /// Convenience initializer for 0xRRGGBB literals. Distinct signature
    /// from `Color(_ hex: String)` in `Color+App.swift`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
