//
//  WorldCupBoxScoreView.swift
//  SportsCal
//
//  Per-match box score for a World Cup fixture, shown inside the game detail
//  stack: a team stat comparison, the goal/card/substitution timeline, and the
//  two lineups with per-player stat lines. Data is fetched on demand from
//  `/worldcup/boxscore/:eventID` (see GameDetailSectionsModel.loadWorldCupBoxScore).
//
//  Layout follows the rest of GameDetailView: away on the left, home on the right.
//

import SwiftUI
import SportsCalModel

struct WorldCupBoxScoreView: View {
    let boxScore: WorldCupBoxScore
    let game: Game

    private var awayColor: Color { Color(hex: game.awayTeamColor ?? "") ?? .accentColor }
    private var homeColor: Color { Color(hex: game.homeTeamColor ?? "") ?? .secondary }

    var body: some View {
        VStack(spacing: 24) {
            if !boxScore.events.isEmpty {
                eventsCard
            }
            if !boxScore.teamStats.isEmpty {
                teamStatsCard
            }
            if !boxScore.home.players.isEmpty || !boxScore.away.players.isEmpty {
                lineupsCard
            }
        }
    }

    // MARK: - Match events timeline

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Match Events")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(boxScore.events) { event in
                    eventRow(event)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func eventRow(_ event: WorldCupMatchEvent) -> some View {
        let isHome = event.side == .home
        HStack(alignment: .top, spacing: 8) {
            // Away column (left)
            Group {
                if !isHome { eventDetail(event, alignment: .leading) }
                else { Color.clear.frame(height: 1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Minute + icon spine
            VStack(spacing: 2) {
                Image(systemName: eventIcon(event.type))
                    .font(.caption)
                    .foregroundStyle(eventTint(event.type, isHome: isHome))
                if let clock = event.clock {
                    Text(clock)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 44)

            // Home column (right)
            Group {
                if isHome { eventDetail(event, alignment: .trailing) }
                else { Color.clear.frame(height: 1) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func eventDetail(_ event: WorldCupMatchEvent, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(eventPrimaryText(event))
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .lineLimit(2)
            if let secondary = eventSecondaryText(event) {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func eventPrimaryText(_ event: WorldCupMatchEvent) -> String {
        switch event.type {
        case .goal, .penaltyGoal, .ownGoal:
            let scorer = event.playerNames.first ?? event.shortText ?? "Goal"
            return event.type == .ownGoal ? "\(scorer) (OG)" : scorer
        case .substitution:
            if let inName = event.playerNames.first { return inName }
            return event.shortText ?? "Substitution"
        case .yellowCard, .redCard:
            return event.playerNames.first ?? event.shortText ?? event.typeText
        default:
            return event.shortText ?? event.typeText
        }
    }

    private func eventSecondaryText(_ event: WorldCupMatchEvent) -> String? {
        switch event.type {
        case .goal, .penaltyGoal:
            if event.playerNames.count > 1 { return "assist: \(event.playerNames[1])" }
            return event.type == .penaltyGoal ? "Penalty" : nil
        case .substitution:
            if event.playerNames.count > 1 { return "out: \(event.playerNames[1])" }
            // Participants are often absent on subs — surface ESPN's narration instead.
            if event.playerNames.isEmpty, let text = event.text {
                return text.replacingOccurrences(of: "Substitution, ", with: "")
            }
            return nil
        default:
            return nil
        }
    }

    private func eventIcon(_ type: WorldCupMatchEventType) -> String {
        switch type {
        case .goal, .penaltyGoal, .ownGoal: return "soccerball"
        case .penaltyMissed: return "xmark.circle"
        case .yellowCard, .redCard: return "rectangle.portrait.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .other: return "circle.fill"
        }
    }

    private func eventTint(_ type: WorldCupMatchEventType, isHome: Bool) -> Color {
        switch type {
        case .yellowCard: return .yellow
        case .redCard: return .red
        case .substitution: return .secondary
        case .goal, .penaltyGoal, .ownGoal: return isHome ? homeColor : awayColor
        default: return .secondary
        }
    }

    // MARK: - Team stat comparison

    private var teamStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Team Stats")
                .font(.headline)

            ForEach(boxScore.teamStats) { stat in
                teamStatRow(stat)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func teamStatRow(_ stat: WorldCupTeamStat) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(stat.awayDisplay)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Spacer()
                Text(stat.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stat.homeDisplay)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            comparisonBar(home: stat.homeValue, away: stat.awayValue)
        }
    }

    @ViewBuilder
    private func comparisonBar(home: Double?, away: Double?) -> some View {
        let h = max(home ?? 0, 0)
        let a = max(away ?? 0, 0)
        let total = h + a
        GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule()
                    .fill(awayColor)
                    .frame(width: total > 0 ? geo.size.width * CGFloat(a / total) : geo.size.width / 2)
                Capsule()
                    .fill(homeColor)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Lineups

    private var lineupsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lineups")
                .font(.headline)

            teamLineup(boxScore.away, accent: awayColor, fallbackName: game.strAwayTeam)
            Divider()
            teamLineup(boxScore.home, accent: homeColor, fallbackName: game.strHomeTeam)
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func teamLineup(_ team: WorldCupBoxScoreTeam, accent: Color, fallbackName: String) -> some View {
        let starters = team.players.filter { $0.starter }
        let bench = team.players.filter { !$0.starter }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(team.teamName.isEmpty ? fallbackName : team.teamName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let formation = team.formation, !formation.isEmpty {
                    Text(formation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            ForEach(starters) { player in
                playerRow(player, accent: accent)
            }

            if !bench.isEmpty {
                Text("Substitutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(bench) { player in
                    playerRow(player, accent: accent)
                }
            }
        }
    }

    @ViewBuilder
    private func playerRow(_ player: WorldCupBoxScorePlayer, accent: Color) -> some View {
        HStack(spacing: 10) {
            Text(player.jersey ?? "–")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if player.subbedOut {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    if player.subbedIn {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
                if let pos = player.positionName ?? player.position, !pos.isEmpty {
                    Text(pos)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                ForEach(notableBadges(player.stats), id: \.self) { badge in
                    statBadge(badge, accent: accent)
                }
            }
        }
    }

    /// Compact glyphs for the stats worth surfacing inline next to a player.
    private func notableBadges(_ stats: [WorldCupPlayerStat]) -> [String] {
        var badges: [String] = []
        for stat in stats {
            guard let value = stat.value, value > 0 else { continue }
            let count = Int(value)
            switch stat.name {
            case "totalGoals": badges.append(String(repeating: "⚽︎", count: max(count, 1)))
            case "ownGoals": badges.append("OG")
            case "goalAssists": badges.append("🅰︎\(count > 1 ? "×\(count)" : "")")
            case "yellowCards": badges.append("🟨")
            case "redCards": badges.append("🟥")
            default: break
            }
        }
        return badges
    }

    @ViewBuilder
    private func statBadge(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
    }
}
