//
//  EFRemixTheme.swift
//  SportsCal (iOS)
//
//  Palette + font tokens for the EF Remix v2 design.
//  Mirrors `ef-core.jsx` from the Claude Design handoff bundle:
//  shared-chroma oklch sport palette, near-black dark / warm cream light
//  surfaces, hand-written + monospace typography.
//

import SwiftUI
import SportsCalModel

// MARK: - Mode

enum EFMode {
    case dark, light

    static func from(_ scheme: ColorScheme) -> EFMode {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Theme tokens (translated from JSX `TH` dict)

enum EFTheme {
    static func bg(_ mode: EFMode) -> Color {
        mode == .dark ? Color(hex: 0x0e1014) : Color(hex: 0xf7f5f0)
    }
    static func surface(_ mode: EFMode) -> Color {
        mode == .dark ? Color(hex: 0x171a21) : .white
    }
    static func alt(_ mode: EFMode) -> Color {
        mode == .dark ? Color(hex: 0x1f232c) : Color(hex: 0xefece4)
    }
    static func line(_ mode: EFMode) -> Color {
        mode == .dark ? .white.opacity(0.08) : Color(hex: 0x14120e).opacity(0.10)
    }
    static func lineHi(_ mode: EFMode) -> Color {
        mode == .dark ? .white.opacity(0.18) : Color(hex: 0x14120e).opacity(0.22)
    }
    static func ink(_ mode: EFMode) -> Color {
        mode == .dark ? Color(hex: 0xf4f3ee) : Color(hex: 0x1a1612)
    }
    static func soft(_ mode: EFMode) -> Color {
        ink(mode).opacity(0.62)
    }
    static func faint(_ mode: EFMode) -> Color {
        ink(mode).opacity(mode == .dark ? 0.32 : 0.36)
    }
    static func live(_ mode: EFMode) -> Color {
        mode == .dark ? Color(hex: 0xff5d52) : Color(hex: 0xd63b2f)
    }
    static func star(_ mode: EFMode) -> Color {
        mode == .dark ? Color(hex: 0xffd966) : Color(hex: 0xa87613)
    }
}

// MARK: - Sport palette

/// Hue lookup mirroring `SPORT_HUE` from `ef-core.jsx`. Values are in degrees
/// (0-360) and converted to SwiftUI's 0-1 normalized hue at use site.
private let efSportHueDegrees: [SportType: Double] = [
    .basketball: 50,
    .soccer: 150,
    .hockey: 230,
    .mlb: 20,
    .nfl: 290,
    .racing: 10,
    .tennis: 105,
    .golf: 170,
]

/// Approximation of `oklch(L 0.13 H)` from the design system. SwiftUI's
/// HSB isn't perceptually uniform, but holding saturation + brightness
/// constant across hues gets very close to the cohesive feel oklch was
/// chosen for — no sport overpowers another.
func efSportColor(_ sport: SportType, mode: EFMode, opacity: Double = 1) -> Color {
    let hue = (efSportHueDegrees[sport] ?? 0) / 360.0
    // Tuned to roughly match L=0.78 dark / L=0.50 light from the JSX.
    let saturation = 0.45
    let brightness = mode == .dark ? 0.82 : 0.55
    return Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity)
}

// MARK: - Fonts

enum EFFont {
    /// Hand-written content font. Uses iOS-bundled `Noteworthy-Bold` as the
    /// nearest neighbour to Kalam from the design system. Falls back to the
    /// system body font if Noteworthy isn't available on the running platform.
    static func hand(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Noteworthy-Bold", size: size, relativeTo: style)
    }

    /// Monospaced metadata font. JetBrains Mono in the design — SF Mono via
    /// `.monospaced` design here.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Color hex helper

extension Color {
    /// Convenience initializer for 0xRRGGBB literals.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
