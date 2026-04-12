//
//  GolfScorecardView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/12/26.
//

import SwiftUI
import SportsCalModel

/// Full tournament scorecard: players down the left, holes 1-18 across the top.
/// Horizontally scrollable. Shows the latest round with hole-by-hole data for top players.
struct GolfScorecardView: View {
    let entries: [LeaderboardEntry]
    let coursePar: Int?
    let holePars: [Int]?
    var maxPlayers: Int = 15

    @State private var selectedRound: Int?
    @State private var showGlossary = false

    private var topEntries: [LeaderboardEntry] {
        entries.prefix(maxPlayers).filter { $0.roundDetails != nil && !($0.roundDetails?.isEmpty ?? true) }
    }

    /// Available round numbers across all entries
    private var availableRounds: [Int] {
        let allRounds = topEntries.flatMap { $0.roundDetails ?? [] }.map(\.roundNumber)
        return Array(Set(allRounds)).sorted()
    }

    /// Latest round that has actual hole score data for at least one player
    private var latestRoundWithData: Int {
        for round in availableRounds.reversed() {
            let hasData = topEntries.contains { entry in
                entry.roundDetails?.first(where: { $0.roundNumber == round })?.holeScores?.contains(where: { $0.score != nil }) ?? false
            }
            if hasData { return round }
        }
        return availableRounds.last ?? 1
    }

    private var displayRound: Int {
        selectedRound ?? latestRoundWithData
    }

    var body: some View {
        if !topEntries.isEmpty && !availableRounds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scorecard")
                        .font(.headline)
                    Spacer()
                    // Round picker
                    Picker("Round", selection: Binding(
                        get: { displayRound },
                        set: { selectedRound = $0 }
                    )) {
                        ForEach(availableRounds, id: \.self) { r in
                            Text("R\(r)").tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header: hole numbers with par underneath
                        headerRow
                        Divider()
                        // Player rows
                        ForEach(Array(topEntries.enumerated()), id: \.offset) { index, entry in
                            playerScorecardRow(entry: entry, isLeader: index == 0)
                            if index < topEntries.count - 1 {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }

                // Legend + glossary
                HStack(spacing: 12) {
                    legendItem(color: .yellow, label: "Ace")
                    legendItem(color: Color(red: 0, green: 0.5, blue: 0.7), label: "Eagle+")
                    legendItem(color: .green, label: "Birdie")
                    legendItem(color: Color.gray.opacity(0.3), label: "Par")
                    legendItem(color: Color(red: 0.85, green: 0.35, blue: 0.15), label: "Bogey")
                    legendItem(color: Color(red: 0.8, green: 0.15, blue: 0.15), label: "Double+")
                    Button {
                        showGlossary = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 9))
                .frame(maxWidth: .infinity, alignment: .center)
                .popover(isPresented: $showGlossary) {
                    GolfGlossaryView()
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Header Row (hole number + par combined)

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Player")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 90, alignment: .leading)
            ForEach(1...9, id: \.self) { hole in
                holeHeader(hole: hole)
            }
            VStack(spacing: 1) {
                Text("OUT")
                    .font(.system(size: 8, weight: .bold))
                if let hp = resolvedHolePars, hp.count >= 9 {
                    Text("\(hp[0..<9].reduce(0, +))")
                        .font(.system(size: 7))
                }
            }
            .frame(width: 32)
            ForEach(10...18, id: \.self) { hole in
                holeHeader(hole: hole)
            }
            VStack(spacing: 1) {
                Text("IN")
                    .font(.system(size: 8, weight: .bold))
                if let hp = resolvedHolePars, hp.count >= 18 {
                    Text("\(hp[9..<18].reduce(0, +))")
                        .font(.system(size: 7))
                }
            }
            .frame(width: 32)
            VStack(spacing: 1) {
                Text("TOT")
                    .font(.system(size: 8, weight: .bold))
                if let hp = resolvedHolePars, hp.count >= 18 {
                    Text("\(hp.reduce(0, +))")
                        .font(.system(size: 7))
                }
            }
            .frame(width: 32)
            Text("+/-")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 32)
        }
        .foregroundColor(.secondary)
        .padding(.vertical, 4)
    }

    /// Derive hole pars from round detail data as fallback
    private var resolvedHolePars: [Int]? {
        if let hp = holePars, hp.count >= 18 { return hp }
        // Fallback: extract from first player's round details
        for entry in topEntries {
            if let details = entry.roundDetails {
                for round in details {
                    if let holes = round.holeScores, holes.count >= 18 {
                        return holes.sorted(by: { $0.hole < $1.hole }).map(\.par)
                    }
                }
            }
        }
        return nil
    }

    private func holeHeader(hole: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(hole)")
                .font(.system(size: 9, weight: .medium))
            if let hp = resolvedHolePars, hole <= hp.count {
                Text("P\(hp[hole - 1])")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 28)
    }

    // MARK: - Player Row

    private func playerScorecardRow(entry: LeaderboardEntry, isLeader: Bool) -> some View {
        let roundDetail = entry.roundDetails?.first(where: { $0.roundNumber == displayRound })
        let holeScores = roundDetail?.holeScores?.sorted(by: { $0.hole < $1.hole }) ?? []

        return HStack(spacing: 0) {
            // Player name
            HStack(spacing: 3) {
                Text("\(entry.position)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(entry.name.components(separatedBy: " ").last ?? entry.name)
                    .font(.system(size: 9, weight: isLeader ? .bold : .regular))
                    .lineLimit(1)
            }
            .frame(width: 90, alignment: .leading)

            // Front 9
            ForEach(1...9, id: \.self) { hole in
                holeCell(holeNum: hole, holeScores: holeScores)
            }
            // Front 9 total
            let front9 = holeScores.filter { $0.hole >= 1 && $0.hole <= 9 }.compactMap(\.score)
            Text(front9.isEmpty ? "-" : "\(front9.reduce(0, +))")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 32)

            // Back 9
            ForEach(10...18, id: \.self) { hole in
                holeCell(holeNum: hole, holeScores: holeScores)
            }
            // Back 9 total
            let back9 = holeScores.filter { $0.hole >= 10 && $0.hole <= 18 }.compactMap(\.score)
            Text(back9.isEmpty ? "-" : "\(back9.reduce(0, +))")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 32)

            // Round total
            Text(roundDetail?.totalScore.map { "\($0)" } ?? "-")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 32)

            // +/- vs par
            if let total = roundDetail?.totalScore, let par = coursePar {
                let diff = total - par
                Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(diff < 0 ? .green : (diff == 0 ? .secondary : .red))
                    .frame(width: 32)
            } else {
                Text("-")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(width: 32)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func holeCell(holeNum: Int, holeScores: [GolfHoleScore]) -> some View {
        if let hole = holeScores.first(where: { $0.hole == holeNum }), let score = hole.score {
            let diff = score - hole.par
            let isAce = score == 1
            Text("\(score)")
                .font(.system(size: 9, weight: diff != 0 ? .bold : .regular))
                .foregroundColor(isAce ? .black : (diff == 0 ? .primary : .white))
                .frame(width: 28, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isAce ? Color.yellow : holeCellColor(diff: diff))
                )
        } else {
            Text("-")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 20)
        }
    }

    private func holeCellColor(diff: Int) -> Color {
        switch diff {
        case ...(-2): return Color(red: 0, green: 0.5, blue: 0.7)
        case -1:      return Color(red: 0.1, green: 0.65, blue: 0.2)
        case 0:       return Color.gray.opacity(0.15)
        case 1:       return Color(red: 0.85, green: 0.35, blue: 0.15)
        default:      return Color(red: 0.8, green: 0.15, blue: 0.15)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}
