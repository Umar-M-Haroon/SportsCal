//
//  PlayerBoxScoreView.swift
//  SportsCal
//
//  The "Players" card in game detail: per-player stat tables for one team at a time
//  (starters then bench, forwards/defense, passing/rushing/receiving…, batting and
//  pitching), with a sticky name column and the stats scrolling sideways. Hockey
//  leads with both goalies' lines. Data rides with the play-by-play fetch
//  (`/plays/:eventID?players=1`); see `PlayerBoxScore`.
//

import SwiftUI
import SportsCalModel

// MARK: - Section (card chrome)

struct PlayerBoxScoreSection: View {
    let box: PlayerBoxScore?
    let sport: SportType?
    let homeName: String
    let awayName: String
    let homeColor: Color
    let awayColor: Color

    var body: some View {
        if let box, box.away != nil || box.home != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Players").font(.headline)
                PlayerBoxScoreView(
                    box: box, sport: sport,
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

// MARK: - Box score

struct PlayerBoxScoreView: View {
    let box: PlayerBoxScore
    let sport: SportType?
    let homeName: String
    let awayName: String
    private let rawHomeColor: Color
    private let rawAwayColor: Color

    @Environment(\.self) private var environment
    @State private var side: String = "away"

    init(box: PlayerBoxScore, sport: SportType?, homeName: String, awayName: String, homeColor: Color, awayColor: Color) {
        self.box = box
        self.sport = sport
        self.homeName = homeName
        self.awayName = awayName
        self.rawHomeColor = homeColor
        self.rawAwayColor = awayColor
    }

    private var selectedTeam: PlayerBoxScore.Team? {
        (side == "home" ? box.home : box.away) ?? box.away ?? box.home ?? box.teams.first
    }

    /// Hockey's goalies get their own both-teams table up top, so the per-team
    /// tables leave them out.
    private var showsGoalieStrip: Bool {
        sport == .hockey && (box.away?.group("goalies") != nil || box.home?.group("goalies") != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsGoalieStrip {
                GoalieStrip(box: box, homeName: homeName, awayName: awayName)
            }

            if box.away != nil, box.home != nil {
                Picker("Team", selection: $side) {
                    Text(awayName).tag("away")
                    Text(homeName).tag("home")
                }
                .pickerStyle(.segmented)
            }

            if let team = selectedTeam {
                ForEach(team.groups.filter { !(showsGoalieStrip && $0.id == "goalies") }) { group in
                    PlayerStatTable(group: group, sport: sport, tint: tint(for: team))
                }
            }
        }
    }

    private func tint(for team: PlayerBoxScore.Team) -> Color {
        (team.homeAway == "home" ? rawHomeColor : rawAwayColor).legible(in: environment)
    }
}

// MARK: - One stat table

/// A sticky name column beside a sideways-scrolling grid of stats. Rows are a fixed
/// (Dynamic Type-scaled) height so the two halves stay aligned.
struct PlayerStatTable: View {
    let group: PlayerBoxScore.Group
    let sport: SportType?
    let tint: Color

    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 26
    @ScaledMetric(relativeTo: .caption) private var nameWidth: CGFloat = 118
    @ScaledMetric(relativeTo: .caption) private var characterWidth: CGFloat = 7.5

    private var played: [PlayerBoxScore.Row] { group.rows.filter { !$0.isDNP } }
    private var didNotPlay: [PlayerBoxScore.Row] { group.rows.filter(\.isDNP) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)

            if !played.isEmpty {
                table
                    .accessibilityRepresentation {
                        VStack {
                            ForEach(played) { row in
                                Text(accessibilityLabel(for: row))
                            }
                            if let totals = group.totals {
                                Text(accessibilityLine(name: "Team", values: totals))
                            }
                        }
                    }
            }

            if !didNotPlay.isEmpty {
                dnpFootnote
            }
        }
    }

    private var table: some View {
        HStack(alignment: .top, spacing: 0) {
            // Sticky names.
            VStack(alignment: .leading, spacing: 0) {
                cell { Text("") }
                ForEach(Array(played.enumerated()), id: \.element.id) { index, row in
                    nameCell(row).background(stripe(index))
                }
                if group.totals != nil {
                    cell { Text("Team").fontWeight(.semibold) }
                }
            }
            .frame(width: nameWidth, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    statLine(group.labels, isHeader: true)
                    ForEach(Array(played.enumerated()), id: \.element.id) { index, row in
                        statLine(row.stats).background(stripe(index))
                    }
                    if let totals = group.totals {
                        statLine(totals, isTotal: true)
                    }
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
    }

    private func nameCell(_ row: PlayerBoxScore.Row) -> some View {
        cell {
            HStack(spacing: 4) {
                Text(row.name)
                    .foregroundStyle(.primary)
                    .truncationMode(.tail)
                if let position = row.position, !position.isEmpty {
                    Text(position)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let note = row.note {
                    Text(note)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
            // Baseball substitutes sit under the starter they replaced.
            .padding(.leading, isSubstitute(row) ? 10 : 0)
        }
    }

    private func isSubstitute(_ row: PlayerBoxScore.Row) -> Bool {
        sport == .mlb && group.id == "batting" && !row.isStarter
    }

    private func statLine(_ values: [String], isHeader: Bool = false, isTotal: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(group.labels.indices), id: \.self) { column in
                Text(column < values.count ? values[column] : "")
                    .frame(width: width(of: column), height: rowHeight)
            }
        }
        .font(isHeader ? .caption2.weight(.semibold) : .caption)
        .fontWeight(isTotal ? .semibold : nil)
        .foregroundStyle(isHeader ? .secondary : .primary)
        .monospacedDigit()
    }

    /// Wide enough for the column's longest entry ("10-19", "18:21", "C/ATT").
    private func width(of column: Int) -> CGFloat {
        var longest = group.labels[column].count
        for row in played where column < row.stats.count {
            longest = max(longest, row.stats[column].count)
        }
        if let totals = group.totals, column < totals.count {
            longest = max(longest, totals[column].count)
        }
        return CGFloat(max(longest, 2)) * characterWidth + 14
    }

    private func stripe(_ index: Int) -> some View {
        (index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : Color.clear)
    }

    private var dnpFootnote: some View {
        let names = didNotPlay.map { row in
            row.reason.map { "\(row.name) (\(Self.sentenceCase($0)))" } ?? row.name
        }
        return Text("Did not play: " + names.joined(separator: ", "))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Accessibility

    /// "A. Dybantsa, forward. 36 minutes, 11 points, field goals 3-13, …"
    private func accessibilityLabel(for row: PlayerBoxScore.Row) -> String {
        var name = row.fullName ?? row.name
        if let note = row.note { name += ", \(note)" }
        return accessibilityLine(name: name, values: row.stats)
    }

    private func accessibilityLine(name: String, values: [String]) -> String {
        let names = group.descriptions ?? group.labels
        let parts = zip(names, values).compactMap { label, value -> String? in
            value.isEmpty ? nil : "\(Self.spoken(label)) \(value)"
        }
        return "\(name). " + parts.joined(separator: ", ")
    }

    /// ESPN's hockey descriptions read "Total goals scored."; trim them to "goals scored".
    private static func spoken(_ description: String) -> String {
        var text = description.trimmingCharacters(in: CharacterSet(charactersIn: ". /"))
        if text.hasPrefix("Total ") { text = String(text.dropFirst(6)) }
        return text
    }

    private static func sentenceCase(_ text: String) -> String {
        let lower = text.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

// MARK: - Hockey goalies

/// Both teams' goalies in one small table: SA, SV, SV% and TOI.
private struct GoalieStrip: View {
    let box: PlayerBoxScore
    let homeName: String
    let awayName: String

    @ScaledMetric(relativeTo: .caption) private var statWidth: CGFloat = 46

    private struct Line: Identifiable {
        let id: String
        let team: String
        let row: PlayerBoxScore.Row
        let group: PlayerBoxScore.Group
    }

    private var lines: [Line] {
        var out: [Line] = []
        for (team, name) in [(box.away, awayName), (box.home, homeName)] {
            guard let group = team?.group("goalies") else { continue }
            for row in group.rows where !row.isDNP {
                out.append(Line(id: "\(team?.id ?? name)-\(row.id)", team: name, row: row, group: group))
            }
        }
        return out
    }

    private static let shown = ["SA", "SV", "SV%", "TOI"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOALIES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Self.shown, id: \.self) { label in
                    Text(label).frame(width: statWidth)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(lines) { line in
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text(line.team)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(line.row.name)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Self.shown, id: \.self) { label in
                        Text(value(label, in: line) ?? "–").frame(width: statWidth)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(line))
            }
        }
    }

    private func value(_ label: String, in line: Line) -> String? {
        guard let index = line.group.labels.firstIndex(of: label), index < line.row.stats.count else { return nil }
        return line.row.stats[index]
    }

    private func accessibilityLabel(_ line: Line) -> String {
        let shots = value("SA", in: line) ?? "–"
        let saves = value("SV", in: line) ?? "–"
        let pct = value("SV%", in: line) ?? "–"
        let toi = value("TOI", in: line) ?? "–"
        return "\(line.team) goalie \(line.row.fullName ?? line.row.name): \(saves) saves on \(shots) shots, save percentage \(pct), time on ice \(toi)"
    }
}

// MARK: - Hockey shots on goal (detail hero)

/// "SOG 32 – 37" under the hero score, from the team stats that ride with the
/// play-by-play. Hockey only; renders nothing until those stats arrive.
struct HeroShotsOnGoalLine: View {
    let sport: SportType?
    let stats: TeamStatComparison?
    let awayName: String
    let homeName: String

    var body: some View {
        if sport == .hockey, let row = stats?.rows.first(where: { $0.name == "shotsTotal" }) {
            Text("SOG \(row.away) – \(row.home)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("Shots on goal: \(awayName) \(row.away), \(homeName) \(row.home)")
        }
    }
}
