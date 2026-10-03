//
//  F1GapRibbonView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import SportsCalModel

/// Gap ladder: one row per driver, each dot placed proportionally by its time
/// gap to the leader (or fastest lap in practice/qualifying). Lapped and
/// retired drivers sit below the timed field, off-scale.
struct F1GapRibbonView: View {
    let entries: [LeaderboardEntry]
    var sessionName: String? = nil

    @State private var showAll = false

    /// Carries OpenF1's official team colours and driver codes when the server has them.
    var standings: F1Standings? = nil

    /// Fallback when the server hasn't sent colours yet (OpenF1 2026 broadcast values),
    /// keyed by `F1Standings.normalizedTeamName`.
    private static let fallbackColors: [String: String] = [
        "red bull": "4781D7", "ferrari": "ED1131", "mercedes": "00D7B6", "mclaren": "F47600",
        "aston martin": "229971", "alpine": "00A1E8", "williams": "1868DB", "racing bulls": "6C98FF",
        "audi": "F50537", "cadillac": "909090", "haas": "9C9FA2",
        // Older names still in past-season data
        "rb": "6692FF", "visa cash app rb": "6692FF", "alphatauri": "6692FF",
        "kick sauber": "52E252", "sauber": "52E252", "alfa romeo": "52E252",
    ]

    private static let collapsedCount = 10
    private static let rowHeight: CGFloat = 20
    private static let labelWidth: CGFloat = 62
    private static let valueWidth: CGFloat = 64
    private static let dotSize: CGFloat = 10

    // MARK: - Data

    private enum Gap: Equatable {
        case leader
        case time(Double)
        case laps(Int)
        case out
    }

    private struct Row: Identifiable {
        let entry: LeaderboardEntry
        let gap: Gap
        var id: String { entry.name }

        var seconds: Double? {
            switch gap {
            case .leader: 0
            case .time(let s): s
            case .laps, .out: nil
            }
        }
    }

    private var rows: [Row] {
        let sorted = entries.sorted { lhs, rhs in
            // Unclassified (position 0) sorts after the field.
            (lhs.position == 0 ? Int.max : lhs.position) < (rhs.position == 0 ? Int.max : rhs.position)
        }
        guard let leader = sorted.first else { return [] }
        // Sprint qualifying sends absolute lap times with a "+" ("+1:11.608" behind a
        // "1:11.567" pole). A real gap is never half a lap, so anything that large is a
        // time: convert it to a gap from the leader's.
        let leaderTime: Double? = leader.gap.flatMap {
            if case .time(let t) = Self.parseGap($0) { return t } else { return nil }
        }
        func normalized(_ gap: Gap) -> Gap {
            guard case .time(let value) = gap, let leaderTime, leaderTime > 0, value >= leaderTime * 0.5 else { return gap }
            return .time(max(value - leaderTime, 0))
        }
        var timed: [Row] = []
        var trailing: [Row] = []
        for entry in sorted {
            if entry == leader {
                timed.append(Row(entry: entry, gap: .leader))
                continue
            }
            guard let raw = entry.gap else { continue }
            let gap = normalized(Self.parseGap(raw))
            switch gap {
            case .time: timed.append(Row(entry: entry, gap: gap))
            default: trailing.append(Row(entry: entry, gap: gap))
            }
        }
        // Keep the ladder monotonic even if a feed reorders mid-update.
        timed.sort { ($0.seconds ?? 0) < ($1.seconds ?? 0) }
        return timed + trailing
    }

    private var isTimedLapSession: Bool {
        guard let name = sessionName?.lowercased() else { return false }
        return name.contains("practice") || name.contains("qualifying")
    }

    // MARK: - Body

    var body: some View {
        let rows = rows
        let timedSeconds = rows.compactMap(\.seconds)
        if timedSeconds.count >= 3 {
            let collapsible = rows.count > Self.collapsedCount + 2
            let visible = collapsible && !showAll ? Array(rows.prefix(Self.collapsedCount)) : rows
            // Fit the scale to what's on screen so a tail-ender doesn't crush the top 10.
            let scale = Scale(maxValue: visible.compactMap(\.seconds).max() ?? 0)

            VStack(alignment: .leading, spacing: 12) {
                header(timedSeconds: timedSeconds)

                VStack(spacing: 0) {
                    ForEach(visible) { row in
                        rowView(row, scale: scale)
                    }
                    axis(scale: scale)
                        .padding(.top, 4)
                }
                .animation(.smooth, value: entries)

                if collapsible {
                    Button {
                        withAnimation(.smooth) { showAll.toggle() }
                    } label: {
                        Label(showAll ? "Show top \(Self.collapsedCount)" : "Show all \(rows.count)",
                              systemImage: showAll ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func header(timedSeconds: [Double]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gap Chart")
                    .font(.headline)
                Text(isTimedLapSession ? "Gap to fastest lap" : "Gap to leader")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if timedSeconds.count >= Self.collapsedCount {
                // timedSeconds is sorted ascending, so index 9 is P10's gap.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.formatSpread(timedSeconds[Self.collapsedCount - 1]))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text("covers top \(Self.collapsedCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rowView(_ row: Row, scale: Scale) -> some View {
        let color = colorForConstructor(row.entry.constructor)
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 14)
                Text(row.entry.position > 0 ? "\(row.entry.position)" : "–")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
                Text(shortName(row.entry.name))
                    .font(.caption.weight(row.gap == .leader ? .bold : .semibold))
            }
            .frame(width: Self.labelWidth, alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                let midY = geo.size.height / 2
                ZStack(alignment: .topLeading) {
                    ForEach(scale.ticks, id: \.self) { tick in
                        Rectangle()
                            .fill(Color.secondary.opacity(tick == 0 ? 0.35 : 0.15))
                            .frame(width: 0.5, height: geo.size.height)
                            .offset(x: scale.x(tick, width: width, inset: Self.dotSize / 2))
                    }

                    switch row.gap {
                    case .leader, .time:
                        let x = scale.x(row.seconds ?? 0, width: width, inset: Self.dotSize / 2)
                        let start = scale.x(0, width: width, inset: Self.dotSize / 2)
                        Capsule()
                            .fill(color.opacity(0.3))
                            .frame(width: max(x - start, 0), height: 3)
                            .offset(x: start, y: midY - 1.5)
                        Circle()
                            .fill(color)
                            .overlay(Circle().stroke(Color.secondaryGroupedBackground, lineWidth: 1.5))
                            .frame(width: Self.dotSize, height: Self.dotSize)
                            .offset(x: x - Self.dotSize / 2, y: midY - Self.dotSize / 2)
                    case .laps:
                        // Off the scale: hollow marker pinned to the far edge.
                        Circle()
                            .stroke(color, lineWidth: 1.5)
                            .frame(width: Self.dotSize - 2, height: Self.dotSize - 2)
                            .offset(x: width - Self.dotSize + 1, y: midY - (Self.dotSize - 2) / 2)
                    case .out:
                        EmptyView()
                    }
                }
            }

            Text(gapText(row))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(row.gap == .leader ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(row))
    }

    private func axis(scale: Scale) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.labelWidth, height: 1)
            GeometryReader { geo in
                ForEach(scale.ticks, id: \.self) { tick in
                    Text(scale.label(tick))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: scale.x(tick, width: geo.size.width, inset: Self.dotSize / 2),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 12)
            Color.clear.frame(width: Self.valueWidth, height: 1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Scale

    /// Linear seconds scale rounded up to a "nice" step so gridlines land on
    /// readable values (0.25s in tight practice sessions, 5s/10s in races).
    private struct Scale {
        let step: Double
        let upper: Double

        init(maxValue: Double) {
            let steps: [Double] = [0.05, 0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10, 15, 20, 30, 60, 120, 300, 600]
            let target = max(maxValue, 0.001) / 4
            step = steps.first { $0 >= target } ?? 1200
            upper = max(step, (maxValue / step).rounded(.up) * step)
        }

        var ticks: [Double] {
            stride(from: 0, through: upper + step / 2, by: step).map { ($0 / step).rounded() * step }
        }

        func x(_ value: Double, width: CGFloat, inset: CGFloat) -> CGFloat {
            let usable = max(width - inset * 2, 0)
            return inset + CGFloat(min(max(value / upper, 0), 1)) * usable
        }

        func label(_ value: Double) -> String {
            if value == 0 { return "0" }
            if step >= 60, value.truncatingRemainder(dividingBy: 60) == 0 {
                return "+\(Int(value / 60))m"
            }
            let decimals = step == step.rounded() ? 0 : ((step * 10) == (step * 10).rounded() ? 1 : 2)
            return "+" + String(format: "%.\(decimals)f", value) + "s"
        }
    }

    // MARK: - Helpers

    static func colorForConstructorName(_ constructor: String, standings: F1Standings? = nil) -> Color {
        let hex = standings?.teamColorHex(for: constructor)
            ?? fallbackColors[F1Standings.normalizedTeamName(constructor)]
        return Color(hex: hex) ?? .gray
    }

    private func colorForConstructor(_ constructor: String?) -> Color {
        guard let constructor else { return .gray }
        return Self.colorForConstructorName(constructor, standings: standings)
    }

    private func shortName(_ fullName: String) -> String {
        if let code = standings?.driverCode(for: fullName) { return code }
        let parts = fullName.components(separatedBy: " ")
        if parts.count >= 2, let last = parts.last {
            return String(last.prefix(3)).uppercased()
        }
        return String(fullName.prefix(3)).uppercased()
    }

    private func gapText(_ row: Row) -> String {
        switch row.gap {
        // P1's feed value is the total race time / fastest lap.
        case .leader: row.entry.gap ?? "Leader"
        case .time(let seconds):
            // Show the computed gap when the feed sent an absolute time.
            Self.parseGap(row.entry.gap ?? "") == .time(seconds) ? (row.entry.gap ?? "") : String(format: "+%.3f", seconds)
        case .laps: row.entry.gap ?? ""
        case .out: (row.entry.gap ?? "").uppercased() == "RETIRED" ? "DNF" : (row.entry.gap ?? "")
        }
    }

    private func accessibilityLabel(_ row: Row) -> String {
        var parts = ["Position \(row.entry.position)", row.entry.name]
        if let constructor = row.entry.constructor { parts.append(constructor) }
        switch row.gap {
        case .leader: parts.append(isTimedLapSession ? "fastest" : "leader")
        case .time(let s): parts.append(String(format: "%.3f seconds behind", s))
        case .laps(let n): parts.append("\(n) lap\(n == 1 ? "" : "s") down")
        case .out: parts.append(row.entry.gap ?? "not classified")
        }
        return parts.joined(separator: ", ")
    }

    private static func formatSpread(_ seconds: Double) -> String {
        seconds < 60 ? String(format: "%.3fs", seconds) : formatClock(seconds)
    }

    private static func formatClock(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return String(format: "%d:%06.3f", minutes, seconds - Double(minutes * 60))
    }

    /// Feed formats: "+0.099", "+1:02.345", "+1 Lap", "+2 Laps", "DNF", "DNS", "Retired".
    private static func parseGap(_ raw: String) -> Gap {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
        if cleaned.lowercased().contains("lap") {
            let digits = cleaned.filter(\.isNumber)
            return .laps(Int(digits) ?? 1)
        }
        let numeric = cleaned.hasPrefix("+") ? String(cleaned.dropFirst()) : cleaned
        if let seconds = parseClock(numeric) {
            return .time(seconds)
        }
        return .out
    }

    /// Parses "ss.sss", "m:ss.sss" or "h:mm:ss.sss" into seconds.
    private static func parseClock(_ string: String) -> Double? {
        let components = string.split(separator: ":")
        guard !components.isEmpty, components.count <= 3 else { return nil }
        var total = 0.0
        for component in components {
            guard let value = Double(component), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

#Preview("Practice") {
    let drivers: [(String, String, String)] = [
        ("Charles Leclerc", "Ferrari", "1:37.528"), ("Isack Hadjar", "Red Bull Racing", "+0.099"),
        ("Lando Norris", "McLaren", "+0.137"), ("Max Verstappen", "Red Bull Racing", "+0.257"),
        ("Lewis Hamilton", "Ferrari", "+0.305"), ("Oscar Piastri", "McLaren", "+0.371"),
        ("George Russell", "Mercedes", "+0.492"), ("Kimi Antonelli", "Mercedes", "+0.532"),
        ("Liam Lawson", "Racing Bulls", "+0.968"), ("Pierre Gasly", "Alpine", "+1.060"),
        ("Arvid Lindblad", "Racing Bulls", "+1.352"), ("Gabriel Bortoleto", "Audi", "+1.523"),
        ("Nico Hülkenberg", "Audi", "+1.581"), ("Esteban Ocon", "Haas", "+1.833"),
        ("Fernando Alonso", "Aston Martin", "+1.950"), ("Oliver Bearman", "Haas", "+2.178"),
        ("Carlos Sainz", "Williams", "+2.402"), ("Lance Stroll", "Aston Martin", "+2.622"),
        ("Valtteri Bottas", "Cadillac", "+2.658"), ("Alexander Albon", "Williams", "+2.693"),
        ("Sergio Pérez", "Cadillac", "+3.410"), ("Franco Colapinto", "Alpine", "+5.863"),
    ]
    ScrollView {
        F1GapRibbonView(
            entries: drivers.enumerated().map { i, d in
                LeaderboardEntry(name: d.0, score: "P\(i + 1)", position: i + 1, constructor: d.1, gap: d.2)
            },
            sessionName: "Free Practice 2"
        )
        .padding()
    }
}

#Preview("Race") {
    let drivers: [(String, String, String)] = [
        ("Max Verstappen", "Red Bull Racing", "1:31:44.742"), ("Lando Norris", "McLaren", "+2.341"),
        ("Charles Leclerc", "Ferrari", "+2.902"), ("Oscar Piastri", "McLaren", "+14.880"),
        ("George Russell", "Mercedes", "+31.204"), ("Lewis Hamilton", "Ferrari", "+48.115"),
        ("Fernando Alonso", "Aston Martin", "+1:04.552"), ("Carlos Sainz", "Williams", "+1 Lap"),
        ("Pierre Gasly", "Alpine", "+2 Laps"), ("Valtteri Bottas", "Cadillac", "DNF"),
    ]
    ScrollView {
        F1GapRibbonView(
            entries: drivers.enumerated().map { i, d in
                LeaderboardEntry(name: d.0, score: "P\(i + 1)", position: i + 1, constructor: d.1, gap: d.2)
            },
            sessionName: "Race"
        )
        .padding()
    }
}

#Preview("Sprint qualifying (absolute times)") {
    let times = ["1:11.567", "+1:11.608", "+1:11.622", "+1:11.666", "+1:12.010"]
    let names = ["Lando Norris", "Oscar Piastri", "Max Verstappen", "George Russell", "Charles Leclerc"]
    ScrollView {
        F1GapRibbonView(
            entries: zip(names, times).enumerated().map { i, d in
                LeaderboardEntry(name: d.0, score: "P\(i + 1)", position: i + 1, constructor: "McLaren", gap: d.1)
            },
            sessionName: "Sprint Qualifying"
        )
        .padding()
    }
}
