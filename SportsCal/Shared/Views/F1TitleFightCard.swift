//
//  F1TitleFightCard.swift
//  SportsCal
//

import SwiftUI
import SportsCalModel

/// Who can still win the championship and what the leader needs next round.
/// Each contender's bar is their points (solid) plus everything still available
/// (faded); a rival is alive while the faded end reaches the leader's line.
struct F1TitleFightCard: View {
    let standings: F1Standings

    @State private var kind: F1TitleFight.Kind = .drivers

    private static let maxRows = 5

    var body: some View {
        if let fight = standings.titleFight(kind), fight.remainingRaces > 0 || fight.champion != nil {
            VStack(alignment: .leading, spacing: 12) {
                header(fight)

                Picker("Championship", selection: $kind) {
                    Text("Drivers").tag(F1TitleFight.Kind.drivers)
                    Text("Constructors").tag(F1TitleFight.Kind.constructors)
                }
                .pickerStyle(.segmented)

                bars(fight)

                outlook(fight)
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
            .animation(.smooth, value: kind)
        }
    }

    private func header(_ fight: F1TitleFight) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Title Fight")
                .font(.headline)
            Spacer()
            Text(roundsLeftText(fight))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func roundsLeftText(_ fight: F1TitleFight) -> String {
        var parts = ["\(fight.remainingRaces) race\(fight.remainingRaces == 1 ? "" : "s")"]
        if fight.remainingSprints > 0 {
            parts.append("\(fight.remainingSprints) sprint\(fight.remainingSprints == 1 ? "" : "s")")
        }
        return parts.joined(separator: " + ") + " · \(fight.pointsAvailable) pts left"
    }

    // MARK: - Bars

    private func bars(_ fight: F1TitleFight) -> some View {
        let shown = Array(fight.contenders.prefix(Self.maxRows))
        let leaderPoints = fight.contenders.first?.points ?? 0
        let scaleMax = max(shown.map(\.maxPossible).max() ?? 1, 1)
        let outCount = totalEntrants - fight.contenders.count

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(shown, id: \.name) { contender in
                HStack(spacing: 8) {
                    Text(displayName(contender.name))
                        .font(.caption.weight(contender.gap == 0 ? .bold : .semibold))
                        .lineLimit(1)
                        .frame(width: 84, alignment: .leading)

                    GeometryReader { geo in
                        let w = geo.size.width
                        let color = color(for: contender.name)
                        ZStack(alignment: .leading) {
                            Capsule().fill(color.opacity(0.18))
                                .frame(width: w * contender.maxPossible / scaleMax)
                            Capsule().fill(color)
                                .frame(width: w * contender.points / scaleMax)
                            Rectangle()
                                .fill(Color.primary.opacity(0.5))
                                .frame(width: 1.5, height: geo.size.height + 6)
                                .offset(x: w * leaderPoints / scaleMax - 0.75)
                        }
                        .frame(height: geo.size.height)
                    }
                    .frame(height: 8)

                    Text(contender.gap == 0 ? points(contender.points) : "−" + points(contender.gap))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(contender.gap == 0 ? .primary : .secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(contender.name), \(points(contender.points)) points"
                    + (contender.gap == 0 ? ", leader" : ", \(points(contender.gap)) behind")
                    + ", can reach \(points(contender.maxPossible))")
            }

            if fight.contenders.count > shown.count || outCount > 0 {
                Text(footnote(hidden: fight.contenders.count - shown.count, out: outCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var totalEntrants: Int {
        kind == .drivers ? standings.driverStandings.count : standings.constructorStandings.count
    }

    private func footnote(hidden: Int, out: Int) -> String {
        var parts: [String] = []
        if hidden > 0 { parts.append("\(hidden) more still in contention") }
        if out > 0 { parts.append("\(out) mathematically out") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Outlook

    @ViewBuilder
    private func outlook(_ fight: F1TitleFight) -> some View {
        if let champion = fight.champion {
            Label("\(displayName(champion)) \(fight.remainingRaces > 0 ? "has clinched" : "won") the \(kind == .drivers ? "drivers'" : "constructors'") title",
                  systemImage: "trophy.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        } else if let clinch = fight.clinchNextRound {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(displayName(clinch.leader)) can clinch \(nextRoundPhrase)",
                      systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                if clinch.margins.isEmpty {
                    Text("Guaranteed once the round is complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(clinch.margins, id: \.rival) { margin in
                        Text("• " + requirement(rival: displayName(margin.rival), margin: margin.points))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if let leader = fight.contenders.first, let second = fight.contenders.dropFirst().first {
            Text("No title decider \(nextRoundPhrase): \(displayName(leader.name)) leads \(displayName(second.name)) by \(points(second.gap)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nextRoundPhrase: String {
        guard let name = standings.nextRoundName else { return "next round" }
        return "at the \(name.replacingOccurrences(of: "Grand Prix", with: "GP"))"
    }

    /// Margin > 0: must outscore. ≤ 0: can afford to be outscored by up to -margin.
    private func requirement(rival: String, margin: Int) -> String {
        if margin > 0 { return "Outscore \(rival) by \(margin)+ points" }
        if margin == 0 { return "Don't be outscored by \(rival)" }
        return "Don't be outscored by \(rival) by more than \(-margin)"
    }

    // MARK: - Helpers

    private func displayName(_ name: String) -> String {
        guard kind == .drivers else { return name }
        return name.split(separator: " ").last.map(String.init) ?? name
    }

    private func color(for name: String) -> Color {
        let team = kind == .drivers
            ? standings.driverStandings.first { $0.driverName == name }?.constructorName ?? ""
            : name
        return F1GapRibbonView.colorForConstructorName(team, standings: standings)
    }

    private func points(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

#Preview("Round 15, 2026") {
    let drivers: [(String, String, Double)] = [
        ("Kimi Antonelli", "Mercedes", 302), ("George Russell", "Mercedes", 236), ("Lewis Hamilton", "Ferrari", 199),
        ("Lando Norris", "McLaren", 186), ("Oscar Piastri", "McLaren", 120), ("Max Verstappen", "Red Bull", 92),
        ("Charles Leclerc", "Ferrari", 60),
    ]
    ScrollView {
        F1TitleFightCard(standings: F1Standings(
            driverStandings: drivers.enumerated().map { i, d in
                F1DriverStanding(position: i + 1, driverName: d.0, constructorName: d.1, points: d.2, wins: 0)
            },
            constructorStandings: [
                F1ConstructorStanding(position: 1, constructorName: "Mercedes", points: 538, wins: 11),
                F1ConstructorStanding(position: 2, constructorName: "Ferrari", points: 259, wins: 1),
                F1ConstructorStanding(position: 3, constructorName: "McLaren", points: 306, wins: 2),
            ],
            round: 15, remainingRaces: 8, remainingSprints: 1,
            nextRoundName: "Bahrain Grand Prix in Malaysia", nextRoundHasSprint: false
        ))
        .padding()
    }
}

#Preview("Clinch next round") {
    ScrollView {
        F1TitleFightCard(standings: F1Standings(
            driverStandings: [
                F1DriverStanding(position: 1, driverName: "Kimi Antonelli", constructorName: "Mercedes", points: 402, wins: 12),
                F1DriverStanding(position: 2, driverName: "George Russell", constructorName: "Mercedes", points: 360, wins: 4),
                F1DriverStanding(position: 3, driverName: "Lewis Hamilton", constructorName: "Ferrari", points: 330, wins: 2),
            ],
            round: 21, remainingRaces: 2, remainingSprints: 0,
            nextRoundName: "Qatar Grand Prix", nextRoundHasSprint: false
        ))
        .padding()
    }
}
