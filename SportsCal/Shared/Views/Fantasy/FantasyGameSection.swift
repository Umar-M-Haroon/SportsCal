//
//  FantasyGameSection.swift
//  SportsCal
//
//  Game detail's fantasy card for an NFL game: the game's top scorers and its
//  stinkers under the user's scoring, from `/fantasy/event/:eventID` (loaded with the
//  box score by `GameDetailSectionsModel`). Free.
//

import SwiftUI
import SportsCalModel

struct FantasyGameSection: View {
    let lines: [FantasyPlayerLine]?
    let scoring: FantasyScoring

    @State private var detail: FantasyEvaluation?

    var body: some View {
        if let lines, !lines.isEmpty {
            let evaluations = lines.map { FantasyEvaluation(line: $0, scoring: scoring) }
            let studs = FantasySlate.studs(evaluations, limit: 3)
            let stinkers = FantasySlate.stinkers(evaluations, limit: 2)
            if !studs.isEmpty || !stinkers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Fantasy").font(.headline)
                        Spacer()
                        Text(scoring.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.app(.nfl))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appTint(.nfl), in: Capsule())
                    }
                    if !studs.isEmpty {
                        group("Studs", studs)
                    }
                    if !stinkers.isEmpty {
                        group("Stinkers", stinkers)
                    }
                }
                .padding()
                .background(Color.secondaryGroupedBackground)
                .cornerRadius(12)
                .sheet(item: $detail) { evaluation in
                    FantasyBreakdownSheet(evaluation: evaluation, scoring: scoring)
                }
            }
        }
    }

    private func group(_ title: String, _ evaluations: [FantasyEvaluation]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(evaluations) { evaluation in
                Button {
                    detail = evaluation
                } label: {
                    FantasyCompactRow(evaluation: evaluation)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Athlete ID → points, for the box score's FPTS column. D/ST lines have no box row.
    static func pointsByAthlete(_ lines: [FantasyPlayerLine]?, scoring: FantasyScoring) -> [String: Double]? {
        guard let lines, !lines.isEmpty else { return nil }
        var out: [String: Double] = [:]
        for line in lines where !line.isDST {
            out[line.athleteID] = scoring.points(line.stats)
        }
        return out
    }
}

/// One line in the game card: headshot, name, position and stat line, points, pace.
struct FantasyCompactRow: View {
    let evaluation: FantasyEvaluation

    var body: some View {
        let line = evaluation.line
        HStack(spacing: 10) {
            FantasyHeadshot(line: line, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(line.shortName ?? line.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text([line.isDST ? nil : line.position, line.teamAbbreviation].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                let summary = line.statSummary
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 6)
            if let delta = evaluation.delta {
                FantasyDeltaPill(delta: delta)
            }
            Text(FantasyScoring.format(evaluation.points))
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.name), \(FantasyScoring.format(evaluation.points)) fantasy points")
        .accessibilityHint("Shows the scoring breakdown")
    }
}

#Preview("Game fantasy card") {
    ScrollView {
        FantasyGameSection(lines: FantasySlate.preview.players, scoring: .nflHalfPPR)
            .padding()
    }
    .background(Color.groupedBackgroundPreview)
}

private extension Color {
    static var groupedBackgroundPreview: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
