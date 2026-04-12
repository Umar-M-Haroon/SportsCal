//
//  RoundHeatmapView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import SportsCalModel

/// 2D grid (players x rounds) with par-relative color encoding.
/// Green = under par (good), gray = even, red = over par (bad).
/// No color is applied when course par is unknown.
struct RoundHeatmapView: View {
    let entries: [LeaderboardEntry]
    var maxPlayers: Int = 10
    var coursePar: Int? = nil

    private var topEntries: [LeaderboardEntry] {
        Array(entries.prefix(maxPlayers))
    }

    private var roundCount: Int {
        topEntries.map(\.rounds.count).max() ?? 0
    }

    var body: some View {
        if roundCount > 0, !topEntries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Round Heatmap")
                    .font(.headline)

                // Header row
                HStack(spacing: 0) {
                    Text("Player")
                        .frame(width: 100, alignment: .leading)
                    ForEach(0..<roundCount, id: \.self) { i in
                        Text("R\(i + 1)")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                // Player rows
                ForEach(Array(topEntries.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Text("\(entry.position)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(entry.name)
                                .font(.caption)
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .lineLimit(1)
                        }
                        .frame(width: 100, alignment: .leading)

                        ForEach(0..<roundCount, id: \.self) { roundIdx in
                            if roundIdx < entry.rounds.count, let score = Int(entry.rounds[roundIdx]) {
                                let bg = cellColor(score: score)
                                let fg: Color = bg == nil ? .primary : .white
                                VStack(spacing: 1) {
                                    Text(entry.rounds[roundIdx])
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                    if let par = coursePar {
                                        let diff = score - par
                                        Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                                            .font(.system(size: 8))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(bg ?? Color.gray.opacity(0.15))
                                )
                                .foregroundColor(fg)
                            } else {
                                Text("-")
                                    .font(.caption2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Legend (only when par is known)
                if coursePar != nil {
                    HStack(spacing: 4) {
                        Text("Under par")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        LinearGradient(
                            colors: [.green, .gray, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 60, height: 6)
                        .clipShape(Capsule())
                        Text("Over par")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    /// Par-relative color: green for under, red for over, gray for even.
    /// Returns nil when coursePar is unknown (no color applied).
    private func cellColor(score: Int) -> Color? {
        guard let par = coursePar else { return nil }
        let diff = score - par
        switch diff {
        case ...(-3): return Color(red: 0.1, green: 0.65, blue: 0.2)   // deep green
        case -2:      return Color(red: 0.3, green: 0.7, blue: 0.35)   // green
        case -1:      return Color(red: 0.45, green: 0.72, blue: 0.45) // light green
        case 0:       return Color.gray.opacity(0.5)                     // even par
        case 1:       return Color(red: 0.85, green: 0.55, blue: 0.2)  // orange
        case 2:       return Color(red: 0.85, green: 0.35, blue: 0.15) // dark orange
        default:      return Color(red: 0.8, green: 0.15, blue: 0.15)  // red (3+)
        }
    }
}
