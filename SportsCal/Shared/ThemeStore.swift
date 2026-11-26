//
//  ThemeStore.swift
//  SportsCal
//
//  Owns the Themes (Pro) selection: accent color and alternate app icon.
//
//  The selection persists in app-group defaults regardless of Pro status, so a
//  lapsed subscriber who renews gets their theme back. What the UI renders is the
//  *effective* accent: the selection while Pro, the default otherwise. The app
//  publishes that effective value (`AppAccentReader.effectiveHexKey`) for widgets,
//  Live Activities and the Watch, which never see the raw selection.
//

import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private enum Keys {
        static let accent = "theme.accent"
        static let customHex = "theme.customAccentHex"
        static let teamID = "theme.teamID"
        static let teamName = "theme.teamName"
        static let teamHex = "theme.teamAccentHex"
        static let liveActivityStyle = "theme.liveActivityStyle"
    }

    @ObservationIgnored private let defaults: UserDefaults?

    /// The chosen accent. Persisted on every change.
    var accent: AppAccent {
        didSet { defaults?.set(accent.rawValue, forKey: Keys.accent) }
    }

    /// The custom accent (0xRRGGBB) used when `accent == .custom`.
    var customHex: Int {
        didSet { defaults?.set(customHex, forKey: Keys.customHex) }
    }

    /// The chosen Live Activity style, kept through a lapse like the accent.
    var liveActivityStyle: LiveActivityStyle {
        didSet { defaults?.set(liveActivityStyle.rawValue, forKey: Keys.liveActivityStyle) }
    }

    /// The favorite team whose color `accent == .team` uses, with the color captured
    /// when it was picked (teams carry no color of their own; it comes from games).
    private(set) var teamID: String?
    private(set) var teamName: String?
    private(set) var teamHex: Int?

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppAccentReader.suiteName)) {
        self.defaults = defaults
        accent = defaults?.string(forKey: Keys.accent).flatMap(AppAccent.init(rawValue:)) ?? .systemBlue
        customHex = (defaults?.object(forKey: Keys.customHex) as? Int) ?? 0x8A4FD8
        liveActivityStyle = defaults?.string(forKey: Keys.liveActivityStyle).flatMap(LiveActivityStyle.init(rawValue:)) ?? .standard
        teamID = defaults?.string(forKey: Keys.teamID)
        teamName = defaults?.string(forKey: Keys.teamName)
        teamHex = defaults?.object(forKey: Keys.teamHex) as? Int
    }

    func setTeam(id: String, name: String, hex: Int) {
        teamID = id
        teamName = name
        teamHex = hex
        defaults?.set(id, forKey: Keys.teamID)
        defaults?.set(name, forKey: Keys.teamName)
        defaults?.set(hex, forKey: Keys.teamHex)
    }

    /// The hex a given accent resolves to, or nil for the default look.
    func hex(for accent: AppAccent) -> Int? {
        switch accent {
        case .systemBlue: return nil
        case .custom:     return customHex
        case .team:       return teamHex
        default:          return accent.curatedHex
        }
    }

    /// What the app should render: the selection for Pro users, else the default.
    func effectiveHex(isPro: Bool) -> Int? {
        isPro ? hex(for: accent) : nil
    }

    /// The Live Activity style to draw: the selection for Pro users, else standard.
    func effectiveLiveActivityStyle(isPro: Bool) -> LiveActivityStyle {
        isPro ? liveActivityStyle : .standard
    }

    /// Writes the effective accent and Live Activity style for widgets / Live
    /// Activities / Watch. No-op when unchanged, so every window can call it freely.
    func publish(isPro: Bool) {
        let style = effectiveLiveActivityStyle(isPro: isPro)
        if style != AppAccentReader.liveActivityStyle(in: defaults) {
            if style == .standard {
                defaults?.removeObject(forKey: AppAccentReader.effectiveLiveActivityStyleKey)
            } else {
                defaults?.set(style.rawValue, forKey: AppAccentReader.effectiveLiveActivityStyleKey)
            }
        }
        let newValue = effectiveHex(isPro: isPro)
        guard newValue != AppAccentReader.effectiveHex(in: defaults) else { return }
        if let newValue {
            defaults?.set(newValue, forKey: AppAccentReader.effectiveHexKey)
        } else {
            defaults?.removeObject(forKey: AppAccentReader.effectiveHexKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        PhoneWatchSyncService.shared.syncAllPreferences()
        #endif
    }
}

// MARK: - Accent color

extension Color {
    /// The app's UI accent: the user's Themes accent while they're Pro, the
    /// asset-catalog accent (system blue) otherwise. Use it for UI chrome —
    /// selection, links, highlights — never for sport, team, live or win/loss
    /// colors. Where a shape style will do, `.tint` reads the same value.
    ///
    /// Reading this inside a view's body registers Observation on `ThemeStore`
    /// and `SubscriptionManager`, so the view updates when the theme changes —
    /// in every window and sheet, with no environment plumbing.
    static var appAccent: Color {
        guard let hex = ThemeStore.shared.effectiveHex(isPro: SubscriptionManager.shared.canUse(.themes)) else {
            return .accentColor
        }
        return legibleAccent(hex)
    }

    /// Team and custom colors can be near-black or near-white; lift them toward
    /// white in dark mode / darken them in light mode so tinted text stays
    /// readable (same thresholds as `Color.legible(in:)`).
    static func legibleAccent(_ hex: Int) -> Color {
        let light = adjustedHex(hex, dark: false)
        let dark = adjustedHex(hex, dark: true)
        guard light != dark || light != hex else { return Color(accentHex: hex) }
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            UIColor(Color(accentHex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(accentHex: isDark ? dark : light))
        })
        #else
        return Color(accentHex: hex)
        #endif
    }

    private static func adjustedHex(_ hex: Int, dark: Bool) -> Int {
        func channel(_ shift: Int) -> Double { Double((hex >> shift) & 0xFF) / 255 }
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (channel(16), channel(8), channel(0))
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        func mix(_ target: Double, _ amount: Double) -> Int {
            func byte(_ c: Double) -> Int { Int(((c + (target - c) * amount) * 255).rounded()) }
            return (byte(r) << 16) | (byte(g) << 8) | byte(b)
        }
        if dark, luminance < 0.06 { return mix(1, 0.45) }
        if !dark, luminance > 0.7 { return mix(0, 0.35) }
        return hex
    }
}

/// Applies the effective accent to a window's root `.tint` and publishes it for
/// widgets / Live Activities / Watch. With the default accent the tint stays nil,
/// so system controls (switches, etc.) keep their stock colors — the default look
/// is unchanged.
struct AppAccentScope: ViewModifier {
    private var store: ThemeStore { .shared }
    private var subscriptions: SubscriptionManager { .shared }

    func body(content: Content) -> some View {
        let hex = store.effectiveHex(isPro: subscriptions.canUse(.themes))
        let style = store.effectiveLiveActivityStyle(isPro: subscriptions.canUse(.themes))
        content
            .tint(hex.map(Color.legibleAccent))
            .onChange(of: PublishedTheme(hex: hex, style: style), initial: true) { _, _ in
                store.publish(isPro: subscriptions.canUse(.themes))
            }
    }
}

private struct PublishedTheme: Equatable {
    let hex: Int?
    let style: LiveActivityStyle
}

extension View {
    /// Root accent for a window or scene. See `AppAccentScope`.
    func appAccentScope() -> some View { modifier(AppAccentScope()) }
}

// MARK: - Alternate app icons (iOS)

/// Alternate home-screen icons. `rawValue` is the asset-catalog app icon set name
/// (`AppIcon-<Name>`); `.standard` is the primary icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard = "AppIcon"
    case midnight = "AppIcon-Midnight"
    case crimson = "AppIcon-Crimson"
    case purple = "AppIcon-Purple"
    case graphite = "AppIcon-Graphite"
    case gold = "AppIcon-Gold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Classic"
        case .midnight: return "Midnight"
        case .crimson:  return "Crimson"
        case .purple:   return "Purple"
        case .graphite: return "Graphite"
        case .gold:     return "Gold"
        }
    }

    /// Name for `setAlternateIconName` (nil restores the primary icon).
    var alternateIconName: String? { self == .standard ? nil : rawValue }

    /// Body and header colors, for the in-app thumbnail (asset-catalog app icons
    /// can't be loaded as images, so the picker draws a miniature instead).
    var thumbnailColors: (body: Int, header: Int) {
        switch self {
        case .standard: return (0x1C7E4D, 0x154125)
        case .midnight: return (0x1E2E52, 0x0F172C)
        case .crimson:  return (0x922030, 0x560F1B)
        case .purple:   return (0x5E3698, 0x351D5E)
        case .graphite: return (0x484C54, 0x24262C)
        case .gold:     return (0xBE8E1E, 0x76540E)
        }
    }

    #if os(iOS)
    @MainActor
    static var current: AppIconChoice {
        guard let name = UIApplication.shared.alternateIconName else { return .standard }
        return AppIconChoice(rawValue: name) ?? .standard
    }

    @MainActor
    static var supported: Bool { UIApplication.shared.supportsAlternateIcons }

    @MainActor
    static func apply(_ choice: AppIconChoice) async throws {
        guard UIApplication.shared.alternateIconName != choice.alternateIconName else { return }
        try await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
    }

    /// A lapsed subscriber goes back to the primary icon (accent falls back on its
    /// own through `AppAccentScope`).
    @MainActor
    static func resetIfNotEntitled() {
        guard !SubscriptionManager.shared.canUse(.themes),
              UIApplication.shared.alternateIconName != nil else { return }
        Task { try? await apply(.standard) }
    }
    #endif
}
