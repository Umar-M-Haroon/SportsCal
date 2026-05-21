//
//  Color+Sport.swift
//  SportsCal — Design System v1.0
//
//  Sport accent palette. Authored in OKLCH (perceptually uniform), exported
//  as adaptive sRGB Colors. Hue varies by sport; chroma 0.13 and lightness
//  (L=0.50 light, L=0.78 dark) are locked so no sport visually overpowers
//  another. Reuses existing SportType enum from SportsCalModel — no
//  separate Sport enum needed.
//
//  Hue table:
//    basketball=50°, soccer=150°, hockey=230°, mlb (baseball)=20°,
//    nfl (football)=290°, racing (f1)=10°, tennis=105°, golf=170°
//

import SwiftUI
import SportsCalModel

public extension Color {
    /// Returns the sport's adaptive accent color (auto light/dark).
    static func app(_ sport: SportType) -> Color {
        switch sport {
        case .basketball: return Color(light: "#A05C0E", dark: "#E8B070")
        case .soccer:     return Color(light: "#1B6F45", dark: "#7DC79E")
        case .hockey:     return Color(light: "#2A5C9A", dark: "#9CBEEB")
        case .mlb:        return Color(light: "#A14829", dark: "#E89F84")
        case .nfl:        return Color(light: "#7B3D8C", dark: "#C8A2DA")
        case .racing:     return Color(light: "#A53B26", dark: "#EA9787")
        case .tennis:     return Color(light: "#5C7821", dark: "#B3CC78")
        case .golf:       return Color(light: "#1F7A65", dark: "#85CDB7")
        }
    }

    /// Subtle background tint for sport-coded chips and cards.
    static func appTint(_ sport: SportType) -> Color {
        .app(sport).opacity(0.12)
    }
}
