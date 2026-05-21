//
//  WatchDesignTokens.swift
//  SportsCalWatch Watch App — Design System (Phase I, minimum viable)
//
//  Mirrors the iOS-side `Color.app*` / `Font.app*` tokens so the watch
//  app can adopt the same visual language. The full DesignSystem/
//  folder is a member of the iOS app target only — promoting it to a
//  shared SPM module is queued as follow-up. Until then, this file
//  duplicates the subset the watch needs.
//

import SwiftUI
import SportsCalModel

enum WatchTokens {
    // Surfaces — adaptive by current scheme on watchOS 10+
    static let background = Color(light: 0xF7F5F0, dark: 0x0E1014)
    static let surface = Color(light: 0xFFFFFF, dark: 0x171A21)
    static let alt = Color(light: 0xEFECE4, dark: 0x1F232C)
    static let ink = Color(light: 0x1A1612, dark: 0xF4F3EE)
    static let inkSoft = Color(light: 0x1A1612, dark: 0xF4F3EE).opacity(0.62)
    static let inkFaint = Color(light: 0x1A1612, dark: 0xF4F3EE).opacity(0.36)
    static let live = Color(light: 0xD63B2F, dark: 0xFF5D52)
    static let star = Color(light: 0xA87613, dark: 0xFFD966)

    // Sport accents — same OKLCH palette as iOS
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
    static func sportTint(_ sport: SportType) -> Color { sport.tinted }

    // Spacing — same scale as iOS appSpace*
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16

    // watchOS hit target minimum (smaller than iOS)
    static let hit: CGFloat = 32

    // Radii
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
}

private extension SportType {
    var tinted: Color { WatchTokens.sport(self).opacity(0.18) }
}

// MARK: - Color hex helper
//
// watchOS doesn't expose `UIColor(dynamicProvider:)` or
// `userInterfaceStyle`, so the watch palette is dark-only — which
// matches how watchOS is overwhelmingly used in practice. If/when
// system-style light surfaces matter, switch to env-driven resolution
// at the call site via `@Environment(\.colorScheme)`.
private extension Color {
    init(light: Int, dark: Int) {
        // Always pick dark on watchOS.
        self.init(rgbHex: dark)
    }
    init(rgbHex: Int) {
        self.init(.sRGB,
                  red: Double((rgbHex >> 16) & 0xFF) / 255,
                  green: Double((rgbHex >> 8) & 0xFF) / 255,
                  blue: Double(rgbHex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Live tag (watchOS-sized)

struct WatchLiveTag: View {
    let period: String?      // "Q4", "73'", etc.

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(WatchTokens.live)
                .frame(width: 5, height: 5)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text("LIVE\(period.map { " · \($0)" } ?? "")")
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(WatchTokens.live)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Live\(period.map { ", \($0)" } ?? "")"))
    }
}

// MARK: - Empty state (watchOS-sized)

struct WatchEmptyState: View {
    let symbol: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: WatchTokens.space2) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WatchTokens.inkSoft)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(.caption2))
                    .foregroundStyle(WatchTokens.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(WatchTokens.space3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(detail.map { "\(title). \($0)" } ?? title))
    }

    // Common presets — match iOS Phase E catalog
    static var quietDay: WatchEmptyState {
        WatchEmptyState(symbol: "sportscourt",
                        title: "No games today",
                        detail: "Check back later or open SportsCal on iPhone.")
    }
    static var noFavorites: WatchEmptyState {
        WatchEmptyState(symbol: "heart.slash",
                        title: "No favorites",
                        detail: "Add teams on iPhone to see them here.")
    }
    static var offline: WatchEmptyState {
        WatchEmptyState(symbol: "wifi.slash",
                        title: "Offline",
                        detail: "Re-sync once you're back online.")
    }
    static var reachabilityLost: WatchEmptyState {
        WatchEmptyState(symbol: "iphone.gen3.slash",
                        title: "Open SportsCal on iPhone",
                        detail: "Your watch can't reach your phone.")
    }
}
