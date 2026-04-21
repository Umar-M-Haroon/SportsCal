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
/// Two lines colored with team hex colors. When play-by-play is available, plots a point
/// per scoring play using a continuous X axis (period + fraction-elapsed); otherwise
/// falls back to one point per period boundary derived from linescores.
struct MomentumChartView: View {
    let game: Game
    let homeTeamName: String
    let awayTeamName: String
    /// Full play-by-play when available. When empty, chart draws from linescores only.
    var plays: [Play] = []

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
        let x: Double         // continuous: integer part = period index (0-based), fractional = elapsed
        let cumulativeScore: Double
        let team: String
    }

    /// Total number of periods covered by the chart (used for axis labels and rule marks).
    private var periodCount: Int {
        if !plays.isEmpty {
            return max(plays.compactMap { $0.period?.number }.max() ?? 0, 1)
        }
        return max(game.homeLinescores?.count ?? 0, game.awayLinescores?.count ?? 0)
    }

    /// Expected length of a regulation period (in seconds) for clock-based X positioning.
    /// Overtime/extra periods fall back to linear index since lengths vary by league/season.
    private func periodLengthSeconds(period: Int) -> Double? {
        guard let sport = game.sportType else { return nil }
        switch sport {
        case .basketball: return period <= 4 ? 12 * 60 : 5 * 60   // OT is 5 min
        case .nfl:        return period <= 4 ? 15 * 60 : 10 * 60  // OT is 10 min
        case .hockey:     return period <= 3 ? 20 * 60 : 5 * 60   // OT is 5 min
        default:          return nil                               // MLB has no clock
        }
    }

    /// Parses ESPN clock strings like "11:42" or "3:08" into seconds remaining.
    private func parseClockSeconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let min = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
        return min * 60 + sec
    }

    /// Score points sourced from the play-by-play. One point per scoring play per team plus
    /// a start (0, 0) origin, using continuous X = (period-1) + elapsed-fraction.
    private var playBasedPoints: [ScorePoint] {
        guard !plays.isEmpty else { return [] }

        // Pre-compute play ordering within each period for clockless sports (MLB).
        var playsByPeriod: [Int: [Play]] = [:]
        for play in plays {
            let p = play.period?.number ?? 1
            playsByPeriod[p, default: []].append(play)
        }

        var points: [ScorePoint] = [
            ScorePoint(x: 0, cumulativeScore: 0, team: homeTeamName),
            ScorePoint(x: 0, cumulativeScore: 0, team: awayTeamName)
        ]

        for (period, periodPlays) in playsByPeriod {
            let total = max(periodPlays.count, 1)
            for (index, play) in periodPlays.enumerated() {
                guard play.scoringPlay == true,
                      let home = play.homeScore, let away = play.awayScore else { continue }

                // Prefer clock-based X; fall back to play-index when the sport has no clock.
                let fraction: Double = {
                    if let text = play.clock?.displayValue,
                       let remaining = parseClockSeconds(text),
                       let length = periodLengthSeconds(period: period), length > 0 {
                        let elapsed = max(0, min(length, length - remaining))
                        return elapsed / length
                    }
                    return Double(index) / Double(total)
                }()

                let x = Double(period - 1) + fraction
                points.append(ScorePoint(x: x, cumulativeScore: Double(home), team: homeTeamName))
                points.append(ScorePoint(x: x, cumulativeScore: Double(away), team: awayTeamName))
            }
        }

        // Ensure the line extends to the current final score.
        if let homeTotal = Int(game.intHomeScore ?? ""),
           let awayTotal = Int(game.intAwayScore ?? "") {
            let endX = Double(periodCount)
            points.append(ScorePoint(x: endX, cumulativeScore: Double(homeTotal), team: homeTeamName))
            points.append(ScorePoint(x: endX, cumulativeScore: Double(awayTotal), team: awayTeamName))
        }

        return points.sorted { $0.x < $1.x }
    }

    /// Fallback path: one point per period boundary, derived from linescores.
    private var linescoreBasedPoints: [ScorePoint] {
        guard let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
              !homeLs.isEmpty, !awayLs.isEmpty else { return [] }

        var points: [ScorePoint] = [
            ScorePoint(x: 0, cumulativeScore: 0, team: homeTeamName),
            ScorePoint(x: 0, cumulativeScore: 0, team: awayTeamName)
        ]

        var homeCum: Double = 0
        var awayCum: Double = 0
        let count = max(homeLs.count, awayLs.count)
        for i in 0..<count {
            if i < homeLs.count { homeCum += homeLs[i] }
            if i < awayLs.count { awayCum += awayLs[i] }
            let x = Double(i + 1)
            points.append(ScorePoint(x: x, cumulativeScore: homeCum, team: homeTeamName))
            points.append(ScorePoint(x: x, cumulativeScore: awayCum, team: awayTeamName))
        }
        return points
    }

    private var dataPoints: [ScorePoint] {
        let pbp = playBasedPoints
        return pbp.isEmpty ? linescoreBasedPoints : pbp
    }

    var body: some View {
        let points = dataPoints
        let usingPBP = !playBasedPoints.isEmpty
        if points.count >= 4 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Score Momentum")
                        .font(.headline)
                    Spacer()
                    if usingPBP {
                        Text("By Play")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }

                let periodLabels = game.periodLabels(count: periodCount)

                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Period", point.x),
                            y: .value("Score", point.cumulativeScore)
                        )
                        .foregroundStyle(by: .value("Team", point.team))
                        .interpolationMethod(usingPBP ? .stepEnd : .catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        // Only draw point markers when we have few enough points to be readable.
                        if !usingPBP || points.count <= 40 {
                            PointMark(
                                x: .value("Period", point.x),
                                y: .value("Score", point.cumulativeScore)
                            )
                            .foregroundStyle(by: .value("Team", point.team))
                            .symbolSize(usingPBP ? 12 : 20)
                        }
                    }

                    // Vertical gridlines at each quarter/period boundary.
                    ForEach(0...periodCount, id: \.self) { boundary in
                        RuleMark(x: .value("Boundary", Double(boundary)))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartForegroundStyleScale([
                    homeTeamName: homeColor,
                    awayTeamName: awayColor
                ])
                .chartXAxis {
                    // Tick centered in each period (at period-1 + 0.5) with the period label.
                    AxisMarks(values: (0..<periodCount).map { Double($0) + 0.5 }) { value in
                        if let x = value.as(Double.self) {
                            let periodIndex = Int(x)
                            if periodIndex < periodLabels.count {
                                AxisValueLabel(centered: true) {
                                    Text(periodLabels[periodIndex]).font(.caption2)
                                }
                            }
                        }
                    }
                }
                .chartXScale(domain: 0...Double(periodCount))
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
