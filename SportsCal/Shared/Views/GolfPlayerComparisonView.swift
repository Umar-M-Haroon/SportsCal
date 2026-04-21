//
//  GolfPlayerComparisonView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/11/26.
//

import SwiftUI
import SportsCalModel

/// Side-by-side comparison of two golfers' round-by-round performance.
struct GolfPlayerComparisonView: View {
    let playerA: LeaderboardEntry
    let playerB: LeaderboardEntry
    let coursePar: Int?

    @Environment(\.dismiss) private var dismiss

    private var scoresA: [Int] { playerA.rounds.compactMap { Int($0) } }
    private var scoresB: [Int] { playerB.rounds.compactMap { Int($0) } }
    private var maxRounds: Int { max(playerA.rounds.count, playerB.rounds.count) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    roundByRoundSection
                    sparklinesSection
                    summarySection
                }
                .padding()
            }
            .navigationTitle("Compare Players")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 0) {
            playerHeader(entry: playerA)
            Divider().frame(height: 60)
            playerHeader(entry: playerB)
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func playerHeader(entry: LeaderboardEntry) -> some View {
        VStack(spacing: 6) {
            HeadshotView(url: entry.headshot, size: 40)
            Text(entry.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            HStack(spacing: 4) {
                Text("#\(entry.position)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(entry.score)
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Round by Round

    private var roundByRoundSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 36)
                Text(playerA.name.components(separatedBy: " ").last ?? playerA.name)
                    .frame(maxWidth: .infinity)
                Text(playerB.name.components(separatedBy: " ").last ?? playerB.name)
                    .frame(maxWidth: .infinity)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.bottom, 4)

            ForEach(0..<maxRounds, id: \.self) { i in
                let scoreA = i < scoresA.count ? scoresA[i] : nil
                let scoreB = i < scoresB.count ? scoresB[i] : nil

                HStack(spacing: 0) {
                    Text("R\(i + 1)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 36)

                    roundCell(score: scoreA, isWinner: isRoundWinner(a: scoreA, b: scoreB))
                        .frame(maxWidth: .infinity)

                    roundCell(score: scoreB, isWinner: isRoundWinner(a: scoreB, b: scoreA))
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 3)

                if i < maxRounds - 1 {
                    Divider().padding(.horizontal, 36)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func roundCell(score: Int?, isWinner: Bool) -> some View {
        if let score {
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.subheadline)
                    .fontWeight(isWinner ? .bold : .regular)
                    .foregroundColor(isWinner ? .primary : .secondary)
                if let par = coursePar {
                    let diff = score - par
                    Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                        .font(.caption2)
                        .foregroundColor(diff < 0 ? .green : (diff == 0 ? .secondary : .red))
                }
            }
        } else {
            Text("-")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func isRoundWinner(a: Int?, b: Int?) -> Bool {
        guard let a, let b else { return false }
        return a < b // lower is better in golf
    }

    // MARK: - Sparklines

    private var sparklinesSection: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(playerA.name.components(separatedBy: " ").last ?? "A")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                GolfScoreSparkline(rounds: playerA.rounds, coursePar: coursePar)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text(playerB.name.components(separatedBy: " ").last ?? "B")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                GolfScoreSparkline(rounds: playerB.rounds, coursePar: coursePar)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(spacing: 8) {
            Text("Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                Text("")
                    .frame(width: 80, alignment: .leading)
                Text(playerA.name.components(separatedBy: " ").last ?? "A")
                    .frame(maxWidth: .infinity)
                Text(playerB.name.components(separatedBy: " ").last ?? "B")
                    .frame(maxWidth: .infinity)
            }
            .font(.caption2.bold())
            .foregroundColor(.secondary)

            summaryRow(label: "Total", valueA: totalString(scoresA), valueB: totalString(scoresB))
            summaryRow(label: "Best", valueA: bestString(scoresA), valueB: bestString(scoresB))
            summaryRow(label: "Average", valueA: avgString(scoresA), valueB: avgString(scoresB))

            if let par = coursePar {
                let diffA = scoresA.reduce(0, +) - (par * scoresA.count)
                let diffB = scoresB.reduce(0, +) - (par * scoresB.count)
                summaryRow(
                    label: "vs Par",
                    valueA: diffA == 0 ? "E" : (diffA > 0 ? "+\(diffA)" : "\(diffA)"),
                    valueB: diffB == 0 ? "E" : (diffB > 0 ? "+\(diffB)" : "\(diffB)")
                )
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func summaryRow(label: String, valueA: String, valueB: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(valueA)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
            Text(valueB)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 2)
    }

    private func totalString(_ scores: [Int]) -> String {
        guard !scores.isEmpty else { return "-" }
        return "\(scores.reduce(0, +))"
    }

    private func bestString(_ scores: [Int]) -> String {
        guard let best = scores.min(), let idx = scores.firstIndex(of: best) else { return "-" }
        if let par = coursePar {
            let diff = best - par
            let diffStr = diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
            return "R\(idx + 1): \(best) (\(diffStr))"
        }
        return "R\(idx + 1): \(best)"
    }

    private func avgString(_ scores: [Int]) -> String {
        guard !scores.isEmpty else { return "-" }
        let avg = Double(scores.reduce(0, +)) / Double(scores.count)
        return String(format: "%.1f", avg)
    }
}
