//
//  CompactGameTile.swift
//  SportsCal — Design System v1.0
//
//  Half-width grid tile for "Also Live" two-up grids. Smaller, denser
//  variant of LiveGameRow — no leverage tag, no subtext, just status +
//  matchup + score. Sport accent stripe on the leading edge.
//

import SwiftUI
import SportsCalModel
import NukeUI

public struct CompactGameTile: View {
    public enum State { case live, pre, final }

    public let sport: SportType
    public let state: State
    public let shortStatus: String      // "4Q · 2:11" / "7:30 PM" / "FINAL"
    public let matchup: String          // "MIA · DEN"
    public let scoreLine: String?       // "98 — 94"; nil for pre
    public var awayBadgeURL: URL? = nil
    public var homeBadgeURL: URL? = nil

    public init(
        sport: SportType,
        state: State,
        shortStatus: String,
        matchup: String,
        scoreLine: String?,
        awayBadgeURL: URL? = nil,
        homeBadgeURL: URL? = nil
    ) {
        self.sport = sport
        self.state = state
        self.shortStatus = shortStatus
        self.matchup = matchup
        self.scoreLine = scoreLine
        self.awayBadgeURL = awayBadgeURL
        self.homeBadgeURL = homeBadgeURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if state == .live {
                    Circle().fill(Color.appLive).frame(width: 5, height: 5)
                }
                Text(shortStatus)
                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(state == .live ? Color.appLive : Color.appInkFaint)
            }
            HStack(spacing: 5) {
                if awayBadgeURL != nil || homeBadgeURL != nil {
                    miniBadgePair
                }
                Text(matchup)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            // Always reserve the score row's height so adjacent tiles in a grid
            // line up — even when one has scores and a neighbour doesn't.
            Group {
                if let scoreLine {
                    Text(scoreLine)
                        .font(.system(.callout, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                } else if state == .pre {
                    Text("vs")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.appInkFaint)
                } else {
                    // .live / .final without scores: keep the row height,
                    // leave it visually empty (the shortStatus row carries state).
                    Text(" ")
                        .font(.system(.callout, design: .rounded).weight(.heavy))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.appSpace3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle.appShape(.appRadiusSM)
                .fill(Color.appAlt)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.app(sport))
                .frame(width: 2)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle.appShape(.appRadiusSM))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(matchup), \(scoreLine ?? "upcoming"), \(shortStatus)"))
    }

    /// Overlapping mini-badge pair (away on top of home) preceding the
    /// matchup text. Tight enough to fit in a half-width grid tile without
    /// pushing the matchup string off-screen.
    private var miniBadgePair: some View {
        HStack(spacing: -4) {
            badge(awayBadgeURL).zIndex(1)
            badge(homeBadgeURL)
        }
    }

    @ViewBuilder
    private func badge(_ url: URL?) -> some View {
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Circle().fill(Color.appAlt)
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.appBackground, lineWidth: 1))
        }
    }
}
