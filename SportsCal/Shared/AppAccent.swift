//
//  AppAccent.swift
//  SportsCal
//
//  The Themes (Pro) accent palette, plus the one shared reader every target
//  uses to find the accent the user is actually entitled to.
//
//  Compiled into the iOS/Mac app, SportsWidgetExtension, the Watch app and the
//  Watch widgets, so it must stay free of app-only types (no SubscriptionManager,
//  no design tokens). The app owns the selection (`ThemeStore`) and publishes the
//  *effective* accent — already resolved for Pro status and the team/custom
//  source — as one integer in shared defaults. Everything else only reads it.
//

import SwiftUI

/// A selectable accent. `systemBlue` is the default look and the fallback when
/// Pro lapses; `team` and `custom` resolve to a stored color.
enum AppAccent: String, CaseIterable, Identifiable, Sendable {
    case systemBlue
    case pitchGreen
    case gridironOrange
    case ice
    case crimson
    case gold
    case purple
    case teal
    case pink
    case graphite
    case mint
    case team
    case custom

    var id: String { rawValue }

    /// The fixed swatches, in picker order (`team` and `custom` have their own rows).
    static let curated: [AppAccent] = [
        .systemBlue, .pitchGreen, .gridironOrange, .ice, .crimson, .gold,
        .purple, .teal, .pink, .graphite, .mint,
    ]

    var displayName: String {
        switch self {
        case .systemBlue:     return "System Blue"
        case .pitchGreen:     return "Pitch Green"
        case .gridironOrange: return "Gridiron Orange"
        case .ice:            return "Ice"
        case .crimson:        return "Crimson"
        case .gold:           return "Gold"
        case .purple:         return "Purple"
        case .teal:           return "Teal"
        case .pink:           return "Pink"
        case .graphite:       return "Graphite"
        case .mint:           return "Mint"
        case .team:           return "Team Colors"
        case .custom:         return "Custom"
        }
    }

    /// sRGB hex for a curated accent. Nil for `systemBlue` (the asset-catalog
    /// accent, which adapts to dark mode) and for `team` / `custom`.
    var curatedHex: Int? {
        switch self {
        case .systemBlue:     return nil
        case .pitchGreen:     return 0x1F9D55
        case .gridironOrange: return 0xE8731A
        case .ice:            return 0x4FB3D9
        case .crimson:        return 0xD0263E
        case .gold:           return 0xD4A017
        case .purple:         return 0x8A4FD8
        case .teal:           return 0x14A3A3
        case .pink:           return 0xE84393
        case .graphite:       return 0x6B7280
        case .mint:           return 0x3CCFAA
        case .team, .custom:  return nil
        }
    }

    /// Swatch color for a curated accent (`systemBlue` renders as the app accent).
    var swatch: Color {
        curatedHex.map(Color.init(accentHex:)) ?? .accentColor
    }
}

/// Keys and the shared read path for the published accent.
enum AppAccentReader {
    /// App-group suite shared by the app and its widget extension. The Watch has
    /// no app group; it mirrors the value into its standard defaults via
    /// WatchConnectivity, so on watchOS the reader looks there instead.
    static let suiteName = "group.Komodo.SportsCal"

    /// The effective accent as 0xRRGGBB, or absent for the default (system blue).
    /// Written only by the app (`ThemeStore`), after applying the Pro gate.
    static let effectiveHexKey = "theme.effectiveAccentHex"

    static var sharedDefaults: UserDefaults? {
        #if os(watchOS)
        return .standard
        #else
        return UserDefaults(suiteName: suiteName)
        #endif
    }

    /// The published accent hex, or nil for the default look.
    static func effectiveHex(in defaults: UserDefaults? = sharedDefaults) -> Int? {
        guard let defaults, defaults.object(forKey: effectiveHexKey) != nil else { return nil }
        let value = defaults.integer(forKey: effectiveHexKey)
        return value >= 0 ? value : nil
    }

    /// The published accent, or nil for the default (callers fall back to
    /// `Color.accentColor`, which keeps the untouched default look).
    static func effectiveColor(in defaults: UserDefaults? = sharedDefaults) -> Color? {
        effectiveHex(in: defaults).map(Color.init(accentHex:))
    }
}

extension Color {
    /// 0xRRGGBB → sRGB color.
    nonisolated init(accentHex hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
