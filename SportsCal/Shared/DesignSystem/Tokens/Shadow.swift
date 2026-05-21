//
//  Shadow.swift
//  SportsCal — Design System v1.0
//
//  Two-layer shadows for depth without smudging. Reduce-Transparency
//  fallback replaces the shadow with a 1pt strong divider border so depth
//  is still legible.
//

import SwiftUI

public enum AppShadow {
    case rest, lift, sheet

    var primary: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        switch self {
        case .rest:  return (.black.opacity(0.06), 2,  0, 1)
        case .lift:  return (.black.opacity(0.08), 12, 0, 4)
        case .sheet: return (.black.opacity(0.16), 32, 0, 12)
        }
    }
    var secondary: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        switch self {
        case .rest:  return (.black.opacity(0.04), 1, 0, 1)
        case .lift:  return (.black.opacity(0.05), 4, 0, 2)
        case .sheet: return (.black.opacity(0.08), 8, 0, 4)
        }
    }
}

public struct AppShadowModifier: ViewModifier {
    let level: AppShadow
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content.overlay(
                RoundedRectangle.appShape(.appRadiusMD)
                    .strokeBorder(Color.appDividerStrong, lineWidth: 1)
            )
        } else {
            content
                .shadow(color: level.primary.color,
                        radius: level.primary.radius,
                        x: level.primary.x, y: level.primary.y)
                .shadow(color: level.secondary.color,
                        radius: level.secondary.radius,
                        x: level.secondary.x, y: level.secondary.y)
        }
    }
}

public extension View {
    /// Apply a two-layer iOS-realistic shadow. Auto-replaces with a 1pt
    /// border when Reduce Transparency is on.
    func appShadow(_ level: AppShadow = .rest) -> some View {
        modifier(AppShadowModifier(level: level))
    }
}
