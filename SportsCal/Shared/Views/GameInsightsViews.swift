//
//  GameInsightsViews.swift
//  SportsCal
//
//  Detail-screen panels built on ESPN's situation and statistics: the live situation
//  panel, the win-probability chart, side-by-side team stats, and the team page's
//  league-rank card. Content only — each theme wraps them in its own card chrome.
//

import SwiftUI
import Charts
import SportsCalModel

// MARK: - Live situation panel

/// The full live state for a detail screen: a large diamond with the count, outs and
/// matchup in baseball; down, distance, field position and timeouts in football; and
/// the win-probability split.
struct LiveSituationPanel: View {
    let situation: GameSituation
    let sport: SportType?
    let homeName: String
    let awayName: String
    private let rawHomeColor: Color
    private let rawAwayColor: Color

    @Environment(\.self) private var environment
    private var homeColor: Color { rawHomeColor.legible(in: environment) }
    private var awayColor: Color { rawAwayColor.legible(in: environment) }

    init(situation: GameSituation, sport: SportType?, homeName: String, awayName: String, homeColor: Color, awayColor: Color) {
        self.situation = situation
        self.sport = sport
        self.homeName = homeName
        self.awayName = awayName
        self.rawHomeColor = homeColor
        self.rawAwayColor = awayColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sport == .mlb, situation.hasBaseballState {
                baseball
            } else if sport == .nfl, situation.hasFootballState {
                football
            }
            if let home = situation.homeWinProbability {
                winProbability(home: home)
            }
        }
    }

    private var baseball: some View {
        HStack(alignment: .center, spacing: 16) {
            BaseDiamond(first: situation.onFirst == true, second: situation.onSecond == true,
                        third: situation.onThird == true, size: 44, tint: .primary)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    if let balls = situation.balls, let strikes = situation.strikes {
                        labeled("COUNT") {
                            Text("\(balls)-\(strikes)").font(.title3.weight(.semibold).monospacedDigit())
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Count \(balls) balls, \(strikes) strikes")
                    }
                    if let outs = situation.outs {
                        labeled("OUTS") {
                            OutsIndicator(outs: outs, dotSize: 9).frame(height: 24)
                        }
                    }
                }
                if let batter = situation.batter {
                    matchupLine(role: "AB", name: batter, line: situation.batterLine)
                }
                if let pitcher = situation.pitcher {
                    matchupLine(role: "P", name: pitcher, line: situation.pitcherLine)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var football: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let side = situation.possession {
                    Label(side == .home ? homeName : awayName, systemImage: "football.fill")
                        .font(.headline)
                        .foregroundStyle(side == .home ? homeColor : awayColor)
                }
                Spacer(minLength: 0)
                if situation.isRedZone == true {
                    Text("RED ZONE")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
            if let text = situation.downDistanceText ?? situation.shortDownDistanceText {
                Text(text).font(.title3.weight(.semibold))
            }
            if situation.homeTimeouts != nil || situation.awayTimeouts != nil {
                HStack(spacing: 16) {
                    timeouts(name: awayName, count: situation.awayTimeouts, color: awayColor)
                    timeouts(name: homeName, count: situation.homeTimeouts, color: homeColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func winProbability(home: Double) -> some View {
        let away = 1 - home - (situation.tieProbability ?? 0)
        return VStack(spacing: 6) {
            HStack {
                Text(awayName).foregroundStyle(.secondary)
                Text("\(Int((away * 100).rounded()))%").font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer()
                Text("WIN PROBABILITY").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int((home * 100).rounded()))%").font(.subheadline.weight(.semibold).monospacedDigit())
                Text(homeName).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            WinProbabilityBar(home: home, homeColor: homeColor, awayColor: awayColor, height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Win probability: \(awayName) \(Int((away * 100).rounded())) percent, \(homeName) \(Int((home * 100).rounded())) percent")
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func matchupLine(role: String, name: String, line: String?) -> some View {
        HStack(spacing: 6) {
            Text(role)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
            if let line {
                Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func timeouts(name: String, count: Int?, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(name)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < (count ?? 0) ? color : Color.secondary.opacity(0.25))
                        .frame(width: 10, height: 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count ?? 0) timeouts left")
    }
}

// MARK: - Win probability chart

/// The game's win-probability history: home above the 50% line in the home color,
/// away below in theirs, with period boundaries marked.
struct WinProbabilityChart: View {
    let series: WinProbabilitySeries
    let homeName: String
    let awayName: String
    let homeColor: Color
    let awayColor: Color
    /// Labels each period boundary ("Q2", "P3", "4"); nil hides the labels.
    var periodLabel: ((Int) -> String)? = nil

    @Environment(\.self) private var environment
    private var homeTint: Color { homeColor.legible(in: environment) }
    private var awayTint: Color { awayColor.legible(in: environment) }

    private struct Point: Identifiable {
        let id: Int
        let home: Double
    }

    private var points: [Point] {
        series.home.enumerated().map { Point(id: $0.offset, home: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(awayName, systemImage: "circle.fill").foregroundStyle(awayTint)
                Spacer()
                if let last = series.home.last {
                    WinProbabilityLabel(home: last, homeName: homeName, awayName: awayName)
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Label(homeName, systemImage: "circle.fill").foregroundStyle(homeTint)
                    .labelStyle(TrailingIconLabelStyle())
            }
            .font(.caption)
            .imageScale(.small)

            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Play", point.id),
                        yStart: .value("Even", 0.5),
                        yEnd: .value("Home", max(point.home, 0.5)),
                        series: .value("Side", "home")
                    )
                    .foregroundStyle(homeTint.opacity(0.6))
                    .interpolationMethod(.linear)
                    AreaMark(
                        x: .value("Play", point.id),
                        yStart: .value("Away", min(point.home, 0.5)),
                        yEnd: .value("Even", 0.5),
                        series: .value("Side", "away")
                    )
                    .foregroundStyle(awayTint.opacity(0.6))
                    .interpolationMethod(.linear)
                }
                RuleMark(y: .value("Even", 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(Array(series.periodStarts.enumerated()), id: \.offset) { index, start in
                    RuleMark(x: .value("Period", start))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                        .annotation(position: .bottom, alignment: .leading, spacing: 2) {
                            if let periodLabel {
                                Text(periodLabel(index + 2)).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .chartYScale(domain: 0...1)
            .chartXScale(domain: 0...max(series.home.count - 1, 1))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v == 0.5 ? "50%" : (v > 0.5 ? homeName : awayName))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var accessibilitySummary: String {
        guard let last = series.home.last else { return "Win probability chart" }
        let peakHome = Int(((series.home.max() ?? 0.5) * 100).rounded())
        let peakAway = Int(((1 - (series.home.min() ?? 0.5)) * 100).rounded())
        let leader = last >= 0.5 ? homeName : awayName
        return "Win probability chart. \(homeName) peaked at \(peakHome) percent, \(awayName) at \(peakAway) percent. Now \(leader) \(Int((max(last, 1 - last) * 100).rounded())) percent."
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - Team stats

/// Side-by-side team stats: away on the left, home on the right, a bar per row
/// showing the split, the better side emphasized.
struct TeamStatComparisonView: View {
    let stats: TeamStatComparison
    let homeName: String
    let awayName: String
    private let rawHomeColor: Color
    private let rawAwayColor: Color

    @Environment(\.self) private var environment
    private var homeColor: Color { rawHomeColor.legible(in: environment) }
    private var awayColor: Color { rawAwayColor.legible(in: environment) }

    init(stats: TeamStatComparison, homeName: String, awayName: String, homeColor: Color, awayColor: Color) {
        self.stats = stats
        self.homeName = homeName
        self.awayName = awayName
        self.rawHomeColor = homeColor
        self.rawAwayColor = awayColor
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(awayName).foregroundStyle(awayColor)
                Spacer()
                Text(homeName).foregroundStyle(homeColor)
            }
            .font(.caption.weight(.bold))

            ForEach(stats.rows) { row in
                StatRow(row: row, homeColor: homeColor, awayColor: awayColor, homeName: homeName, awayName: awayName)
            }
        }
    }

    private struct StatRow: View {
        let row: TeamStatComparison.Row
        let homeColor: Color
        let awayColor: Color
        let homeName: String
        let awayName: String

        /// Which side the row favors, if the values are comparable and differ.
        private var better: GameSituation.Side? {
            guard let h = row.homeValue, let a = row.awayValue, h != a else { return nil }
            let homeHigher = h > a
            return (homeHigher != (row.lowerIsBetter == true)) ? .home : .away
        }

        /// Away share of the bar.
        private var awayShare: Double? {
            guard let h = row.homeValue, let a = row.awayValue, h >= 0, a >= 0, h + a > 0 else { return nil }
            return a / (h + a)
        }

        var body: some View {
            VStack(spacing: 4) {
                HStack {
                    Text(row.away)
                        .fontWeight(better == .away ? .bold : .regular)
                        .foregroundStyle(better == .home ? .secondary : .primary)
                    Spacer()
                    Text(row.label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.home)
                        .fontWeight(better == .home ? .bold : .regular)
                        .foregroundStyle(better == .away ? .secondary : .primary)
                }
                .font(.subheadline.monospacedDigit())

                if let awayShare {
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            Capsule().fill(awayColor.opacity(better == .home ? 0.35 : 0.9))
                                .frame(width: max(proxy.size.width * awayShare - 1, 0))
                            Capsule().fill(homeColor.opacity(better == .away ? 0.35 : 0.9))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.label): \(awayName) \(row.away), \(homeName) \(row.home)")
        }
    }
}

// MARK: - Team rank card

/// Where a team ranks in its league on the stats that matter.
struct TeamRankCard: View {
    let stats: TeamSeasonStats
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(stats.isPreviousSeason ? "\(stats.season) season (last season)" : "\(stats.season) season")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(stats.stats) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(stat.value).font(.headline.monospacedDigit())
                            if let rank = stat.rankDisplay {
                                Text(rank)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle((stat.rank ?? .max) <= 5 ? Color.white : Color.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill((stat.rank ?? .max) <= 5 ? accent : Color.secondary.opacity(0.15))
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stat.label): \(stat.value)\(stat.rankDisplay.map { ", ranked \($0) in the league" } ?? "")")
                }
            }
        }
    }
}

// MARK: - Helpers

extension GameDetailSectionsModel {
    /// The labels that mark period boundaries on a win-probability chart.
    static func periodLabel(for sport: SportType?) -> ((Int) -> String)? {
        guard let sport else { return nil }
        switch sport {
        case .basketball, .nfl:
            return { $0 <= 4 ? "Q\($0)" : ($0 == 5 ? "OT" : "\($0 - 4)OT") }
        case .hockey:
            return { $0 <= 3 ? "P\($0)" : "OT" }
        case .mlb:
            return { "\($0)" }
        default:
            return nil
        }
    }
}
