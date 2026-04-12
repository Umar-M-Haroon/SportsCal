//
//  GolfHoleGridView.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/11/26.
//

import SwiftUI
import SportsCalModel

/// Displays a grid of 18 hole scores, split into front 9 and back 9.
/// Each cell is colored by score relative to par: green for birdie, red for bogey, etc.
struct GolfHoleGridView: View {
    let holeScores: [GolfHoleScore]

    private var front9: [GolfHoleScore] {
        holeScores.filter { $0.hole >= 1 && $0.hole <= 9 }.sorted { $0.hole < $1.hole }
    }

    private var back9: [GolfHoleScore] {
        holeScores.filter { $0.hole >= 10 && $0.hole <= 18 }.sorted { $0.hole < $1.hole }
    }

    var body: some View {
        VStack(spacing: 4) {
            // Front 9
            nineHoleRow(holes: front9, label: "OUT")
            // Back 9
            nineHoleRow(holes: back9, label: "IN")
        }
    }

    @ViewBuilder
    private func nineHoleRow(holes: [GolfHoleScore], label: String) -> some View {
        if !holes.isEmpty {
            VStack(spacing: 2) {
                // Hole numbers
                HStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22)
                    ForEach(holes, id: \.hole) { hole in
                        Text("\(hole.hole)")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    Text("")
                        .frame(width: 24)
                }

                // Par row
                HStack(spacing: 2) {
                    Text("Par")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                        .frame(width: 22)
                    ForEach(holes, id: \.hole) { hole in
                        Text("\(hole.par)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    let parTotal = holes.map(\.par).reduce(0, +)
                    Text("\(parTotal)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                }

                // Score row
                HStack(spacing: 2) {
                    Text("")
                        .frame(width: 22)
                    ForEach(holes, id: \.hole) { hole in
                        if let score = hole.score {
                            Text("\(score)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(holeColor(score: score, par: hole.par))
                                )
                        } else {
                            Text("-")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        }
                    }
                    let scoreTotal = holes.compactMap(\.score).reduce(0, +)
                    if holes.contains(where: { $0.score != nil }) {
                        Text("\(scoreTotal)")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 24)
                    } else {
                        Text("-")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                    }
                }
            }
        }
    }

    private func holeColor(score: Int, par: Int) -> Color {
        if score == 1 { return .yellow }                                    // hole-in-one (gold)
        let diff = score - par
        switch diff {
        case ...(-2): return Color(red: 0.0, green: 0.5, blue: 0.7)   // eagle+ (dark teal)
        case -1:      return Color(red: 0.1, green: 0.65, blue: 0.2)  // birdie (green)
        case 0:       return Color.gray.opacity(0.4)                    // par
        case 1:       return Color(red: 0.85, green: 0.35, blue: 0.15) // bogey (dark orange)
        default:      return Color(red: 0.8, green: 0.15, blue: 0.15)  // double+ (red)
        }
    }
}
