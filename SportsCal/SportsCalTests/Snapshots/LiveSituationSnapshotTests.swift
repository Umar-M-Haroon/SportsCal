//
//  LiveSituationSnapshotTests.swift
//  SportsCalTests
//
//  Renders the live-situation and game-insight components for visual review.
//  The win-probability series is ESPN's real IND 137–134 NY (OT) curve, every third
//  point; the box stats and ranks are real ESPN values from the model fixtures.
//

#if canImport(SnapshotTesting) && os(iOS)
import SnapshotTesting
import SwiftUI
import XCTest
import SportsCalModel
@testable import Scoreline

@MainActor
final class LiveSituationSnapshotTests: XCTestCase {

    private let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"

    private func snap<V: View>(_ view: V, _ name: String, height: CGFloat, testName: String = #function, line: UInt = #line) {
        for (slug, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let wrapped = view
                .padding(16)
                .frame(width: 390)
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, style == .dark ? .dark : .light)
            assertSnapshot(
                of: wrapped,
                as: .image(layout: .fixed(width: 390, height: height), traits: UITraitCollection(userInterfaceStyle: style)),
                named: "\(name)-\(slug)",
                record: record,
                testName: testName,
                line: line
            )
        }
    }

    private func card<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private let guardians = Color(red: 0.0, green: 0.17, blue: 0.36)
    private let tigers = Color(red: 0.98, green: 0.27, blue: 0.09)
    private let chiefs = Color(red: 0.89, green: 0.09, blue: 0.22)
    private let bills = Color(red: 0.0, green: 0.2, blue: 0.55)

    private let mlb = GameSituation(period: 9, inningHalf: .bottom, balls: 2, strikes: 1, outs: 1,
                                    onFirst: true, onSecond: false, onThird: true,
                                    batter: "S. Kwan", batterLine: "2-4, 2B", pitcher: "J. Duran", pitcherLine: "0.2 IP, 1 K",
                                    homeWinProbability: 0.312)
    private let nfl = GameSituation(period: 4, clock: 151, down: 3, distance: 4, yardLine: 12,
                                    downDistanceText: "3rd & 4 at KC 12", shortDownDistanceText: "3rd & 4",
                                    possession: .away, isRedZone: true, homeTimeouts: 2, awayTimeouts: 1,
                                    homeWinProbability: 0.58)

    func test_strips() {
        let view = VStack(alignment: .leading, spacing: 16) {
            GameStateStrip(situation: mlb, sport: .mlb, homeName: "CLE", awayName: "DET")
            GameStateStrip(situation: nfl, sport: .nfl, homeName: "KC", awayName: "BUF")
            GameStateStrip(situation: GameSituation(period: 4, clock: 95, homeWinProbability: 0.71), sport: .basketball, homeName: "NY", awayName: "IND")
            LiveActivitySituationStrip(situation: LiveActivitySituation(mlb)!, homeName: "CLE", awayName: "DET")
            LiveActivitySituationStrip(situation: LiveActivitySituation(nfl)!, homeName: "KC", awayName: "BUF")
            HStack { ExcitementBadge(tier: .classic); ExcitementBadge(tier: .thriller) }
        }
        snap(view, "strips", height: 260)
    }

    func test_livePanels() {
        let view = VStack(spacing: 16) {
            card("Live") {
                LiveSituationPanel(situation: mlb, sport: .mlb, homeName: "CLE", awayName: "DET", homeColor: guardians, awayColor: tigers)
            }
            card("Live") {
                LiveSituationPanel(situation: nfl, sport: .nfl, homeName: "KC", awayName: "BUF", homeColor: chiefs, awayColor: bills)
            }
        }
        snap(view, "live-panels", height: 420)
    }

    func test_winProbabilityChart() {
        let series = WinProbabilitySeries(home: [0.794, 0.825, 0.821, 0.81, 0.805, 0.847, 0.851, 0.838, 0.807, 0.786, 0.786, 0.779, 0.783, 0.818, 0.813, 0.831, 0.831, 0.831, 0.831, 0.815, 0.845, 0.841, 0.828, 0.794, 0.754, 0.754, 0.754, 0.728, 0.78, 0.724, 0.779, 0.767, 0.778, 0.778, 0.77, 0.702, 0.774, 0.78, 0.699, 0.619, 0.61, 0.665, 0.775, 0.775, 0.713, 0.753, 0.734, 0.789, 0.778, 0.666, 0.718, 0.65, 0.589, 0.639, 0.638, 0.638, 0.638, 0.636, 0.719, 0.793, 0.742, 0.708, 0.715, 0.753, 0.764, 0.742, 0.78, 0.761, 0.767, 0.784, 0.846, 0.864, 0.883, 0.865, 0.806, 0.847, 0.867, 0.832, 0.827, 0.751, 0.75, 0.723, 0.686, 0.686, 0.693, 0.649, 0.639, 0.647, 0.713, 0.712, 0.785, 0.743, 0.742, 0.71, 0.633, 0.64, 0.629, 0.738, 0.768, 0.768, 0.767, 0.734, 0.741, 0.765, 0.732, 0.692, 0.692, 0.65, 0.61, 0.633, 0.717, 0.604, 0.683, 0.59, 0.61, 0.61, 0.622, 0.749, 0.72, 0.751, 0.658, 0.748, 0.711, 0.698, 0.604, 0.6, 0.694, 0.737, 0.695, 0.536, 0.5, 0.512, 0.484, 0.41, 0.472, 0.356, 0.469, 0.539, 0.483, 0.609, 0.527, 0.349, 0.52, 0.425, 0.393, 0.386, 0.305, 0.492, 0.51, 0.213, 0.497, 0.35, 0.109, 0.246, 0.271, 0.186, 0.103, 0.161, 0.29, 0.382, 0.5, 0.5, 0.482, 0.383, 0.233, 0.202, 0.21, 0.139, 0.347, 0.06, 0.029, 0.011, 0.002, 0.001, 0.011, 0.042, 0.038, 0.094, 0.094, 0.145, 0.047, 0.064, 0.016, 0.007, 0.007], periodStarts: [32, 74, 114, 160])
        let view = card("Win Probability") {
            WinProbabilityChart(series: series, homeName: "NY", awayName: "IND",
                                homeColor: Color(red: 0.0, green: 0.42, blue: 0.71),
                                awayColor: Color(red: 0.99, green: 0.73, blue: 0.13),
                                league: .nba)
        }
        snap(view, "win-probability", height: 260)
    }

    func test_teamStats() {
        let stats = TeamStatComparison(rows: [
            .init(name: "totalYards", label: "Total Yards", home: "338", away: "361"),
            .init(name: "netPassingYards", label: "Passing", home: "211", away: "269"),
            .init(name: "rushingYards", label: "Rushing", home: "127", away: "92"),
            .init(name: "thirdDownEff", label: "3rd Down", home: "6-14", away: "4-13"),
            .init(name: "turnovers", label: "Turnovers", home: "1", away: "2", lowerIsBetter: true),
            .init(name: "possessionTime", label: "Possession", home: "28:49", away: "31:11"),
        ])
        let view = card("Team Stats") {
            TeamStatComparisonView(stats: stats, homeName: "CLE", awayName: "PIT",
                                   homeColor: Color(red: 0.19, green: 0.16, blue: 0.15),
                                   awayColor: Color(red: 1.0, green: 0.71, blue: 0.11))
        }
        snap(view, "team-stats", height: 380)
    }

    func test_rankCard() {
        let stats = TeamSeasonStats(season: "2025-26", isPreviousSeason: true, stats: [
            .init(name: "offensive.points", label: "Points / Game", value: "114.9", rank: 3, rankDisplay: "3rd"),
            .init(name: "offensive.fieldGoalPct", label: "FG %", value: "46.7", rank: 3, rankDisplay: "3rd"),
            .init(name: "offensive.threePointPct", label: "3PT %", value: "36.7", rank: 2, rankDisplay: "2nd"),
            .init(name: "offensive.trueShootingPct", label: "True Shooting %", value: "58.3", rank: 2, rankDisplay: "2nd"),
            .init(name: "offensive.assists", label: "Assists / Game", value: "24.6", rank: 4, rankDisplay: "4th"),
            .init(name: "general.reboundRate", label: "Rebound Rate", value: "52.9", rank: 1, rankDisplay: "Tied-1st"),
            .init(name: "defensive.steals", label: "Steals / Game", value: "7.1", rank: 5, rankDisplay: "5th"),
            .init(name: "defensive.blocks", label: "Blocks / Game", value: "5.0", rank: 12, rankDisplay: "12th"),
        ])
        let view = card("League Ranks") { TeamRankCard(stats: stats, accent: .orange) }
        snap(view, "rank-card", height: 330)
    }
}
#endif
