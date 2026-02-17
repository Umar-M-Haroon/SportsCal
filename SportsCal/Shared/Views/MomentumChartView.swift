//
//  MomentumChartView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import Charts
import SportsCalModel

/// Swift Charts line chart showing cumulative score progression period-by-period.
/// Two lines colored with team hex colors, shaded area between them showing lead.
struct MomentumChartView: View {
    let game: Game
    let homeTeamName: String
    let awayTeamName: String

    private var homeColor: Color {
        if let hex = game.homeTeamColor {
            return Color(hex: hex)
        }
        return .blue
    }

    private var awayColor: Color {
        if let hex = game.awayTeamColor {
            return Color(hex: hex)
        }
        return .red
    }

    private struct ScorePoint: Identifiable {
        let id = UUID()
        let period: String
        let periodIndex: Int
        let cumulativeScore: Double
        let team: String
    }

    private var dataPoints: [ScorePoint] {
        guard let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
              !homeLs.isEmpty, !awayLs.isEmpty else { return [] }

        let periodCount = max(homeLs.count, awayLs.count)
        let labels = game.periodLabels(count: periodCount)
        var points: [ScorePoint] = []

        // Start at 0
        points.append(ScorePoint(period: "Start", periodIndex: 0, cumulativeScore: 0, team: homeTeamName))
        points.append(ScorePoint(period: "Start", periodIndex: 0, cumulativeScore: 0, team: awayTeamName))

        var homeCum: Double = 0
        var awayCum: Double = 0

        for i in 0..<periodCount {
            let label = i < labels.count ? labels[i] : "\(i + 1)"
            if i < homeLs.count { homeCum += homeLs[i] }
            if i < awayLs.count { awayCum += awayLs[i] }
            points.append(ScorePoint(period: label, periodIndex: i + 1, cumulativeScore: homeCum, team: homeTeamName))
            points.append(ScorePoint(period: label, periodIndex: i + 1, cumulativeScore: awayCum, team: awayTeamName))
        }

        return points
    }

    var body: some View {
        let points = dataPoints
        if points.count >= 4 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Score Momentum")
                    .font(.headline)

                Chart(points) { point in
                    LineMark(
                        x: .value("Period", point.periodIndex),
                        y: .value("Score", point.cumulativeScore)
                    )
                    .foregroundStyle(by: .value("Team", point.team))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    PointMark(
                        x: .value("Period", point.periodIndex),
                        y: .value("Score", point.cumulativeScore)
                    )
                    .foregroundStyle(by: .value("Team", point.team))
                    .symbolSize(20)
                }
                .chartForegroundStyleScale([
                    homeTeamName: homeColor,
                    awayTeamName: awayColor
                ])
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        if let idx = value.as(Int.self) {
                            let allLabels = ["Start"] + game.periodLabels(count: max((game.homeLinescores?.count ?? 0), (game.awayLinescores?.count ?? 0)))
                            if idx < allLabels.count {
                                AxisValueLabel { Text(allLabels[idx]).font(.caption2) }
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 200)

                // Score annotations
                if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores {
                    let homeTotal = homeLs.reduce(0, +)
                    let awayTotal = awayLs.reduce(0, +)
                    let diff = abs(homeTotal - awayTotal)
                    if diff > 0 {
                        let leader = homeTotal > awayTotal ? homeTeamName : awayTeamName
                        Text("\(leader) led by \(formatScore(diff))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func formatScore(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }
}

// MARK: - Color from Hex

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        case 8:
            r = Double((int >> 24) & 0xFF) / 255
            g = Double((int >> 16) & 0xFF) / 255
            b = Double((int >> 8) & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
