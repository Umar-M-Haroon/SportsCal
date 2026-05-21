//
//  Motion.swift
//  SportsCal — Design System v1.0
//
//  Spring-based animation tokens matched to common interactions. Use the
//  appAnimation modifier to honor Reduce Motion automatically (falls back
//  to a quick fade).
//

import SwiftUI

public enum AppMotion {
    /// Quick UI feedback — chip toggle, tab change. ~280ms.
    public static let snap = Animation.spring(response: 0.28, dampingFraction: 0.86)

    /// Reorder, list↔grid swap. Bouncier — visible movement.
    public static let rearrange = Animation.spring(response: 0.42, dampingFraction: 0.78)

    /// Sheet present, fullscreen focus. Slower, smooth.
    public static let sheet = Animation.spring(response: 0.55, dampingFraction: 0.88)

    /// Live data tick — subtle pulse for score updates.
    public static let liveTick = Animation.easeOut(duration: 0.35)
}

public extension View {
    /// Apply an animation, falling back to a 180ms easeInOut fade when
    /// Reduce Motion is on. Pass the Environment value yourself so the
    /// modifier can be used outside of view init.
    func appAnimation<V: Equatable>(
        _ motion: Animation,
        value: V,
        reduceMotion: Bool = false
    ) -> some View {
        animation(reduceMotion ? .easeInOut(duration: 0.18) : motion, value: value)
    }
}
