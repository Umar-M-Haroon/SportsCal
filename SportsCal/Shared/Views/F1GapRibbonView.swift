//
//  F1GapRibbonView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import SportsCalModel

/// Positions drivers proportionally by time gap rather than evenly ranked.
struct F1GapRibbonView: View {
    let entries: [LeaderboardEntry]

    /// Static constructor color lookup for F1 teams
    private static let constructorColors: [String: Color] = [
        "Red Bull Racing": Color(hex: "3671C6"),
        "Ferrari": Color(hex: "E8002D"),
        "Mercedes": Color(hex: "27F4D2"),
        "McLaren": Color(hex: "FF8000"),
        "Aston Martin": Color(hex: "229971"),
        "Alpine": Color(hex: "FF87BC"),
        "Williams": Color(hex: "64C4FF"),
        "RB": Color(hex: "6692FF"),
        "Kick Sauber": Color(hex: "52E252"),
        "Haas F1 Team": Color(hex: "B6BABD"),
        // Alternate names
        "Red Bull": Color(hex: "3671C6"),
        "AlphaTauri": Color(hex: "6692FF"),
        "Alfa Romeo": Color(hex: "52E252"),
        "Sauber": Color(hex: "52E252"),
        "Haas": Color(hex: "B6BABD"),
    ]

    private struct DriverGap {
        let name: String
        let position: Int
        let gapSeconds: Double
        let constructor: String?
        let headshot: String?
    }

    private var driverGaps: [DriverGap] {
        entries.compactMap { entry in
            let gap: Double
            if entry.position == 1 {
                gap = 0
            } else if let gapStr = entry.gap {
                gap = parseGap(gapStr)
            } else {
                return nil
            }
            return DriverGap(
                name: entry.name,
                position: entry.position,
                gapSeconds: gap,
                constructor: entry.constructor,
                headshot: entry.headshot
            )
        }
    }

    private var maxGap: Double {
        driverGaps.map(\.gapSeconds).max() ?? 1
    }

    var body: some View {
        let gaps = driverGaps
        if gaps.count >= 3 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gap Chart")
                    .font(.headline)

                Text("Positions spaced by time gap from leader")
                    .font(.caption)
                    .foregroundColor(.secondary)

                let displayMax = maxGap
                GeometryReader { geo in
                    let availableWidth = geo.size.width - 50 // leave room for labels
                    ZStack(alignment: .leading) {
                        // Track line
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 2)
                            .offset(y: 0)

                        ForEach(Array(gaps.enumerated()), id: \.offset) { _, driver in
                            let fraction = displayMax > 0 ? driver.gapSeconds / displayMax : 0
                            let xPos = fraction * availableWidth

                            VStack(spacing: 2) {
                                Text("P\(driver.position)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule()
                                            .fill(colorForConstructor(driver.constructor))
                                    )

                                // Driver name (short)
                                Text(shortName(driver.name))
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)

                                // Gap label
                                if driver.position > 1 {
                                    Text("+\(String(format: "%.1f", driver.gapSeconds))s")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 44)
                            .offset(x: xPos)
                        }
                    }
                }
                .frame(height: 60)

                // Constructor legend (compact)
                let uniqueConstructors = Array(Set(gaps.compactMap(\.constructor))).sorted()
                if !uniqueConstructors.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 4) {
                        ForEach(uniqueConstructors, id: \.self) { constructor in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForConstructor(constructor))
                                    .frame(width: 6, height: 6)
                                Text(constructor)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func colorForConstructor(_ constructor: String?) -> Color {
        guard let constructor else { return .gray }
        return Self.constructorColors[constructor] ?? .gray
    }

    private func shortName(_ fullName: String) -> String {
        let parts = fullName.components(separatedBy: " ")
        if parts.count >= 2 {
            return String(parts.last!.prefix(3)).uppercased()
        }
        return String(fullName.prefix(3)).uppercased()
    }

    private func parseGap(_ gap: String) -> Double {
        // Formats: "+1.234", "+1 Lap", "+2 Laps", "DNF"
        let cleaned = gap.trimmingCharacters(in: .whitespaces)
        if cleaned.lowercased().contains("lap") {
            // Treat lapped drivers as having a large gap
            let parts = cleaned.components(separatedBy: " ")
            if let laps = Double(parts.first?.replacingOccurrences(of: "+", with: "") ?? "") {
                return laps * 90 // ~90 seconds per lap approximation
            }
            return 90
        }
        if cleaned.lowercased() == "dnf" || cleaned.lowercased() == "dns" {
            return maxGap + 10 // push to end
        }
        let numericStr = cleaned.replacingOccurrences(of: "+", with: "")
        return Double(numericStr) ?? 0
    }
}
