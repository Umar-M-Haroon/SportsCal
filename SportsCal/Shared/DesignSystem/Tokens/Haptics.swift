//
//  Haptics.swift
//  SportsCal — Design System v1.0
//
//  Semantic haptic events. UIKit-backed on iOS; no-op everywhere else.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum AppHaptic {
    /// Chip toggle, list row tap. Light impact.
    case tap
    /// Drag-drop complete, swap commit. Medium impact.
    case rearrange
    /// Favorite added, settings saved. Success notification.
    case success
    /// Score change against your team. Warning notification.
    case warning
    /// Network fail, validation error. Error notification.
    case error
    /// Game just went live. Rigid impact at 0.85 intensity.
    case liveAlert
    /// A tracked game's score went up (goal / score). Success notification
    /// followed by a heavy impact for a distinct "they scored" punch.
    case goal

    public func fire() {
        #if canImport(UIKit) && !os(watchOS)
        switch self {
        case .tap:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .rearrange:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .liveAlert:
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.impactOccurred(intensity: 0.85)
        case .goal:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.impactOccurred(intensity: 1.0)
        }
        #endif
    }
}
