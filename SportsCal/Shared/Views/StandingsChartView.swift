//
//  StandingsChartView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import Charts
import SportsCalModel

/// Line chart showing team ranking/position changes over a 30-day window.
/// Y-axis is rank (inverted — 1 at top), X-axis is date.
/// Favorite teams get thicker lines, others are dimmed.
struct StandingsChartView: View {
    let sport: SportType
    @Environment(Favorites.self) private var favorites

    @State private var viewModel = StandingsViewModel()
    @State private var selectedLeagueID: Int?
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
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(sport.color)
                    Text("Standings Movement")
                        .font(.headline)
                    Spacer()
                }

                // League picker for soccer (multiple leagues)
                if leagueOptions.count > 1 {
                    Picker("League", selection: Binding(
                        get: { activeLeagueID },
                        set: { newValue in
                            selectedLeagueID = newValue
                            Task { await viewModel.loadHistory(leagueID: newValue) }
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
                } else if viewModel.snapshots.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.flattrend.xyaxis")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No standings history yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Data builds over time as daily snapshots are recorded.")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    chartContent
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
            .task {
                await viewModel.loadHistory(leagueID: activeLeagueID)
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartContent: some View {
        let dataPoints = buildDataPoints()
        Chart(dataPoints) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Position", point.position),
                series: .value("Team", point.teamName)
            )
            .foregroundStyle(point.teamColor.opacity(point.isFavorite ? 1.0 : 0.3))
            .lineStyle(StrokeStyle(lineWidth: point.isFavorite ? 3.0 : 1.0))
            .interpolationMethod(.catmullRom)
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let pos = value.as(Int.self) {
                    AxisValueLabel { Text("\(pos)").font(.caption2) }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartYScale(domain: .automatic(reversed: true))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // Find nearest team at tap point
                        if let date: Date = proxy.value(atX: location.x),
                           let position: Double = proxy.value(atY: location.y) {
                            let nearest = dataPoints
                                .filter { abs($0.date.timeIntervalSince(date)) < 86400 }
                                .min(by: { abs(Double($0.position) - position) < abs(Double($1.position) - position) })
                            selectedTeam = nearest?.teamName
                        }
                    }
            }
        }
        .frame(height: 250)

        // Selected team info
        if let selected = selectedTeam,
           let lastSnapshot = viewModel.snapshots.last,
           let entry = lastSnapshot.entries.first(where: { $0.teamName == selected }) {
            HStack {
                if let hex = entry.teamColor {
                    Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
                }
                Text(selected).font(.caption.bold())
                Spacer()
                if let w = entry.wins, let l = entry.losses {
                    Text("\(w)-\(l)").font(.caption).foregroundColor(.secondary)
                }
                Text("#\(entry.position)").font(.caption.bold())
            }
            .padding(.horizontal, 4)
        }

        // Favorite teams legend
        let favTeams = uniqueFavoriteTeams(from: dataPoints)
        if !favTeams.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(favTeams, id: \.name) { team in
                    HStack(spacing: 4) {
                        Circle().fill(team.color).frame(width: 8, height: 8)
                        Text(team.abbr ?? team.name)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(team.color.opacity(0.1), in: Capsule())
                    .onTapGesture { selectedTeam = team.name }
                }
            }
        }
    }

    // MARK: - Data

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let position: Int
        let teamName: String
        let teamColor: Color
        let isFavorite: Bool
        let abbreviation: String?
    }

    private func buildDataPoints() -> [ChartPoint] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var points: [ChartPoint] = []
        for snapshot in viewModel.snapshots {
            guard let date = dateFormatter.date(from: snapshot.date) else { continue }
            for entry in snapshot.entries {
                let color: Color = entry.teamColor.map { Color(hex: $0) } ?? .gray
                let isFav = favorites.teams.contains(entry.teamName)
                points.append(ChartPoint(
                    date: date,
                    position: entry.position,
                    teamName: entry.teamName,
                    teamColor: color,
                    isFavorite: isFav,
                    abbreviation: entry.teamAbbreviation
                ))
            }
        }
        return points
    }

    private struct FavTeamInfo: Hashable {
        let name: String
        let color: Color
        let abbr: String?
        func hash(into hasher: inout Hasher) { hasher.combine(name) }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    }

    private func uniqueFavoriteTeams(from points: [ChartPoint]) -> [FavTeamInfo] {
        var seen = Set<String>()
        return points.compactMap { point in
            guard point.isFavorite, seen.insert(point.teamName).inserted else { return nil }
            return FavTeamInfo(name: point.teamName, color: point.teamColor, abbr: point.abbreviation)
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}
