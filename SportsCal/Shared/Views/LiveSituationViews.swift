//
//  LiveSituationViews.swift
//  SportsCal
//
//  The live game-state strip — bases and outs, down and distance, win probability —
//  and the "worth watching" badge. Theme-neutral building blocks: they take colors
//  and short names rather than reaching for a theme, so the classic, Modern and
//  Ambient rows, the detail screens and the Live Activity can all use them.
//
//  Compiled into the app and the widget extension (Live Activity).
//

import SwiftUI
import SportsCalModel

// MARK: - Bases

/// Three bases as a diamond, filled when occupied.
struct BaseDiamond: View {
    var first: Bool
    var second: Bool
    var third: Bool
    var size: CGFloat = 16
    var tint: Color = .primary

    var body: some View {
        // Each base is a square turned 45°, so it spans its diagonal. Lay the three out
        // on a diamond whose half-width is a little over one diagonal, so they read as
        // separate bases rather than a cluster.
        let diagonal = size / 2.3
        let side = diagonal / 2.squareRoot()
        let spread = diagonal * 0.65
        ZStack {
            base(second, side: side).offset(y: -spread / 2)
            base(third, side: side).offset(x: -spread, y: spread / 2)
            base(first, side: side).offset(x: spread, y: spread / 2)
        }
        .frame(width: size, height: diagonal + spread)
        .accessibilityElement()
        .accessibilityLabel(Self.accessibilityText(first: first, second: second, third: third))
    }

    private func base(_ occupied: Bool, side: CGFloat) -> some View {
        Rectangle()
            .fill(occupied ? tint : .clear)
            .overlay(Rectangle().strokeBorder(tint.opacity(occupied ? 1 : 0.45), lineWidth: max(1, side * 0.16)))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(45))
    }

    static func accessibilityText(first: Bool, second: Bool, third: Bool) -> String {
        switch (first, second, third) {
        case (false, false, false): return "Bases empty"
        case (true, true, true): return "Bases loaded"
        default:
            let on = [(first, "first"), (second, "second"), (third, "third")].filter(\.0).map(\.1)
            return "Runner\(on.count > 1 ? "s" : "") on " + ListFormatter.localizedString(byJoining: on)
        }
    }
}

/// Outs as three dots, filled per out.
struct OutsIndicator: View {
    var outs: Int
    var dotSize: CGFloat = 5
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: dotSize * 0.6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < outs ? tint : tint.opacity(0.22))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(outs) out\(outs == 1 ? "" : "s")")
    }
}

// MARK: - Team colors

extension Color {
    /// A team color that stays visible against the current background: near-black
    /// colors (Steelers, Guardians navy) lift toward white in dark mode, near-white
    /// ones darken in light mode. Other colors pass through.
    func legible(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.linearRed)
            + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
        switch environment.colorScheme {
        case .dark where luminance < 0.06:
            return mix(with: .white, by: 0.45)
        case .light where luminance > 0.7:
            return mix(with: .black, by: 0.35)
        default:
            return self
        }
    }
}

// MARK: - Win probability

/// A two-tone bar split at the home side's win probability: away on the left, home
/// on the right, matching the away-left layout of every row.
struct WinProbabilityBar: View {
    /// Home win probability, 0...1.
    var home: Double
    var homeColor: Color
    var awayColor: Color
    var height: CGFloat = 4

    @Environment(\.self) private var environment

    var body: some View {
        GeometryReader { proxy in
            let homeWidth = proxy.size.width * min(max(home, 0), 1)
            HStack(spacing: 1) {
                Rectangle().fill(awayColor.legible(in: environment))
                Rectangle().fill(homeColor.legible(in: environment)).frame(width: homeWidth)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.4), value: home)
        .accessibilityHidden(true)
    }
}

/// "KC 62%" — the favourite and their chance. With `showsIcon`, a trend glyph leads
/// so a bare percentage in a score row isn't mistaken for part of the score.
struct WinProbabilityLabel: View {
    var home: Double
    /// Draw probability, where a draw is possible; the away side gets what's left.
    var tie: Double? = nil
    var homeName: String
    var awayName: String
    var showsIcon: Bool = false

    var body: some View {
        let away = max(0, 1 - home - (tie ?? 0))
        let homeFavored = home >= away
        let percent = Int((max(home, away) * 100).rounded())
        HStack(spacing: 3) {
            if showsIcon {
                Image(systemName: "chart.line.uptrend.xyaxis").imageScale(.small)
            }
            Text("\(homeFavored ? homeName : awayName) \(percent)%")
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(homeFavored ? homeName : awayName), \(percent) percent to win")
    }
}

// MARK: - Strip

/// One line of live game state for a list row: runners, outs and the count in
/// baseball; down, distance and the ball in football; win probability where the feed
/// has it. Renders nothing when there's nothing to say.
struct GameStateStrip: View {
    let situation: GameSituation
    let sport: SportType?
    var homeName: String
    var awayName: String
    var tint: Color = .secondary

    var body: some View {
        if hasContent {
            HStack(spacing: 8) {
                if sport == .mlb, situation.hasBaseballState {
                    baseball
                } else if sport == .nfl, situation.hasFootballState {
                    football
                }
                if let home = situation.homeWinProbability {
                    WinProbabilityLabel(home: home, tie: situation.tieProbability,
                                        homeName: homeName, awayName: awayName, showsIcon: true)
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
        }
    }

    private var hasContent: Bool {
        (sport == .mlb && situation.hasBaseballState)
            || (sport == .nfl && situation.hasFootballState)
            || situation.homeWinProbability != nil
    }

    @ViewBuilder
    private var baseball: some View {
        BaseDiamond(first: situation.onFirst == true, second: situation.onSecond == true,
                    third: situation.onThird == true, size: 20, tint: tint)
        if let outs = situation.outs {
            OutsIndicator(outs: outs, tint: tint)
        }
    }

    @ViewBuilder
    private var football: some View {
        if let side = situation.possession {
            HStack(spacing: 3) {
                Image(systemName: "football.fill").imageScale(.small)
                Text(side == .home ? homeName : awayName)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(side == .home ? homeName : awayName) ball")
        }
        if let text = situation.shortDownDistanceText ?? situation.downDistanceText {
            Text(text).lineLimit(1)
        }
        if situation.isRedZone == true {
            Text("RED ZONE")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.red, in: Capsule())
        }
    }
}

// MARK: - Live Activity strip

/// The strip for a Live Activity, from the coarser `LiveActivitySituation` the push
/// payload carries.
struct LiveActivitySituationStrip: View {
    let situation: LiveActivitySituation
    var homeName: String
    var awayName: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            if situation.outs != nil || situation.bases != nil {
                BaseDiamond(first: situation.onFirst, second: situation.onSecond, third: situation.onThird, size: 18, tint: tint)
                if let outs = situation.outs {
                    OutsIndicator(outs: outs, dotSize: 4.5, tint: tint)
                }
            }
            if let side = situation.possession {
                HStack(spacing: 3) {
                    Image(systemName: "football.fill").imageScale(.small)
                    Text(side == .home ? homeName : awayName)
                }
            }
            if let text = situation.downDistance {
                Text(text).lineLimit(1)
            }
            if situation.redZone == true {
                Text("RED ZONE")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
            }
            if let percent = situation.homeWinPct {
                WinProbabilityLabel(home: Double(percent) / 100, homeName: homeName, awayName: awayName, showsIcon: true)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
    }
}

// MARK: - Worth watching

/// Badge for a finished game that was worth watching. Says how tense it was, never
/// who won, so it's safe on a score-hidden list.
struct ExcitementBadge: View {
    let tier: ExcitementTier

    var body: some View {
        if tier.isWorthWatching {
            HStack(spacing: 3) {
                Image(systemName: tier == .classic ? "flame.fill" : "bolt.fill")
                    .imageScale(.small)
                Text(tier.displayName)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tier.displayName)
        }
    }
}
