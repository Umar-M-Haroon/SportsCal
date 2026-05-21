//
//  LiveGameRow.swift
//  SportsCal — Design System v1.0
//
//  Live game list row: pulsing LIVE eyebrow + score + matchup + optional
//  leverage tag. Model-agnostic — takes display strings, not Game struct,
//  so the same row works against any data source.
//

import SwiftUI
import SportsCalModel
import NukeUI

public struct LiveGameRow: View {
    public let sport: SportType
    public let matchup: String          // "BOS vs LAL" or "ARS · MCI"
    public let scoreLine: String        // "112 — 106"
    public let period: String           // "Q4"
    public let clock: String?           // "4:22"
    public var subtext: String? = nil   // "Tatum 38 · Davis 14R"
    public var leverageLabel: String? = nil
    public var leverageDelta: Int? = nil
    public var awayBadgeURL: URL? = nil
    public var homeBadgeURL: URL? = nil

    public init(
        sport: SportType,
        matchup: String,
        scoreLine: String,
        period: String,
        clock: String? = nil,
        subtext: String? = nil,
        leverageLabel: String? = nil,
        leverageDelta: Int? = nil,
        awayBadgeURL: URL? = nil,
        homeBadgeURL: URL? = nil
    ) {
        self.sport = sport
        self.matchup = matchup
        self.scoreLine = scoreLine
        self.period = period
        self.clock = clock
        self.subtext = subtext
        self.leverageLabel = leverageLabel
        self.leverageDelta = leverageDelta
        self.awayBadgeURL = awayBadgeURL
        self.homeBadgeURL = homeBadgeURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            HStack(spacing: .appSpace2) {
                LiveTag(period: period, clock: clock)
                Spacer()
                if let leverageLabel {
                    LeverageTag(label: leverageLabel, delta: leverageDelta)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if awayBadgeURL != nil || homeBadgeURL != nil {
                        rowBadgePair(awayBadgeURL: awayBadgeURL, homeBadgeURL: homeBadgeURL)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(matchup).font(.appHeadline)
                        if let subtext {
                            Text(subtext)
                                .font(.appCallout)
                                .foregroundStyle(Color.appInkSoft)
                        }
                    }
                }
                Spacer()
                Text(scoreLine)
                    .font(.appScore)
                    .foregroundStyle(Color.appInk)
            }
        }
        .appCard()
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.app(sport))
                .frame(width: 3)
                .clipShape(
                    RoundedRectangle.appShape(.appRadiusMD)
                )
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var voiceOverLabel: Text {
        let lev = leverageLabel.map { ", \($0)" } ?? ""
        let sub = subtext.map { ", \($0)" } ?? ""
        let clk = clock.map { " \($0)" } ?? ""
        return Text("Live, \(matchup), \(scoreLine), \(period)\(clk)\(sub)\(lev)")
    }
}

/// Overlapping mini-badge pair for row components. Away on top of home,
/// 22pt circles with a thin background stroke so they read on `.appAlt`
/// or `.appSurface` cards. `@MainActor` because `LazyImage` is itself
/// main-actor-isolated.
@MainActor
@ViewBuilder
fileprivate func rowBadgePair(awayBadgeURL: URL?, homeBadgeURL: URL?) -> some View {
    HStack(spacing: -6) {
        rowBadge(awayBadgeURL).zIndex(1)
        rowBadge(homeBadgeURL)
    }
}

@MainActor
@ViewBuilder
fileprivate func rowBadge(_ url: URL?) -> some View {
    if let url {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Circle().fill(Color.appAlt)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.appBackground, lineWidth: 1))
    }
}
