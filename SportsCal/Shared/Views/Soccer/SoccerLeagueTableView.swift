//
//  SoccerLeagueTableView.swift
//  SportsCal
//
//  A soccer table, FotMob-style: a coloured band for each qualification or
//  relegation zone, rank movement, played / goal difference / points, and each
//  side's last five results. A legend explains the zones underneath.
//

import SwiftUI
import SportsCalModel

struct SoccerLeagueTableView: View {
    let groups: [SoccerTableGroup]
    let zones: [SoccerTableZone]

    var body: some View {
        VStack(alignment: .leading, spacing: .appSpace5) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    if let name = group.name {
                        Text(name.uppercased()).appEyebrow().foregroundStyle(Color.app(.soccer))
                    }
                    headerRow
                    ForEach(group.rows) { row in
                        tableRow(row)
                        if row.id != group.rows.last?.id { Divider().opacity(0.5) }
                    }
                }
                .appCard()
            }
            if !zones.isEmpty {
                legend
            }
        }
    }

    // MARK: Rows

    private enum Column {
        static let rank: CGFloat = 26
        static let stat: CGFloat = 26
        static let goalDifference: CGFloat = 32
        static let form: CGFloat = 5 * 8 + 4 * 2
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: Column.rank, alignment: .leading)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            Text("P").frame(width: Column.stat)
            Text("GD").frame(width: Column.goalDifference)
            Text("Pts").frame(width: Column.stat)
            Text("Form").frame(width: Column.form)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.leading, 7)
    }

    private func tableRow(_ row: SoccerTableRow) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                Text("\(row.rank)")
                    .font(.subheadline)
                    .monospacedDigit()
                rankChangeMark(row.rankChange)
            }
            .frame(width: Column.rank, alignment: .leading)

            HStack(spacing: 6) {
                WCBadge(url: row.badge, size: 18)
                Text(row.teamName)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(row.played)")
                .frame(width: Column.stat)
                .foregroundStyle(.secondary)
            Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
                .frame(width: Column.goalDifference)
                .foregroundStyle(.secondary)
            Text("\(row.points)")
                .fontWeight(.bold)
                .frame(width: Column.stat)
            formDots(row.form)
                .frame(width: Column.form)
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.vertical, 3)
        .padding(.leading, 7)
        .overlay(alignment: .leading) {
            // The zone band runs down the left edge.
            if let zone = row.zone {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: zone.colorHex) ?? .clear)
                    .frame(width: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(row))
    }

    @ViewBuilder
    private func rankChangeMark(_ change: Int) -> some View {
        if change != 0 {
            Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 6))
                .foregroundStyle(change > 0 ? Color.green : Color.red)
        }
    }

    private func formDots(_ form: [SoccerResult]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(form.enumerated()), id: \.offset) { _, result in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.color(for: result))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    static func color(for result: SoccerResult) -> Color {
        switch result {
        case .win: return .green
        case .draw: return .gray
        case .loss: return .red
        }
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(zones, id: \.self) { zone in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: zone.colorHex) ?? .clear)
                        .frame(width: 10, height: 10)
                    Text(zone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                ForEach([SoccerResult.win, .draw, .loss], id: \.self) { result in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Self.color(for: result)).frame(width: 8, height: 8)
                        Text(result == .win ? "Won" : result == .draw ? "Drew" : "Lost")
                    }
                }
                Text("· last five, latest on the right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, .appSpace2)
    }

    private func accessibilityLabel(_ row: SoccerTableRow) -> String {
        var parts = ["\(row.rank). \(row.teamName)", "\(row.points) points", "played \(row.played)",
                     "goal difference \(row.goalDifference)"]
        if let zone = row.zone { parts.append(zone.description) }
        if !row.form.isEmpty {
            parts.append("form " + row.form.map(\.rawValue).joined(separator: " "))
        }
        return parts.joined(separator: ", ")
    }
}
