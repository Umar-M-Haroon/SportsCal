//
//  WorldCupScorersView.swift
//  SportsCal
//
//  Golden Boot race — top scorers for the World Cup.
//

import SwiftUI
import SportsCalModel

struct WorldCupScorersView: View {
    let scorers: [WorldCupScorer]
    private var accent: Color { .app(.soccer) }

    var body: some View {
        VStack(alignment: .leading, spacing: .appSpace3) {
            ForEach(Array(scorers.enumerated()), id: \.offset) { _, scorer in
                row(scorer)
                if scorer.rank < scorers.count {
                    Divider().background(Color.appDivider)
                }
            }
        }
    }

    private func row(_ scorer: WorldCupScorer) -> some View {
        HStack(spacing: .appSpace3) {
            Text("\(scorer.rank)")
                .font(.appFootnote)
                .foregroundStyle(Color.appInkFaint)
                .frame(width: 22, alignment: .leading)
            HeadshotView(url: scorer.headshotURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(scorer.playerName)
                    .font(.appCallout)
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    WCBadge(url: scorer.teamBadge, size: 14)
                    Text(scorer.teamName)
                        .font(.appCaption)
                        .foregroundStyle(Color.appInkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: .appSpace2)
            HStack(spacing: 4) {
                Text("\(scorer.goals)")
                    .font(.appTitle)
                    .foregroundStyle(accent)
                Image(systemName: "soccerball")
                    .font(.caption)
                    .foregroundStyle(Color.appInkFaint)
            }
        }
    }
}

/// Full-screen scorers list (pushed from the hub "See all").
struct WorldCupScorersScreen: View {
    let scorers: [WorldCupScorer]

    var body: some View {
        ScrollView {
            WorldCupScorersView(scorers: scorers)
                .padding(.appSpace4)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Golden Boot")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }
}
