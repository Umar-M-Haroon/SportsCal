//
//  StatScatterView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import Charts
import SportsCalModel

/// Scatter plot where users pick two stats for X and Y axes and see all teams plotted.
/// Each team is a dot colored with their hex color. Favorite teams are highlighted.
struct StatScatterView: View {
    let sport: SportType
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage

    @State private var viewModel = TeamStatsViewModel()
    @State private var selectedLeagueID: Int?
    @State private var xStat: String = ""
    @State private var yStat: String = ""
    @State private var selectedTeam: String?

    private var leagueOptions: [(name: String, id: Int)] {
        switch sport {
        case .basketball: return [("NBA", 4387)]
        case .nfl: return [("NFL", 4391)]
        case .hockey: return [("NHL", 4380)]
        case .mlb: return [("MLB", 4424)]
        case .soccer: return [
            ("Premier League", 4328),
            ("La Liga", 4335),
            ("Bundesliga", 4331),
            ("Serie A", 4332),
            ("Ligue 1", 4334),
            ("MLS", 4346)
        ]
        case .golf, .tennis, .racing: return []
        }
    }

    private var activeLeagueID: Int {
        selectedLeagueID ?? leagueOptions.first?.id ?? 0
    }

    var body: some View {
        if !leagueOptions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.dots.scatter")
                        .foregroundColor(sport.color)
                    Text("Team Comparison")
                        .font(.headline)
                    Spacer()
                }

                // League picker for soccer
                if leagueOptions.count > 1 {
                    Picker("League", selection: Binding(
                        get: { activeLeagueID },
                        set: { newValue in
                            selectedLeagueID = newValue
                            xStat = ""
                            yStat = ""
                            Task { await viewModel.load(leagueID: newValue) }
                        }
                    )) {
                        ForEach(leagueOptions, id: \.id) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else if viewModel.teams.isEmpty {
                    Text("No team stats available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    statPickers
                    if !xStat.isEmpty && !yStat.isEmpty {
                        scatterChart
                    }
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
            .task {
                await viewModel.load(leagueID: activeLeagueID)
            }
            .onChange(of: viewModel.availableStats) { _, stats in
                if xStat.isEmpty, stats.count >= 2 {
                    // Pick sensible defaults
                    xStat = pickDefault(stats, prefer: ["wins", "gamesPlayed", "pointsFor"])
                    yStat = pickDefault(stats, prefer: ["losses", "pointDifferential", "pointsAgainst"], excluding: xStat)
                }
            }
        }
    }

    // MARK: - Stat Pickers

    @ViewBuilder
    private var statPickers: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("X Axis").font(.caption2).foregroundColor(.secondary)
                Picker("X", selection: $xStat) {
                    ForEach(viewModel.availableStats, id: \.self) { stat in
                        Text(formatStatName(stat)).tag(stat)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Y Axis").font(.caption2).foregroundColor(.secondary)
                Picker("Y", selection: $yStat) {
                    ForEach(viewModel.availableStats, id: \.self) { stat in
                        Text(formatStatName(stat)).tag(stat)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Scatter Chart

    @ViewBuilder
    private var scatterChart: some View {
        let points = buildPoints()
        let xValues = points.map(\.x)
        let yValues = points.map(\.y)
        let xAvg = xValues.isEmpty ? 0 : xValues.reduce(0, +) / Double(xValues.count)
        let yAvg = yValues.isEmpty ? 0 : yValues.reduce(0, +) / Double(yValues.count)

        Chart {
            // Average lines (quadrant dividers)
            RuleMark(x: .value("Avg", xAvg))
                .foregroundStyle(.gray.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            RuleMark(y: .value("Avg", yAvg))
                .foregroundStyle(.gray.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Team dots
            ForEach(points) { point in
                PointMark(
                    x: .value(formatStatName(xStat), point.x),
                    y: .value(formatStatName(yStat), point.y)
                )
                .foregroundStyle(point.color)
                .symbolSize(point.isFavorite ? 120 : 60)
                .annotation(position: .top, spacing: 2) {
                    if point.isFavorite || point.teamName == selectedTeam {
                        Text(point.abbreviation)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(point.color)
                    }
                }
            }
        }
        .chartXAxisLabel(formatStatName(xStat))
        .chartYAxisLabel(formatStatName(yStat))
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel().font(.caption2)
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel().font(.caption2)
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let xVal: Double = proxy.value(atX: location.x),
                           let yVal: Double = proxy.value(atY: location.y) {
                            let nearest = points.min(by: { a, b in
                                let da = pow(a.x - xVal, 2) + pow(a.y - yVal, 2)
                                let db = pow(b.x - xVal, 2) + pow(b.y - yVal, 2)
                                return da < db
                            })
                            selectedTeam = nearest?.teamName
                        }
                    }
            }
        }
        .frame(height: 280)

        // Selected team detail
        if let selected = selectedTeam,
           let team = viewModel.teams.first(where: { $0.teamName == selected }) {
            HStack {
                Circle().fill(Color(hex: team.teamColor)).frame(width: 10, height: 10)
                Text(team.teamName).font(.caption.bold())
                Spacer()
                if let xVal = team.statValue(xStat) {
                    Text("\(formatStatName(xStat)): \(xVal, specifier: "%.1f")")
                        .font(.caption2).foregroundColor(.secondary)
                }
                if let yVal = team.statValue(yStat) {
                    Text("\(formatStatName(yStat)): \(yVal, specifier: "%.1f")")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Data

    private struct ScatterPoint: Identifiable {
        let id = UUID()
        let teamName: String
        let abbreviation: String
        let x: Double
        let y: Double
        let color: Color
        let isFavorite: Bool
    }

    private func buildPoints() -> [ScatterPoint] {
        viewModel.teams.compactMap { team in
            guard let x = team.statValue(xStat),
                  let y = team.statValue(yStat) else { return nil }
            return ScatterPoint(
                teamName: team.teamName,
                abbreviation: team.teamAbbreviation,
                x: x,
                y: y,
                color: Color(hex: team.teamColor),
                isFavorite: favorites.teams.contains(team.teamName)
            )
        }
    }

    // MARK: - Helpers

    private func formatStatName(_ name: String) -> String {
        // Convert camelCase to Title Case
        var result = ""
        for char in name {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result += String(char)
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    private func pickDefault(_ stats: [String], prefer: [String], excluding: String? = nil) -> String {
        for pref in prefer {
            if let match = stats.first(where: { $0.lowercased() == pref.lowercased() && $0 != excluding }) {
                return match
            }
        }
        return stats.first(where: { $0 != excluding }) ?? stats.first ?? ""
    }
}
