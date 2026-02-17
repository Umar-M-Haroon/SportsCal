//
//  SportsRingView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/16/26.
//

import SwiftUI
import SportsCalModel

/// Apple Activity-ring style view showing favorite teams' combined win rate per sport.
struct SportsRingView: View {
    let games: [Game]
    let favorites: Favorites

    private struct SportRecord {
        let sport: SportType
        var wins: Int = 0
        var losses: Int = 0
        var winRate: Double { Double(wins) / Double(max(wins + losses, 1)) }
    }

    private var sportRecords: [SportRecord] {
        // Filter to favorite team games with records
        let favoriteGames = games.filter { favorites.contains($0) }

        var records: [SportType: SportRecord] = [:]
        for game in favoriteGames {
            guard let sport = game.sportType else { continue }

            // Parse records from the game (format: "24-8" or "24-8-2")
            let homeIsFav = favorites.teams.contains(game.strHomeTeam)
            let awayIsFav = favorites.teams.contains(game.strAwayTeam)

            if homeIsFav, let record = game.homeRecord {
                let parsed = parseRecord(record)
                records[sport, default: SportRecord(sport: sport)].wins += parsed.wins
                records[sport, default: SportRecord(sport: sport)].losses += parsed.losses
            }
            if awayIsFav, let record = game.awayRecord {
                let parsed = parseRecord(record)
                records[sport, default: SportRecord(sport: sport)].wins += parsed.wins
                records[sport, default: SportRecord(sport: sport)].losses += parsed.losses
            }
        }

        return records.values
            .filter { $0.wins + $0.losses > 0 }
            .sorted { $0.sport.displayName < $1.sport.displayName }
    }

    private var combinedRecord: (wins: Int, losses: Int) {
        let records = sportRecords
        return (
            wins: records.reduce(0) { $0 + $1.wins },
            losses: records.reduce(0) { $0 + $1.losses }
        )
    }

    var body: some View {
        let records = sportRecords
        if !records.isEmpty {
            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.pie.fill")
                        .foregroundColor(.accentColor)
                    Text("Your Sports Pulse")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 20) {
                    // Concentric rings
                    ZStack {
                        ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                            let ringSize = CGFloat(70 - index * 14)
                            RingShape(progress: record.winRate)
                                .stroke(
                                    record.sport.color,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .frame(width: ringSize, height: ringSize)
                            // Background ring
                            Circle()
                                .stroke(record.sport.color.opacity(0.15), lineWidth: 8)
                                .frame(width: ringSize, height: ringSize)
                        }

                        // Center record
                        let combined = combinedRecord
                        VStack(spacing: 0) {
                            Text("\(combined.wins)-\(combined.losses)")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                    }
                    .frame(width: 80, height: 80)

                    // Legend
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(records, id: \.sport) { record in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(record.sport.color)
                                    .frame(width: 8, height: 8)
                                Text(record.sport.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(record.wins)-\(record.losses)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(Int(record.winRate * 100))%")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(record.winRate >= 0.5 ? .green : .red)
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

    private func parseRecord(_ record: String) -> (wins: Int, losses: Int) {
        let parts = record.components(separatedBy: "-")
        guard parts.count >= 2,
              let wins = Int(parts[0]),
              let losses = Int(parts[1]) else { return (0, 0) }
        return (wins, losses)
    }
}

// MARK: - Ring Shape

struct RingShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startAngle = Angle(degrees: -90)
        let endAngle = Angle(degrees: -90 + (360 * min(progress, 1.0)))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
