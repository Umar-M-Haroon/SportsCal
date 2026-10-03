//
//  F1LapChartView.swift
//  SportsCal
//

import SwiftUI
import Charts
import SportsCalModel

/// Lap-by-lap position chart for a finished Race or Sprint. One line per driver in team
/// colour (second driver of each team dashed), safety car / VSC laps shaded, red flags
/// marked. Tap a driver chip to follow one line.
struct F1LapChartView: View {
    let detail: F1SessionDetail

    @State private var focused: Int?

    private static let rowHeight: CGFloat = 13

    private var lines: [F1LapPositions] { detail.lapPositions }
    private var gridSize: Int { max(lines.flatMap(\.positions).max() ?? 20, 2) }
    private var lastLap: Int { max(detail.totalLaps, (lines.map(\.positions.count).max() ?? 1) - 1) }

    /// Second car of each team (by finishing order) draws dashed.
    private var dashedDrivers: Set<Int> {
        var seen = Set<String>()
        var dashed = Set<Int>()
        for line in lines {
            let team = line.teamColour ?? line.acronym
            if seen.contains(team) { dashed.insert(line.driverNumber) } else { seen.insert(team) }
        }
        return dashed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
            legend
            driverChips
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Lap Chart")
                .font(.headline)
            Spacer()
            if let weather = detail.weather {
                Label {
                    Text("Air \(temperature(weather.airTempMax)) · Track \(temperature(weather.trackTempMax))")
                } icon: {
                    Image(systemName: weather.rainfall ? "cloud.rain" : "sun.max")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(weather.rainfall ? "Rain" : "Dry"), air up to \(temperature(weather.airTempMax)), track up to \(temperature(weather.trackTempMax))")
            }
        }
    }

    private func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    // MARK: - Chart

    private var chart: some View {
        let dashed = dashedDrivers
        let finishers = lines.filter { $0.positions.count == lastLap + 1 }.map(\.driverNumber)
        return Chart {
            ForEach(Array(detail.neutralizations.enumerated()), id: \.offset) { _, period in
                RectangleMark(
                    xStart: .value("Lap", period.startLap),
                    xEnd: .value("Lap", period.endLap)
                )
                .foregroundStyle(Color.yellow.opacity(period.kind == .safetyCar ? 0.22 : 0.12))
            }
            ForEach(detail.redFlagLaps, id: \.self) { lap in
                RuleMark(x: .value("Lap", lap))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            }
            ForEach(lines, id: \.driverNumber) { line in
                let isDimmed = focused != nil && focused != line.driverNumber
                let color = Color(hex: line.teamColour) ?? .gray
                ForEach(Array(line.positions.enumerated()), id: \.offset) { lap, position in
                    LineMark(
                        x: .value("Lap", lap),
                        y: .value("Position", -position),
                        series: .value("Driver", line.acronym)
                    )
                    .foregroundStyle(color.opacity(isDimmed ? 0.12 : 1))
                    .lineStyle(StrokeStyle(
                        lineWidth: focused == line.driverNumber ? 3 : 1.5,
                        dash: dashed.contains(line.driverNumber) ? [4, 2] : []
                    ))
                    .interpolationMethod(.monotone)
                }
                if let last = line.positions.last, finishers.contains(line.driverNumber) {
                    PointMark(x: .value("Lap", line.positions.count - 1), y: .value("Position", -last))
                        .symbolSize(0)
                        .annotation(position: .trailing, spacing: 3) {
                            Text(line.acronym)
                                .font(.system(size: 8, weight: focused == line.driverNumber ? .bold : .medium))
                                .foregroundStyle(isDimmed ? Color.secondary.opacity(0.4) : Color.primary)
                        }
                }
            }
        }
        // Positions are plotted negated so P1 sits on top over an explicit, padded
        // domain (an auto-sized reversed scale clips the bottom line).
        .chartYScale(domain: -(Double(gridSize) + 0.5)...(-0.5))
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(stride(from: 1, through: gridSize, by: 4)).map { -$0 }) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel { if let p = value.as(Int.self) { Text("P\(-p)") } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.1))
                AxisValueLabel { if let lap = value.as(Int.self) { Text(lap == 0 ? "Grid" : "\(lap)") } }
            }
        }
        .chartXScale(domain: 0...lastLap)
        .padding(.trailing, 22) // room for end-of-line codes
        .frame(height: CGFloat(gridSize) * Self.rowHeight + 30)
        .animation(.smooth, value: focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["Lap chart over \(lastLap) laps"]
        for period in detail.neutralizations {
            parts.append("\(period.kind == .safetyCar ? "safety car" : "virtual safety car") laps \(period.startLap) to \(period.endLap)")
        }
        if !detail.redFlagLaps.isEmpty {
            parts.append("red flag on lap \(detail.redFlagLaps.map(String.init).joined(separator: ", "))")
        }
        let movers = lines.compactMap { line -> (String, Int)? in
            guard let start = line.positions.first, let end = line.positions.last, line.positions.count == lastLap + 1 else { return nil }
            return (line.name, start - end)
        }.sorted { $0.1 > $1.1 }
        if let best = movers.first, best.1 > 0 {
            parts.append("biggest gain \(best.0), \(best.1) places")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Legend & chips

    @ViewBuilder
    private var legend: some View {
        let hasSC = detail.neutralizations.contains { $0.kind == .safetyCar }
        let hasVSC = detail.neutralizations.contains { $0.kind == .virtualSafetyCar }
        if hasSC || hasVSC || !detail.redFlagLaps.isEmpty {
            HStack(spacing: 12) {
                if hasSC { swatch(Color.yellow.opacity(0.22), "Safety car") }
                if hasVSC { swatch(Color.yellow.opacity(0.12), "Virtual SC") }
                if !detail.redFlagLaps.isEmpty { swatch(.red, "Red flag") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(label)
        }
    }

    private var driverChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(lines, id: \.driverNumber) { line in
                    let isOn = focused == line.driverNumber
                    Button {
                        focused = isOn ? nil : line.driverNumber
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: line.teamColour) ?? .gray).frame(width: 6, height: 6)
                            Text(line.acronym).font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Highlight \(line.name)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: focused)
    }
}

#Preview {
    // Synthetic 30-lap race: a safety car on laps 12–15 and a VSC on 22–23.
    let drivers: [(Int, String, String, [Int])] = [
        (63, "RUS", "00D7B6", [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]),
        (12, "ANT", "00D7B6", [6, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]),
        (16, "LEC", "ED1131", [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 3]),
        (44, "HAM", "ED1131", [5, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 4, 4, 3, 3, 3, 3, 3, 4]),
        (1, "NOR", "F47600", [3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5]),
        (81, "PIA", "F47600", [4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]),
    ]
    ScrollView {
        F1LapChartView(detail: F1SessionDetail(
            sessionKey: 1, sessionName: "Race", dateStart: "", totalLaps: 30, timing: nil,
            lapPositions: drivers.map { F1LapPositions(driverNumber: $0.0, acronym: $0.1, name: $0.1, teamColour: $0.2, positions: $0.3) },
            neutralizations: [F1Neutralization(kind: .safetyCar, startLap: 12, endLap: 15),
                              F1Neutralization(kind: .virtualSafetyCar, startLap: 22, endLap: 23)],
            redFlagLaps: [],
            weather: F1WeatherSummary(airTempMin: 31, airTempMax: 33.7, trackTempMin: 55, trackTempMax: 61.6, rainfall: false)
        ))
        .padding()
    }
}
