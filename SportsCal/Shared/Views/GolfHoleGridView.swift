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
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22)
                    ForEach(holes, id: \.hole) { hole in
                        Text("\(hole.hole)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    Text("")
                        .frame(width: 24)
                }

                // Par row
                HStack(spacing: 2) {
                    Text("Par")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 22)
                    ForEach(holes, id: \.hole) { hole in
                        Text("\(hole.par)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    let parTotal = holes.map(\.par).reduce(0, +)
                    Text("\(parTotal)")
                        .font(.caption2.weight(.bold))
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
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(holeColor(score: score, par: hole.par))
                                )
                                .overlay(GolfScoreMark(diff: score - hole.par).foregroundStyle(.white.opacity(0.9)).padding(1))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(GolfScoreStyle.holeLabel(hole: hole.hole, score: score, par: hole.par))
                        } else {
                            Text("-")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        }
                    }
                    let scoreTotal = holes.compactMap(\.score).reduce(0, +)
                    if holes.contains(where: { $0.score != nil }) {
                        Text("\(scoreTotal)")
                            .font(.caption2.weight(.bold))
                            .frame(width: 24)
                    } else {
                        Text("-")
                            .font(.caption2)
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

/// The scorecard convention, so a hole reads without colour: circled under par (twice for
/// an eagle or better), boxed over par (twice for a double bogey or worse).
struct GolfScoreMark: View {
    let diff: Int

    var body: some View {
        if diff <= -2 {
            ZStack {
                Circle().stroke(lineWidth: 1)
                Circle().inset(by: 2.5).stroke(lineWidth: 1)
            }
        } else if diff == -1 {
            Circle().stroke(lineWidth: 1)
        } else if diff == 1 {
            Rectangle().stroke(lineWidth: 1)
        } else if diff >= 2 {
            ZStack {
                Rectangle().stroke(lineWidth: 1)
                Rectangle().inset(by: 2.5).stroke(lineWidth: 1)
            }
        }
    }
}

/// Shared golf score presentation for the app's golf views (and the same rule as the
/// widgets'): under par is green, over par muted.
enum GolfScoreStyle {
    static func color(toPar text: String?) -> Color {
        guard let value = GolfScore.toPar(text) else { return .secondary }
        if value < 0 { return .green }
        return value == 0 ? .primary : .secondary
    }

    static func holeName(score: Int, par: Int) -> String {
        if score == 1 { return "hole in one" }
        switch score - par {
        case ...(-3): return "albatross"
        case -2: return "eagle"
        case -1: return "birdie"
        case 0: return "par"
        case 1: return "bogey"
        case 2: return "double bogey"
        default: return "\(score - par) over par"
        }
    }

    /// "Hole 4, birdie, 3".
    static func holeLabel(hole: Int, score: Int, par: Int) -> String {
        "Hole \(hole), \(holeName(score: score, par: par)), \(score)"
    }

    /// "Tied 3rd" from "T3"; the label itself otherwise.
    static func spokenPosition(_ label: String) -> String {
        label.hasPrefix("T") ? "tied \(label.dropFirst())" : label
    }

    /// A tee time in the viewer's time zone ("1:49 PM", or "Sat 1:49 PM" when it isn't today).
    static func teeTimeText(_ entry: LeaderboardEntry, now: Date = Date()) -> String? {
        guard let date = entry.teeTimeStart else { return entry.teeTime }
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
