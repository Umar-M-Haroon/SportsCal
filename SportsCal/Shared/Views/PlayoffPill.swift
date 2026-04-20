//
//  PlayoffPill.swift
//  SportsCal
//
//  Compact badge summarizing the playoff series state for a Game.
//  Examples: "LAL 2-1 · Conf. Finals · G3", "Tied 1-1 · First Round", "Wild Card".
//

import SwiftUI
import SportsCalModel

struct PlayoffPill: View {
    let game: Game
    let homeTeamShort: String?
    let awayTeamShort: String?

    var body: some View {
        if let text = resolvedText {
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.85), in: Capsule())
                .lineLimit(1)
        }
    }

    private var resolvedText: String? {
        if let playoff = game.playoff, let text = Self.summaryText(
            playoff: playoff,
            homeShort: homeTeamShort,
            awayShort: awayTeamShort
        ) {
            return text
        }
        // Fallback when structured playoff data hasn't been populated (stale cache, etc.)
        return game.fallbackPostseasonTitle
    }

    /// Produces a compact single-line summary, or nil if there's nothing meaningful to show.
    static func summaryText(
        playoff: PlayoffContext,
        homeShort: String?,
        awayShort: String?
    ) -> String? {
        var segments: [String] = []

        if let score = seriesScoreSegment(playoff: playoff, homeShort: homeShort, awayShort: awayShort) {
            segments.append(score)
        }
        if let round = roundLabel(from: playoff.seriesTitle) {
            segments.append(round)
        }
        if let n = playoff.gameNumber, playoff.bestOf != nil {
            segments.append("G\(n)")
        }

        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    private static func seriesScoreSegment(
        playoff: PlayoffContext,
        homeShort: String?,
        awayShort: String?
    ) -> String? {
        guard let home = playoff.homeWins, let away = playoff.awayWins else { return nil }
        if home == 0 && away == 0 { return nil } // Game 1 — show nothing here
        if home == away { return "Tied \(home)-\(away)" }
        let leader = home > away ? (homeShort ?? "Home") : (awayShort ?? "Away")
        let hi = max(home, away)
        let lo = min(home, away)
        return "\(leader) \(hi)-\(lo)"
    }

    /// Abbreviates common ESPN series titles so they fit on a single line.
    private static func roundLabel(from title: String?) -> String? {
        guard let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let lowered = raw.lowercased()
        if lowered.contains("conference final") { return "Conf. Finals" }
        if lowered.contains("conference semifinal") { return "Conf. Semis" }
        if lowered.contains("conference quarterfinal") { return "Conf. QF" }
        if lowered.contains("division final") { return "Div. Finals" }
        if lowered.contains("division series") { return "Div. Series" }
        if lowered.contains("championship series") { return "Championship" }
        if lowered.contains("wild card") { return "Wild Card" }
        if lowered.contains("first round") { return "1st Round" }
        if lowered.contains("second round") { return "2nd Round" }
        if lowered.contains("semifinal") { return "Semifinals" }
        if lowered.contains("super bowl") { return "Super Bowl" }
        if lowered.contains("nba finals") || lowered.contains("stanley cup final") || lowered == "world series" || lowered.hasSuffix(" finals") {
            return "Finals"
        }
        // Fall back to original if short enough, else truncate to a reasonable length.
        return raw.count <= 20 ? raw : String(raw.prefix(18)) + "…"
    }
}

#Preview {
    let nbaSeries = Game(
        strLeague: "\(Leagues.nba.rawValue)",
        strHomeTeam: "LAL", strAwayTeam: "BOS",
        strTimestamp: "2025-06-10T00:03:00", isoDate: nil,
        playoff: PlayoffContext(
            seriesTitle: "NBA Finals", gameNumber: 3, bestOf: 7,
            homeWins: 1, awayWins: 1, seriesCompleted: false, isNeutralSite: false
        )
    )
    let nflWildCard = Game(
        strLeague: "\(Leagues.nfl.rawValue)",
        strHomeTeam: "DAL", strAwayTeam: "SF",
        strTimestamp: "2025-01-12T00:03:00", isoDate: nil,
        playoff: PlayoffContext(
            seriesTitle: "Wild Card Round",
            isNeutralSite: false
        )
    )
    return VStack(alignment: .leading, spacing: 10) {
        PlayoffPill(game: nbaSeries, homeTeamShort: "LAL", awayTeamShort: "BOS")
        PlayoffPill(game: nflWildCard, homeTeamShort: "DAL", awayTeamShort: "SF")
    }
    .padding()
}
