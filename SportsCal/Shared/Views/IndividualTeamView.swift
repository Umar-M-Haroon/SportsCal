//
//  IndividualTeamView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import SportsCalModel
import NukeUI

private func resolvedBadgeURL(_ urlString: String) -> URL? {
    if urlString.contains("thesportsdb.com") {
        return URL(string: urlString + "/preview")
    }
    return URL(string: urlString)
}

/// A team name with its seed or rank. A playoff seed reads "(5) Bills"; a college
/// AP / CFP rank is a small raised number before the name, the way polls print it,
/// so it isn't mistaken for a seed.
enum SeededName {
    static func text(_ name: String, seed: Int?, isRank: Bool) -> Text {
        guard let seed else { return Text(name) }
        guard isRank else { return Text("(\(seed)) \(name)") }
        let rank = Text("\(seed)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .baselineOffset(4)
        return Text("\(rank)\u{2009}\(name)")
    }

    /// "Number 5 Ohio State" / "5 seed Bills", for an accessibility label.
    static func spoken(_ name: String, seed: Int?, isRank: Bool) -> String {
        guard let seed else { return name }
        return isRank ? "Number \(seed) \(name)" : "\(seed) seed \(name)"
    }
}

struct IndividualTeamView: View {
    var teamURL: String?
    var shortName: String?
    var longName: String?
    var score: Int?
    var isWinning: Bool
    var isAway: Bool
    var record: String? = nil
    var seed: Int? = nil
    /// The seed is a college poll rank (see `SeededName`).
    var seedIsRank: Bool = false
    /// Soccer red cards, drawn as a card glyph beside the name.
    var redCards: Int = 0
    var data: Data? = nil
    /// Score / fallback-code sizes track Dynamic Type; 24pt / 14pt at the default size.
    @ScaledMetric(relativeTo: .title2) private var scoreSize: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var codeSize: CGFloat = 14
    // Fallback logo view when URL is missing
    private var fallbackLogo: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)
            if let shortName {
                Text(Team.shortCode(strTeamShort: nil, name: shortName))
                    .font(.system(size: codeSize, weight: .bold))
                    .foregroundColor(.secondary)
            } else if let longName {
                Text(Team.shortCode(strTeamShort: nil, name: longName))
                    .font(.system(size: codeSize, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                if !isAway {
                    if let score = score, isWinning {
                        Text("\(score)")
                            .font(.system(size: scoreSize))
                            .fontWeight(.heavy)
                            .lineLimit(1)
                            .fixedSize()
                    } else if let score = score, !isWinning  {
                        Text("\(score)")
                            .font(.system(size: scoreSize))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let teamURL {
                        LazyImage(request: ImageRequest(url: resolvedBadgeURL(teamURL), processors: [.resize(size: CGSize(width: 40, height: 40))])) { state in
                            if let image = state.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                            } else if state.error != nil {
                                // Show fallback if image load fails
                                fallbackLogo
                            } else {
                                ProgressView()
                            }
                        }
                    } else if let data {
                        #if os(iOS)
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #else
                        if let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #endif
                    } else {
                        // Show fallback when no URL or data
                        fallbackLogo
                    }
                } else {
                    if let teamURL {
                        LazyImage(request: ImageRequest(url: resolvedBadgeURL(teamURL), processors: [.resize(size: CGSize(width: 40, height: 40))])) { state in
                            if let image = state.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                            } else if state.error != nil {
                                // Show fallback if image load fails
                                fallbackLogo
                            } else {
                                ProgressView()
                            }
                        }
                    } else if let data {
                        #if os(iOS)
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #else
                        if let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        #endif
                    } else {
                        // Show fallback when no URL or data
                        fallbackLogo
                    }
                    if let score = score, isWinning {
                        Text("\(score)")
                            .font(.system(size: scoreSize))
                            .fontWeight(.heavy)
                            .lineLimit(1)
                            .fixedSize()
                    } else if let score = score, !isWinning  {
                        Text("\(score)")
                            .font(.system(size: scoreSize))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            if let name = shortName ?? longName {
                HStack(spacing: 4) {
                    if !isAway { redCardMark }
                    // One line, shrunk to fit: wrapping let SwiftUI break a long word
                    // mid-way ("Vanderbilt Com-modores").
                    SeededName.text(name, seed: seed, isRank: seedIsRank)
                        .font(.headline)
                        .fontWeight(isWinning ? .bold : .regular)
                        .foregroundColor(isWinning ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(shortName != nil ? 0.7 : 0.6)
                        .allowsTightening(true)
                    if isAway { redCardMark }
                }
                .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            }
            if let record {
                Text(record)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            }
        }
    }
}

extension IndividualTeamView {
    @ViewBuilder
    fileprivate var redCardMark: some View {
        if redCards > 0 {
            SoccerRedCardMark(count: redCards)
        }
    }
}

/// A red card, with a count past one. Sits beside a team's name on rows.
struct SoccerRedCardMark: View {
    let count: Int

    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.red)
                .frame(width: 7, height: 10)
            if count > 1 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(count == 1 ? "1 red card" : "\(count) red cards")
    }
}

#Preview {
    IndividualTeamView(isWinning: false, isAway: true)
}
