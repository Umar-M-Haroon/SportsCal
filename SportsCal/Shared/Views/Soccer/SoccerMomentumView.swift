//
//  SoccerMomentumView.swift
//  SportsCal
//
//  FotMob-style attack momentum: one bar per minute, rising in the home colour
//  when the home side is on top and falling in the away colour when the away
//  side is. Halves sit side by side with a small gap at half-time, so first-half
//  stoppage keeps its own minutes; goals are marked on the side that scored.
//  The series is built server-side from where play happens (see SoccerMomentum).
//

import SwiftUI
import Charts
import SportsCalModel

struct SoccerMomentumView: View {
    let momentum: [SoccerMomentumPoint]
    let shots: [SoccerShot]
    let homeName: String
    let awayName: String
    let homeColor: Color
    let awayColor: Color

    /// Empty minutes left between periods on the x axis.
    private static let periodGap = 1.5

    private struct Bar: Identifiable {
        let id: Int
        let x: Double
        let value: Double
    }

    private struct GoalMark: Identifiable {
        let id: String
        let x: Double
        let isHome: Bool
    }

    private struct Boundary: Identifiable {
        let id: Int
        let x: Double
        let label: String
    }

    // MARK: Layout

    /// Where each period starts on the x axis: its kickoff minute, pushed right by
    /// the stoppage time and gaps of the periods before it.
    private var periodOffsets: [Int: Double] {
        let periods = Set(momentum.map(\.period)).sorted()
        var offsets: [Int: Double] = [:]
        var shift = 0.0
        for period in periods {
            offsets[period] = shift
            let minutes = momentum.filter { $0.period == period }.map(\.minute)
            let regulationEnd = Double(Self.regulationEnd(of: period))
            let lastMinute = Double(minutes.max() ?? 0) + 1
            shift += max(0, lastMinute - regulationEnd) + Self.periodGap
        }
        return offsets
    }

    private static func regulationEnd(of period: Int) -> Int {
        switch period {
        case 1: return 45
        case 2: return 90
        case 3: return 105
        default: return 120
        }
    }

    private var bars: [Bar] {
        let offsets = periodOffsets
        return momentum.enumerated().map { index, point in
            Bar(id: index, x: Double(point.minute) + (offsets[point.period] ?? 0), value: point.value)
        }
    }

    private var goals: [GoalMark] {
        let offsets = periodOffsets
        return shots.filter { $0.outcome == .goal }.map { shot in
            let period = shot.period ?? (shot.minute < 46 ? 1 : 2)
            return GoalMark(id: shot.id, x: shot.minute + (offsets[period] ?? 0), isHome: shot.side == .home)
        }
    }

    /// Axis labels at kickoff, half-time and the end of each period in the series.
    private var boundaries: [Boundary] {
        let offsets = periodOffsets
        var marks = [Boundary(id: 0, x: 0, label: "0'")]
        for period in offsets.keys.sorted() {
            let lastMinute = Double(momentum.filter { $0.period == period }.map(\.minute).max() ?? 0) + 1
            let end = max(lastMinute, Double(Self.regulationEnd(of: period))) + (offsets[period] ?? 0)
            let label: String
            // "90'" rather than "FT": the axis reaches it while the match is still live.
            label = period == 1 ? "HT" : "\(Self.regulationEnd(of: period))'"
            marks.append(Boundary(id: period, x: end, label: label))
        }
        return marks
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            teamLabel(homeName, color: homeColor)
            chart
            teamLabel(awayName, color: awayColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Momentum")
        .accessibilityValue(accessibilitySummary)
    }

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Minute", bar.x),
                    y: .value("Momentum", bar.value),
                    width: .fixed(2.5)
                )
                .foregroundStyle(bar.value >= 0 ? homeColor : awayColor)
            }
            RuleMark(y: .value("Even", 0))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
            ForEach(goals) { goal in
                PointMark(x: .value("Minute", goal.x), y: .value("Momentum", goal.isHome ? 1.18 : -1.18))
                    .symbol {
                        Image(systemName: "soccerball")
                            .font(.system(size: 10))
                            .foregroundStyle(goal.isHome ? homeColor : awayColor)
                    }
            }
        }
        .chartYScale(domain: -1.3...1.3)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...(boundaries.map(\.x).max() ?? 90))
        .chartXAxis {
            let marks = boundaries
            AxisMarks(values: marks.map(\.x)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                // Labels centre on their mark, so the end ones would overhang the
                // chart's edges and clip; pin those inward.
                let anchor: UnitPoint = value.index == 0 ? .topLeading
                    : value.index == marks.count - 1 ? .topTrailing : .top
                AxisValueLabel(anchor: anchor) {
                    if let x = value.as(Double.self), let mark = marks.first(where: { $0.x == x }) {
                        Text(mark.label)
                    }
                }
            }
        }
        .frame(height: 120)
    }

    private func teamLabel(_ name: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// "Home on top for 52 minutes, away for 38", for VoiceOver.
    private var accessibilitySummary: String {
        let homeMinutes = momentum.filter { $0.value > 0.05 }.count
        let awayMinutes = momentum.filter { $0.value < -0.05 }.count
        return "\(homeName) on top for \(homeMinutes) minutes, \(awayName) for \(awayMinutes)"
    }
}
