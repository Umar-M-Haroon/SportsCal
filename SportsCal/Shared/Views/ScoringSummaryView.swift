//
//  ScoringSummaryView.swift
//  SportsCal
//
//  The "Scoring Summary" card in game detail, above the full play-by-play: football
//  scores by quarter, hockey goals by period (scorer, assists, PP/SH/EN) with the
//  penalties folded underneath, baseball runs by inning. Data rides with the
//  play-by-play fetch; see `ScoringSummary`.
//

import SwiftUI
import SportsCalModel

// MARK: - Section (card chrome)

struct ScoringSummarySection: View {
    let summary: ScoringSummary?
    let game: Game
    let homeName: String
    let awayName: String
    let homeColor: Color
    let awayColor: Color

    var body: some View {
        if let summary, !summary.entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Scoring Summary").font(.headline)
                ScoringSummaryView(
                    summary: summary, game: game,
                    homeName: homeName, awayName: awayName,
                    homeColor: homeColor, awayColor: awayColor
                )
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }
}

// MARK: - Summary

struct ScoringSummaryView: View {
    let summary: ScoringSummary
    let game: Game
    let homeName: String
    let awayName: String
    private let rawHomeColor: Color
    private let rawAwayColor: Color

    @Environment(\.self) private var environment
    @State private var showsPenalties = false

    init(summary: ScoringSummary, game: Game, homeName: String, awayName: String, homeColor: Color, awayColor: Color) {
        self.summary = summary
        self.game = game
        self.homeName = homeName
        self.awayName = awayName
        self.rawHomeColor = homeColor
        self.rawAwayColor = awayColor
    }

    private var scores: ScoringSummary { ScoringSummary(entries: summary.entries.filter { !$0.isPenalty }) }
    private var penalties: ScoringSummary { ScoringSummary(entries: summary.entries.filter(\.isPenalty)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let groups = scores.byPeriod
            if groups.isEmpty {
                Text("No scoring yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.period) { group in
                periodBlock(title: periodTitle(group.period), entries: group.entries)
            }

            if !penalties.entries.isEmpty {
                DisclosureGroup(isExpanded: $showsPenalties) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(penalties.byPeriod, id: \.period) { group in
                            periodBlock(title: periodTitle(group.period), entries: group.entries)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Penalties (\(penalties.entries.count))")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private func periodBlock(title: String, entries: [ScoringSummary.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(entries) { entry in
                EntryRow(
                    entry: entry,
                    teamName: name(for: entry),
                    tint: color(for: entry),
                    halfLabel: game.sportType == .mlb ? entry.half.map(Self.halfLabel) : nil
                )
            }
        }
    }

    private func name(for entry: ScoringSummary.Entry) -> String {
        switch entry.side {
        case "home": return homeName
        case "away": return awayName
        default: return entry.teamAbbreviation ?? ""
        }
    }

    private func color(for entry: ScoringSummary.Entry) -> Color {
        let raw: Color
        switch entry.side {
        case "home": raw = rawHomeColor
        case "away": raw = rawAwayColor
        default: raw = .secondary
        }
        return raw.legible(in: environment)
    }

    /// "1st Period", "2nd Quarter", "3rd Inning", "OT", "Shootout".
    private func periodTitle(_ period: Int) -> String {
        if period == -1 { return "Shootout" }
        let label = game.periodLabel(period)
        let regulation = game.leagueValue?.regulationPeriods ?? 0
        guard period <= regulation else { return label == "SO" ? "Shootout" : label }
        let ordinal = ClutchMoment.ordinal(period)
        switch game.sportType {
        case .mlb: return "\(ordinal) Inning"
        case .hockey: return "\(ordinal) Period"
        default: return "\(ordinal) Quarter"
        }
    }

    private static func halfLabel(_ half: String) -> String {
        half == "Bottom" ? "Bot" : half
    }
}

// MARK: - One entry

private struct EntryRow: View {
    let entry: ScoringSummary.Entry
    let teamName: String
    let tint: Color
    let halfLabel: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(teamName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(entry.isPenalty ? .secondary : tint)
                .frame(minWidth: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                headline
                if let assists = entry.assists, !assists.isEmpty {
                    Text("Assists: " + assists.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !entry.isPenalty, !entry.isShootout, let away = entry.awayScore, let home = entry.homeScore {
                Text("\(away)–\(home)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var headline: some View {
        if let player = entry.player {
            // Hockey: "J. Farabee · Snap Shot" or "D. Severson · Tripping".
            let name = Text(player).fontWeight(entry.isPenalty ? .regular : .semibold)
            let detail = Text(entry.text).foregroundStyle(.secondary)
            Text("\(name)  \(detail)")
                .font(.caption)
                .foregroundStyle(entry.isPenalty ? .secondary : .primary)
        } else {
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(entry.isPenalty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var meta: some View {
        let parts = metaParts
        if !parts.isEmpty || !(entry.tags ?? []).isEmpty {
            HStack(spacing: 6) {
                ForEach(entry.tags ?? [], id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.15), in: Capsule())
                }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let halfLabel { parts.append(halfLabel) }
        if let clock = entry.clock, !clock.isEmpty { parts.append(clock) }
        if let minutes = entry.penaltyMinutes { parts.append("\(minutes) min") }
        return parts
    }

    private var accessibilityLabel: String {
        var parts: [String] = [teamName]
        if let player = entry.player { parts.append(player) }
        parts.append(entry.text)
        if let assists = entry.assists, !assists.isEmpty {
            parts.append("assisted by " + assists.joined(separator: " and "))
        }
        for tag in entry.tags ?? [] { parts.append(Self.spokenTag(tag)) }
        if let halfLabel { parts.append(halfLabel == "Bot" ? "bottom half" : "top half") }
        if let clock = entry.clock, !clock.isEmpty { parts.append("at \(clock)") }
        if let minutes = entry.penaltyMinutes { parts.append("\(minutes) minutes") }
        if !entry.isPenalty, !entry.isShootout, let away = entry.awayScore, let home = entry.homeScore {
            parts.append("score \(away) to \(home)")
        }
        return parts.joined(separator: ", ")
    }

    private static func spokenTag(_ tag: String) -> String {
        switch tag {
        case "PP": return "power play"
        case "SH": return "shorthanded"
        case "EN": return "empty net"
        case "SO": return "shootout"
        case "TD": return "touchdown"
        case "FG": return "field goal"
        case "SF": return "safety"
        default: return tag
        }
    }
}
