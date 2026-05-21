//
//  FinalGameRow.swift
//  SportsCal — Design System v1.0
//
//  Final-score row. Winner gets primary ink, loser fades to soft ink.
//  Result line summarizes ("FINAL · BOS won by 6").
//

import SwiftUI
import SportsCalModel
import NukeUI

public struct FinalGameRow: View {
    public let sport: SportType
    public let homeAbbr: String
    public let awayAbbr: String
    public let homeScore: Int
    public let awayScore: Int
    public var resultLine: String? = nil  // override; otherwise auto-generated
    public var awayBadgeURL: URL? = nil
    public var homeBadgeURL: URL? = nil

    public init(
        sport: SportType,
        homeAbbr: String,
        awayAbbr: String,
        homeScore: Int,
        awayScore: Int,
        resultLine: String? = nil,
        awayBadgeURL: URL? = nil,
        homeBadgeURL: URL? = nil
    ) {
        self.sport = sport
        self.homeAbbr = homeAbbr
        self.awayAbbr = awayAbbr
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.resultLine = resultLine
        self.awayBadgeURL = awayBadgeURL
        self.homeBadgeURL = homeBadgeURL
    }

    private var homeWon: Bool { homeScore > awayScore }
    private var margin: Int { abs(homeScore - awayScore) }
    private var summary: String {
        if let resultLine { return resultLine }
        if homeScore == awayScore { return "FINAL · TIE" }
        let winner = homeWon ? homeAbbr : awayAbbr
        return "FINAL · \(winner) won by \(margin)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .appSpace3) {
            Text(summary).appEyebrow()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    teamLine(name: homeAbbr, badgeURL: homeBadgeURL, won: homeWon)
                    teamLine(name: awayAbbr, badgeURL: awayBadgeURL, won: !homeWon && homeScore != awayScore)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(homeScore)")
                        .font(.appScore)
                        .foregroundStyle(homeWon ? Color.appInk : .appInkSoft)
                    Text("\(awayScore)")
                        .font(.appScore)
                        .foregroundStyle(homeWon ? .appInkSoft : Color.appInk)
                }
            }
        }
        .appCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(summary), \(homeAbbr) \(homeScore), \(awayAbbr) \(awayScore)"))
    }

    private func teamLine(name: String, badgeURL: URL?, won: Bool) -> some View {
        HStack(spacing: 6) {
            if let badgeURL {
                LazyImage(url: badgeURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Circle().fill(Color.appAlt)
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())
            }
            Text(name)
                .font(.appHeadline)
                .foregroundStyle(won ? Color.appInk : .appInkSoft)
        }
    }
}
