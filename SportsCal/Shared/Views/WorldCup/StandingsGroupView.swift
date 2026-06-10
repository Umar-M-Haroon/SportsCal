//
//  StandingsGroupView.swift
//  SportsCal
//
//  Renders one standings group/division table from an ESPN `Child`. Shared by the
//  World Cup hub (one per group, 12 at the 2026 tournament) and reusable elsewhere.
//

import SwiftUI
import SportsCalModel

struct StandingsGroupView: View {
    let name: String?
    let entries: [Entry]
    var isSoccer: Bool = true
    var accent: Color = .appPositive
    /// Team display/short names to bold (e.g. the two teams in the game being viewed).
    var highlight: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name {
                Text(name.uppercased())
                    .font(.appFootnote)
                    .foregroundStyle(Color.appInkFaint)
            }

            HStack(spacing: 0) {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("W").frame(width: 32, alignment: .center)
                Text("L").frame(width: 32, alignment: .center)
                if isSoccer {
                    Text("D").frame(width: 32, alignment: .center)
                    Text("Pts").frame(width: 36, alignment: .center)
                }
            }
            .font(.appFootnote)
            .foregroundStyle(Color.appInkFaint)

            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let isHL = isHighlighted(entry)
                HStack(spacing: 0) {
                    Text("\(index + 1)").frame(width: 24, alignment: .leading)
                    Text(entry.team?.shortDisplayName ?? entry.team?.displayName ?? "-")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(statValue(entry, "wins")).frame(width: 32, alignment: .center)
                    Text(statValue(entry, "losses")).frame(width: 32, alignment: .center)
                    if isSoccer {
                        Text(statValue(entry, "ties")).frame(width: 32, alignment: .center)
                        Text(statValue(entry, "points")).frame(width: 36, alignment: .center)
                    }
                }
                .font(.appCaption)
                .fontWeight(isHL ? .bold : .regular)
                .foregroundStyle(isHL ? accent : Color.appInkSoft)
            }
        }
        .padding(.vertical, .appSpace1)
    }

    private func statValue(_ entry: Entry, _ name: String) -> String {
        guard let stat = entry.stats?.first(where: { $0.name == name }) else { return "-" }
        return stat.displayValue ?? (stat.value.map { "\(Int($0))" } ?? "-")
    }

    private func isHighlighted(_ entry: Entry) -> Bool {
        guard !highlight.isEmpty else { return false }
        if let n = entry.team?.displayName, highlight.contains(n) { return true }
        if let n = entry.team?.shortDisplayName, highlight.contains(n) { return true }
        return false
    }
}
