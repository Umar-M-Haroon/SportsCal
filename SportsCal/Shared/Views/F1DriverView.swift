//
//  F1DriverView.swift
//  SportsCal
//

import SwiftUI
import Charts
import SportsCalModel

/// A driver's season: championship standing, headline stats, points progression against
/// the leader, and race-by-race results. Rebuilt from weekends already in the schedule.
struct F1DriverView: View {
    let driverName: String

    @Environment(GameViewModel.self) private var viewModel

    var body: some View {
        F1DriverContent(
            driverName: driverName,
            standings: viewModel.f1Standings,
            weekends: (viewModel.totalGames ?? []).filter { $0.sportType == .racing }
        )
    }
}

/// Environment-free body so previews and snapshots can feed data directly.
struct F1DriverContent: View {
    let driverName: String
    let standings: F1Standings?
    let weekends: [Game]

    /// The season of the most recent finished race weekend: right through the
    /// off-season, when "now" would point at a season with no results yet.
    private var seasonWeekends: [Game] {
        let calendar = Calendar.current
        let finished = weekends.filter { weekend in
            weekend.sessions?.contains { $0.importance >= 5 && $0.status == "post" && !$0.leaderboard.isEmpty } ?? false
        }
        guard let latest = finished.compactMap(\.isoDate).max() else { return [] }
        let year = calendar.component(.year, from: latest)
        return weekends.filter { $0.isoDate.map { calendar.component(.year, from: $0) } == year }
    }

    var body: some View {
        let weekends = seasonWeekends
        let season = F1DriverSeason(driverName: driverName, weekends: weekends)
        let standing = standings?.driverStanding(matching: driverName)
        let leaderName = standings?.driverStandings.first?.driverName
        let leaderSeason = leaderName.flatMap { $0 == standing?.driverName ? nil : F1DriverSeason(driverName: $0, weekends: weekends) }
        let teamColor = F1GapRibbonView.colorForConstructorName(
            standing?.constructorName ?? season.rounds.last?.constructor ?? "", standings: standings)

        ScrollView {
            VStack(spacing: 20) {
                header(season: season, standing: standing, teamColor: teamColor)
                statsRow(season: season, standing: standing)
                if season.rounds.count >= 2 {
                    progression(season: season, leader: leaderSeason, teamColor: teamColor)
                }
                results(season: season)
            }
            .padding()
        }
        .navigationTitle(driverName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Header

    private func header(season: F1DriverSeason, standing: F1DriverStanding?, teamColor: Color) -> some View {
        HStack(spacing: 14) {
            HeadshotView(url: season.rounds.last?.headshot, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(driverName)
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5).fill(teamColor).frame(width: 3, height: 14)
                    Text(standing?.constructorName ?? season.rounds.last?.constructor ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let nationality = standing?.nationality {
                        Text("· \(nationality)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let standing {
                VStack(spacing: 0) {
                    Text("P\(standing.position)")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(teamColor)
                    Text("\(points(standing.points)) pts")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Championship position \(standing.position), \(points(standing.points)) points")
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Stats

    private func statsRow(season: F1DriverSeason, standing: F1DriverStanding?) -> some View {
        HStack(spacing: 0) {
            stat("\(standing?.wins ?? season.wins)", "Wins")
            stat("\(season.podiums)", "Podiums")
            stat(season.bestFinish.map { "P\($0)" } ?? "–", "Best")
            stat(season.averageFinish.map { String(format: "%.1f", $0) } ?? "–", "Avg finish")
        }
        .padding(.vertical, 12)
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Points progression

    private func progression(season: F1DriverSeason, leader: F1DriverSeason?, teamColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Points by Round").font(.headline)
                Spacer()
                if let leader {
                    Text("vs \(surname(leader.driverName)) (leader)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                if let leader {
                    ForEach(leader.rounds) { round in
                        LineMark(x: .value("Round", round.roundNumber), y: .value("Points", round.cumulativePoints),
                                 series: .value("Driver", "leader"))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                ForEach(season.rounds) { round in
                    LineMark(x: .value("Round", round.roundNumber), y: .value("Points", round.cumulativePoints),
                             series: .value("Driver", "driver"))
                        .foregroundStyle(teamColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    if round.race == 1 {
                        PointMark(x: .value("Round", round.roundNumber), y: .value("Points", round.cumulativePoints))
                            .foregroundStyle(teamColor)
                            .symbolSize(30)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.1))
                    AxisValueLabel { if let r = value.as(Int.self) { Text("R\(r)") } }
                }
            }
            .chartXScale(domain: 1...max(season.rounds.last?.roundNumber ?? 0, leader?.rounds.last?.roundNumber ?? 0, 2))
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Points by round: \(season.rounds.last?.cumulativePoints ?? 0) points after \(season.rounds.count) rounds")
            Text("Dots mark wins. Computed from results; penalties can shift the official total.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Results

    private func results(season: F1DriverSeason) -> some View {
        let gamesByID = Dictionary(seasonWeekends.map { ($0.idEvent ?? $0.strHomeTeam, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Results").font(.headline)
            HStack(spacing: 0) {
                Text("Grand Prix").frame(maxWidth: .infinity, alignment: .leading)
                Text("Quali").frame(width: 42, alignment: .trailing)
                Text("Sprint").frame(width: 46, alignment: .trailing)
                Text("Race").frame(width: 42, alignment: .trailing)
                Text("Pts").frame(width: 34, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if season.rounds.isEmpty {
                Text("No results this season yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(season.rounds.reversed()) { round in
                let row = resultRow(round)
                if let game = gamesByID[round.gameID] {
                    NavigationLink { RaceDetailView(game: game) } label: { row }
                        .buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func resultRow(_ round: F1DriverSeason.Round) -> some View {
        HStack(spacing: 0) {
            Text(shortRaceName(round.raceName))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(round.qualifying.map { "\($0)" } ?? "–").frame(width: 42, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(round.sprint.map { "\($0)" } ?? "–").frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(round.race.map { "P\($0)" } ?? "DNS")
                .fontWeight((round.race ?? 99) <= 3 ? .bold : .regular)
                .frame(width: 42, alignment: .trailing)
            Text("\(round.points)").frame(width: 34, alignment: .trailing)
                .foregroundStyle(round.points > 0 ? .primary : .secondary)
        }
        .font(.caption.monospacedDigit())
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            shortRaceName(round.raceName),
            round.qualifying.map { "qualified \($0)" },
            round.sprint.map { "sprint \($0)" },
            round.race.map { "finished \($0)" } ?? "did not start",
            "\(round.points) points",
        ].compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: - Helpers

    /// "Qatar Airways Azerbaijan Grand Prix" → "Azerbaijan GP": drop the sponsor prefix
    /// by keeping the words right before "Grand Prix".
    private func shortRaceName(_ name: String) -> String {
        guard let range = name.range(of: "Grand Prix") else { return name }
        let before = name[..<range.lowerBound].split(separator: " ")
        let suffix = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
        // Multi-word place names that would otherwise be cut ("Abu Dhabi", "São Paulo", ...).
        let twoWord = ["Abu Dhabi", "São Paulo", "Las Vegas", "Saudi Arabian", "Emilia Romagna", "Mexico City", "United States"]
        let tail = before.suffix(2).joined(separator: " ")
        let place = twoWord.contains { tail.hasSuffix($0) } ? tail : String(before.last ?? "")
        return [place + " GP", suffix].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func surname(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }

    private func points(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

private func previewWeekend(_ id: String, _ name: String, day: Int, ant: Int, rus: Int, sprint: Int? = nil) -> Game {
    var sessions = [
        EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "post", leaderboard: [
            LeaderboardEntry(name: "Kimi Antonelli", score: "", position: max(ant - 1, 1), constructor: "Mercedes"),
            LeaderboardEntry(name: "George Russell", score: "", position: rus, constructor: "Mercedes"),
        ]),
        EventSession(sessionType: "Race", sessionName: "Race", status: "post", leaderboard: [
            LeaderboardEntry(name: "Kimi Antonelli", score: "", position: ant, constructor: "Mercedes"),
            LeaderboardEntry(name: "George Russell", score: "", position: rus, constructor: "Mercedes"),
        ]),
    ]
    if let sprint {
        sessions.insert(EventSession(sessionType: "SR", sessionName: "SR", status: "post", leaderboard: [
            LeaderboardEntry(name: "Kimi Antonelli", score: "", position: sprint, constructor: "Mercedes"),
        ]), at: 1)
    }
    return Game(idEvent: id, strHomeTeam: name, strAwayTeam: "",
                 isoDate: Date(timeIntervalSince1970: 1_773_000_000 + Double(day) * 86_400), sessions: sessions)
}

#Preview {
    let weekends = [
        previewWeekend("1", "Qatar Airways Australian Grand Prix", day: 0, ant: 2, rus: 1),
        previewWeekend("2", "Heineken Chinese Grand Prix", day: 7, ant: 1, rus: 3, sprint: 2),
        previewWeekend("3", "Aramco Japanese Grand Prix", day: 21, ant: 1, rus: 2),
        previewWeekend("4", "Crypto.com Miami Grand Prix", day: 56, ant: 4, rus: 1, sprint: 1),
        previewWeekend("5", "Lenovo Canadian Grand Prix", day: 77, ant: 1, rus: 5),
        previewWeekend("6", "Monaco Grand Prix", day: 91, ant: 3, rus: 2),
    ]
    NavigationStack {
        F1DriverContent(
            driverName: "Kimi Antonelli",
            standings: F1Standings(driverStandings: [
                F1DriverStanding(position: 1, driverName: "Kimi Antonelli", constructorName: "Mercedes", points: 302, wins: 8, nationality: "Italian"),
                F1DriverStanding(position: 2, driverName: "George Russell", constructorName: "Mercedes", points: 236, wins: 3),
            ]),
            weekends: weekends
        )
    }
}
