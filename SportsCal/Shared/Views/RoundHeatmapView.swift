//
//  RoundHeatmapView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import SportsCalModel

/// 2D grid (players x rounds) with green-to-red color encoding based on score relative to field range.
struct RoundHeatmapView: View {
    let entries: [LeaderboardEntry]
    var maxPlayers: Int = 10

    private var topEntries: [LeaderboardEntry] {
        Array(entries.prefix(maxPlayers))
    }

    private var roundCount: Int {
        topEntries.map(\.rounds.count).max() ?? 0
    }

    /// Parse all round scores across entries to find field min/max
    private var fieldRange: (min: Double, max: Double) {
        var allScores: [Double] = []
        for entry in topEntries {
            for round in entry.rounds {
                if let val = Double(round) {
                    allScores.append(val)
                }
            }
        }
        guard let lo = allScores.min(), let hi = allScores.max(), lo < hi else {
            return (65, 75) // sensible defaults for golf
        }
        return (lo, hi)
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
                            if roundIdx < entry.rounds.count, let score = Double(entry.rounds[roundIdx]) {
                                let range = fieldRange
                                let normalized = (score - range.min) / max(range.max - range.min, 1)
                                Text(entry.rounds[roundIdx])
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(heatColor(normalized: normalized))
                                    )
                                    .foregroundColor(.white)
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

                // Legend
                HStack(spacing: 4) {
                    Text("Low")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    LinearGradient(
                        colors: [.green, .yellow, .orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 60, height: 6)
                    .clipShape(Capsule())
                    Text("High")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    /// Maps a 0...1 normalized value to a green → yellow → red color
    private func heatColor(normalized: Double) -> Color {
        let clamped = min(max(normalized, 0), 1)
        if clamped < 0.5 {
            // Green to Yellow
            let t = clamped * 2
            return Color(red: t, green: 0.7, blue: 0.1)
        } else {
            // Yellow to Red
            let t = (clamped - 0.5) * 2
            return Color(red: 0.85, green: 0.7 * (1 - t), blue: 0.1 * (1 - t))
        }
    }
}
