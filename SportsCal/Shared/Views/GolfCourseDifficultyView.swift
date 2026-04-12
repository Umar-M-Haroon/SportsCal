//
//  GolfCourseDifficultyView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/12/26.
//

import SwiftUI
import SportsCalModel

/// Shows each hole's average score vs par, birdie/bogey counts, ranked by difficulty.
struct GolfCourseDifficultyView: View {
    let entries: [LeaderboardEntry]
    let holePars: [Int]?

    private struct HoleStat: Identifiable {
        let id: Int // hole number
        let par: Int
        let avgScore: Double
        let birdies: Int
        let bogeys: Int
        let eagles: Int
        let doubles: Int
        let totalPlayed: Int

        var avgVsPar: Double { avgScore - Double(par) }
    }

    private var holeStats: [HoleStat] {
        guard let holePars, holePars.count >= 18 else { return [] }

        var stats: [Int: (scores: [Int], par: Int)] = [:]
        for i in 1...18 {
            stats[i] = (scores: [], par: holePars[i - 1])
        }

        // Aggregate all hole scores across all players and all rounds
        for entry in entries {
            guard let details = entry.roundDetails else { continue }
            for round in details {
                guard let holes = round.holeScores else { continue }
                for hole in holes {
                    guard let score = hole.score, hole.hole >= 1, hole.hole <= 18 else { continue }
                    stats[hole.hole]?.scores.append(score)
                }
            }
        }

        return (1...18).compactMap { holeNum -> HoleStat? in
            guard let data = stats[holeNum], !data.scores.isEmpty else { return nil }
            let avg = Double(data.scores.reduce(0, +)) / Double(data.scores.count)
            var birdies = 0, bogeys = 0, eagles = 0, doubles = 0
            for s in data.scores {
                let diff = s - data.par
                switch diff {
                case ...(-2): eagles += 1
                case -1: birdies += 1
                case 1: bogeys += 1
                case 2...: doubles += 1
                default: break
                }
            }
            return HoleStat(
                id: holeNum, par: data.par, avgScore: avg,
                birdies: birdies, bogeys: bogeys, eagles: eagles,
                doubles: doubles, totalPlayed: data.scores.count
            )
        }
    }

    private var sortedByDifficulty: [HoleStat] {
        holeStats.sorted { $0.avgVsPar > $1.avgVsPar }
    }

    var body: some View {
        if !holeStats.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Course Overview")
                    .font(.headline)

                // Difficulty bar chart
                VStack(spacing: 3) {
                    // Header
                    HStack(spacing: 0) {
                        Text("Hole")
                            .frame(width: 34, alignment: .leading)
                        Text("Par")
                            .frame(width: 26)
                        Text("Avg")
                            .frame(width: 36)
                        Text("")
                            .frame(maxWidth: .infinity)
                        Text("🦅")
                            .frame(width: 28)
                        Text("🐦")
                            .frame(width: 28)
                        Text("💀")
                            .frame(width: 28)
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                    ForEach(holeStats) { hole in
                        HStack(spacing: 0) {
                            Text("#\(hole.id)")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 34, alignment: .leading)
                            Text("\(hole.par)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 26)
                            Text(String(format: "%.2f", hole.avgScore))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(hole.avgVsPar < -0.05 ? .green : (hole.avgVsPar > 0.05 ? .red : .secondary))
                                .frame(width: 36)

                            // Difficulty bar
                            GeometryReader { geo in
                                let maxDiff = max(abs(holeStats.map(\.avgVsPar).max() ?? 0.5), abs(holeStats.map(\.avgVsPar).min() ?? 0.5), 0.3)
                                let center = geo.size.width / 2
                                let scale = center / maxDiff
                                let barWidth = abs(hole.avgVsPar) * scale

                                ZStack(alignment: .leading) {
                                    // Center line
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 1)
                                        .position(x: center, y: geo.size.height / 2)

                                    // Bar
                                    if hole.avgVsPar > 0.01 {
                                        // Harder than par (red, right of center)
                                        Rectangle()
                                            .fill(Color.red.opacity(0.6))
                                            .frame(width: barWidth, height: 10)
                                            .cornerRadius(2)
                                            .position(x: center + barWidth / 2, y: geo.size.height / 2)
                                    } else if hole.avgVsPar < -0.01 {
                                        // Easier than par (green, left of center)
                                        Rectangle()
                                            .fill(Color.green.opacity(0.6))
                                            .frame(width: barWidth, height: 10)
                                            .cornerRadius(2)
                                            .position(x: center - barWidth / 2, y: geo.size.height / 2)
                                    }
                                }
                            }
                            .frame(height: 14)

                            // Counts
                            Text(hole.eagles > 0 ? "\(hole.eagles)" : "-")
                                .font(.system(size: 9))
                                .foregroundColor(hole.eagles > 0 ? Color(red: 0, green: 0.5, blue: 0.7) : .secondary.opacity(0.3))
                                .frame(width: 28)
                            Text("\(hole.birdies)")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                                .frame(width: 28)
                            Text("\(hole.bogeys + hole.doubles)")
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                                .frame(width: 28)
                        }
                    }
                }

                // Hardest/easiest callouts
                if let hardest = sortedByDifficulty.first, let easiest = sortedByDifficulty.last {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hardest")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("Hole \(hardest.id) (Par \(hardest.par))")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                            Text(String(format: "Avg %.2f (+%.2f)", hardest.avgScore, hardest.avgVsPar))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Easiest")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("Hole \(easiest.id) (Par \(easiest.par))")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                            Text(String(format: "Avg %.2f (%.2f)", easiest.avgScore, easiest.avgVsPar))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }
}
