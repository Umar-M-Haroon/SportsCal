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

    @ViewBuilder
    private var baseball: some View {
        if let next = situation.dueUpSide {
            dueUp(next)
        } else {
            atBat
        }
    }

    /// Between half-innings: who bats next, instead of the finished half's three outs
    /// and its last batter.
    private func dueUp(_ side: GameSituation.Side) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.baseball")
                .font(.title2)
                .foregroundStyle(side == .home ? homeColor : awayColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("DUE UP").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(side == .home ? homeName : awayName).font(.title3.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side == .home ? homeName : awayName) due up")
    }

    private var atBat: some View {
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
                if let batting = situation.inningHalf?.battingSide {
                    Text("\(batting == .home ? homeName : awayName) batting")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(batting == .home ? homeColor : awayColor)
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
                    RedZonePill()
                }
            }
            if let text = situation.downDistanceText ?? situation.shortDownDistanceText {
                Text(text).font(.title3.weight(.semibold))
            }
            if let yardLine = situation.yardLine, let possession = situation.possession {
                FootballFieldView(
                    yardLine: yardLine, possession: possession, distance: situation.distance,
                    isRedZone: situation.isRedZone == true,
                    homeColor: homeColor, awayColor: awayColor
                )
            }
            // An unknown count is left off rather than drawn as none left.
            if situation.homeTimeouts != nil || situation.awayTimeouts != nil {
                HStack(spacing: 16) {
                    if let away = situation.awayTimeouts {
                        timeouts(name: awayName, count: away, color: awayColor)
                    }
                    if let home = situation.homeTimeouts {
                        timeouts(name: homeName, count: home, color: homeColor)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func winProbability(home: Double) -> some View {
        let away = situation.awayWinProbability ?? (1 - home)
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

    private func timeouts(name: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(name)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < count ? color : Color.secondary.opacity(0.25))
                        .frame(width: 10, height: 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) timeout\(count == 1 ? "" : "s") left")
    }
}

// MARK: - Football field

/// A strip of field: the ball at its spot, the line to gain, and the red zone the
/// offense is driving at. Away's end zone is on the left, matching the away-left
/// rows; ESPN's `yardLine` counts from the home goal line (0) to the away one (100).
struct FootballFieldView: View {
    let yardLine: Int
    let possession: GameSituation.Side
    let distance: Int?
    let isRedZone: Bool
    let homeColor: Color
    let awayColor: Color

    /// 0...1 from the left edge of the playing field (between the end zones).
    private func position(_ line: Int) -> CGFloat {
        CGFloat(100 - min(max(line, 0), 100)) / 100
    }

    /// Home drives toward yardLine 100 (left), away toward 0 (right).
    private var lineToGain: Int? {
        guard let distance, distance > 0 else { return nil }
        let target = possession == .home ? yardLine + distance : yardLine - distance
        return min(max(target, 0), 100)
    }

    var body: some View {
        GeometryReader { proxy in
            let endZone = proxy.size.width * 0.08
            let field = proxy.size.width - endZone * 2
            let x: (Int) -> CGFloat = { endZone + field * position($0) }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.18))
                // End zones: away on the left, home on the right.
                Rectangle().fill(awayColor.opacity(0.55)).frame(width: endZone)
                Rectangle().fill(homeColor.opacity(0.55)).frame(width: endZone)
                    .offset(x: endZone + field)
                // The red zone the offense is attacking: the 20 yards before the far goal.
                Rectangle()
                    .fill(Color.red.opacity(isRedZone ? 0.28 : 0.1))
                    .frame(width: field * 0.2)
                    .offset(x: possession == .home ? endZone : endZone + field * 0.8)
                ForEach([10, 20, 30, 40, 50, 60, 70, 80, 90], id: \.self) { line in
                    Rectangle()
                        .fill(Color.primary.opacity(line == 50 ? 0.35 : 0.15))
                        .frame(width: 1)
                        .offset(x: x(line))
                }
                if let gain = lineToGain {
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2)
                        .offset(x: x(gain) - 1)
                }
                Image(systemName: "football.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(possession == .home ? homeColor : awayColor)
                    .shadow(color: .black.opacity(0.25), radius: 1)
                    .offset(x: x(yardLine) - 7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 26)
        .accessibilityHidden(true)
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
    /// Names the periods on the boundary marks ("Q2", "H2", "OT"); nil hides the labels.
    var league: Leagues? = nil

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
                ForEach(series.boundaries(league: league), id: \.index) { boundary in
                    RuleMark(x: .value("Period", boundary.index))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                        .annotation(position: .bottom, alignment: .leading, spacing: 2) {
                            if league != nil {
                                Text(boundary.label).font(.system(size: 9)).foregroundStyle(.secondary)
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
