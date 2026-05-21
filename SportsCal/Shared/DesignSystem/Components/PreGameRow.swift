//
//  PreGameRow.swift
//  SportsCal — Design System v1.0
//
//  Upcoming game row. NO em-dash placeholder for a missing score (per
//  chat4 of the design handoff) — instead shows kickoff time + countdown
//  with a "vs" between teams.
//

import SwiftUI
import SportsCalModel
import NukeUI

public struct PreGameRow: View {
    public let sport: SportType
    public let matchup: String          // "JUV vs NAP"
    public let kickoffLabel: String     // "8:00 PM ET"
    public var countdown: String? = nil // "in 1h 14m"
    public var contextLine: String? = nil // "AL East · 2.5 GB"
    public var awayBadgeURL: URL? = nil
    public var homeBadgeURL: URL? = nil

    public init(
        sport: SportType,
        matchup: String,
        kickoffLabel: String,
        countdown: String? = nil,
        contextLine: String? = nil,
        awayBadgeURL: URL? = nil,
        homeBadgeURL: URL? = nil
    ) {
        self.sport = sport
        self.matchup = matchup
        self.kickoffLabel = kickoffLabel
        self.countdown = countdown
        self.contextLine = contextLine
        self.awayBadgeURL = awayBadgeURL
        self.homeBadgeURL = homeBadgeURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            HStack {
                Text(eyebrow).appEyebrow()
                Spacer()
                Text("UPCOMING")
                    .font(.appCaption)
                    .tracking(1)
                    .foregroundStyle(Color.appInkFaint)
            }
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if awayBadgeURL != nil || homeBadgeURL != nil {
                        preBadgePair(awayBadgeURL: awayBadgeURL, homeBadgeURL: homeBadgeURL)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(matchup).font(.appHeadline)
                        if let contextLine {
                            Text(contextLine)
                                .font(.appCallout)
                                .foregroundStyle(Color.appInkSoft)
                        }
                    }
                }
                Spacer()
                Image(systemName: "clock")
                    .foregroundStyle(Color.app(sport))
                    .imageScale(.small)
            }
        }
        .appCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(matchup), starts \(eyebrow)"))
    }

    private var eyebrow: String {
        if let countdown { return "\(kickoffLabel) · \(countdown)" }
        return kickoffLabel
    }
}

/// Overlapping mini-badge pair for `PreGameRow`. Same shape as the
/// `rowBadgePair` helper in `LiveGameRow.swift` — duplicated rather than
/// extracted so each row component file stays self-contained without
/// adding a new file to the Xcode project. `@MainActor` because
/// `LazyImage` is itself main-actor-isolated.
@MainActor
@ViewBuilder
fileprivate func preBadgePair(awayBadgeURL: URL?, homeBadgeURL: URL?) -> some View {
    HStack(spacing: -6) {
        preBadge(awayBadgeURL).zIndex(1)
        preBadge(homeBadgeURL)
    }
}

@MainActor
@ViewBuilder
fileprivate func preBadge(_ url: URL?) -> some View {
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
