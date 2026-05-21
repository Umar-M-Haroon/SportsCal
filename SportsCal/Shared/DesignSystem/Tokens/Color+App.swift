//
//  Color+App.swift
//  SportsCal — Design System v1.0
//
//  Semantic surface, ink, and status colors. Adaptive light/dark via
//  Color(light:dark:). Pairs verified against WCAG 2.2 AA — see Design
//  System §17. Increase Contrast variant uses appInkSoftAdaptive(_:).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Color {
    // MARK: - Semantic surfaces

    static let appBackground = Color(light: "#F7F5F0", dark: "#0E1014")
    static let appSurface    = Color(light: "#FFFFFF", dark: "#171A21")
    static let appAlt        = Color(light: "#EFECE4", dark: "#1F232C")

    static let appDivider = Color(
        light: .black.opacity(0.10),
        dark:  .white.opacity(0.08)
    )
    static let appDividerStrong = Color(
        light: .black.opacity(0.22),
        dark:  .white.opacity(0.18)
    )

    // MARK: - Ink hierarchy

    static let appInk = Color(light: "#1A1612", dark: "#F4F3EE")

    static let appInkSoft = Color(
        light: Color("#1A1612").opacity(0.62),
        dark:  Color("#F4F3EE").opacity(0.62)
    )
    static let appInkFaint = Color(
        light: Color("#1A1612").opacity(0.36),
        dark:  Color("#F4F3EE").opacity(0.32)
    )

    /// Soft ink that promotes to primary ink when Increase Contrast is on.
    static func appInkSoftAdaptive(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? .appInk : .appInkSoft
    }

    // MARK: - Status accents

    /// Live indicator. Pair with pulse animation. Use sparingly.
    static let appLive = Color(light: "#D63B2F", dark: "#FF5D52")

    /// Leverage / favorite / "high stakes" tag color.
    static let appStar = Color(light: "#A87613", dark: "#FFD966")

    /// Score deltas: green positive lead.
    static let appPositive = Color(light: "#1F8B3F", dark: "#5BD174")
    /// Score deltas: red deficit. Aliases appLive.
    static let appNegative = Color.appLive
}

// MARK: - Helper initializers

public extension Color {
    /// Hex string init: "#RRGGBB" or "#RRGGBBAA". Leading "#" optional.
    init(_ hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8)  & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Adaptive light/dark Color from hex strings.
    init(light: String, dark: String) {
        self.init(light: Color(light), dark: Color(dark))
    }

    /// Adaptive light/dark from existing Colors. Cross-platform.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor(dynamicProvider: { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        }))
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return isDark ? NSColor(dark) : NSColor(light)
        }))
        #else
        self = light
        #endif
    }
}
