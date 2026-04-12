//
//  GolfScoreSparkline.swift
//  SportsCal
//
//  Created by Umar Haroon on 4/11/26.
//

import SwiftUI

/// A small line chart showing cumulative score-to-par progression across rounds.
/// When coursePar is nil, shows raw score trend instead.
struct GolfScoreSparkline: View {
    let rounds: [String]
    let coursePar: Int?

    private var scores: [Int] {
        rounds.compactMap { Int($0) }
    }

    /// Cumulative par-relative scores: e.g. [68, 71, 66, 70] with par 72 → [-4, -5, -11, -13]
    private var cumulativeValues: [Double] {
        guard !scores.isEmpty else { return [] }
        if let par = coursePar {
            var cumulative: [Double] = []
            var total = 0
            for score in scores {
                total += (score - par)
                cumulative.append(Double(total))
            }
            return cumulative
        } else {
            return scores.map { Double($0) }
        }
    }

    /// Whether the overall trend is improving (going down = good in golf)
    private var isImproving: Bool {
        guard cumulativeValues.count >= 2 else { return true }
        return (cumulativeValues.last ?? 0) <= (cumulativeValues.first ?? 0)
    }

    var body: some View {
        if scores.count >= 2 {
            let values = cumulativeValues
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 0
            let range = max(maxVal - minVal, 1)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let insetH = h - 20 // leave room for labels
                let stepX = w / CGFloat(max(values.count - 1, 1))

                ZStack(alignment: .topLeading) {
                    // Zero line (even par) when using par-relative
                    if coursePar != nil, minVal < 0 || maxVal > 0 {
                        let zeroY = yPosition(value: 0, minVal: minVal, range: range, height: insetH)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: zeroY))
                            path.addLine(to: CGPoint(x: w, y: zeroY))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundColor(.secondary.opacity(0.4))

                        Text("E")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                            .position(x: 8, y: zeroY - 8)
                    }

                    // Line path
                    Path { path in
                        for (i, val) in values.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = yPosition(value: val, minVal: minVal, range: range, height: insetH)
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(isImproving ? Color.green : Color.red, lineWidth: 2)

                    // Data points and labels
                    ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                        let x = CGFloat(i) * stepX
                        let y = yPosition(value: val, minVal: minVal, range: range, height: insetH)

                        Circle()
                            .fill(isImproving ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)

                        Text(formatValue(val))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .position(x: x, y: y + 12)
                    }
                }
            }
            .frame(height: 50)
        }
    }

    private func yPosition(value: Double, minVal: Double, range: Double, height: CGFloat) -> CGFloat {
        // Invert Y: lower values (better in golf) should be higher on screen
        let normalized = (value - minVal) / range
        return 4 + normalized * height
    }

    private func formatValue(_ val: Double) -> String {
        let intVal = Int(val)
        if coursePar != nil {
            return intVal == 0 ? "E" : (intVal > 0 ? "+\(intVal)" : "\(intVal)")
        } else {
            return "\(intVal)"
        }
    }
}
