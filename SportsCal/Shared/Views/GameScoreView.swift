//
//  GameScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/24/22.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// One VoiceOver sentence for a team-sport list row, so a row reads as a single element
/// ("Live, Rockets 89, Lakers 119, 3rd Qtr" / "Rockets 89, Lakers 119, final" /
/// "Rockets vs Lakers, 7:30 PM") instead of badge/score/status fragments. Mirrors the
/// Modern `LiveGameRow.voiceOverLabel` shape (state, matchup, score, period). Teams in
/// the rows' visual order: away first, home first for soccer (`Game.displaysHomeFirst`),
/// which also says who won a shootout and the aggregate of a two-leg tie.
enum GameRowAccessibility {
    static func label(
        game: Game,
        awayName: String,
        homeName: String,
        awayScore: Int?,
        homeScore: Int?,
        isLive: Bool,
        now: Date = Date()
    ) -> String {
        let base = baseLabel(game: game, awayName: awayName, homeName: homeName,
                             awayScore: awayScore, homeScore: homeScore, isLive: isLive, now: now)
        return game.isPreseason ? "\(base), preseason" : base
    }

    private static func baseLabel(
        game: Game,
        awayName: String,
        homeName: String,
        awayScore: Int?,
        homeScore: Int?,
        isLive: Bool,
        now: Date
    ) -> String {
        let status = spokenStatus(game)
        let names = game.displayOrdered(home: homeName, away: awayName)
        let matchup = "\(names.first) vs \(names.second)"
        var score: String?
        if let awayScore, let homeScore {
            let scores = game.displayOrdered(home: homeScore, away: awayScore)
            score = "\(names.first) \(scores.first), \(names.second) \(scores.second)"
        }
        let decision = game.soccerDecisionSpoken(homeName: homeName, awayName: awayName)

        if isLive {
            // The row's diamond and field strip are folded into this one label, so
            // say what they show: outs and runners, the ball and the spot.
            let situation = game.situation?.accessibilityPhrase(sport: game.sportType, homeName: homeName, awayName: awayName)
            return ["Live", score ?? matchup, status, situation, decision].compactMap { $0 }.joined(separator: ", ")
        }
        if game.isFinalStatus {
            return ["\(score ?? matchup), \(status?.lowercased() ?? "final")", decision].compactMap { $0 }.joined(separator: ", ")
        }
        // Not started yet: the kickoff time is what matters.
        if let date = game.standardDate, date > now {
            return "\(matchup), \(when(date, now: now))"
        }
        // Postponed / delayed / unknown — say whatever status the row shows.
        if let status { return "\(matchup), \(status)" }
        if let date = game.standardDate { return "\(matchup), \(when(date, now: now))" }
        return matchup
    }

    /// The status as it should be spoken: "Bot 9th" → "Bottom 9th", plus "game 2" on
    /// a doubleheader.
    private static func spokenStatus(_ game: Game) -> String? {
        var status = game.displayStatus
        if game.sportType == .mlb, let text = status {
            if text.hasPrefix("Bot ") { status = "Bottom " + text.dropFirst(4) }
            if text.hasPrefix("Mid ") { status = "Middle " + text.dropFirst(4) }
        }
        guard let number = game.doubleheaderGame else { return status }
        return [status, "game \(number) of a doubleheader"].compactMap { $0 }.joined(separator: ", ")
    }

    /// "7:30 PM" today, "Oct 5, 2026 at 7:30 PM" on other days.
    static func when(_ date: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct GameScoreView: View {
    var homeTeam: Team
    var awayTeam: Team
    var homeScore: Int
    var awayScore: Int
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    
    var isLive: Bool
    var navigationDisabled: Bool = false
    /// The competition, under the status, where the list around the row doesn't say
    /// it (soccer in Live / Your Teams).
    var competitionLabel: String? = nil

    private var accessibilityLabel: String {
        GameRowAccessibility.label(
            game: game,
            awayName: awayTeam.strTeam ?? game.strAwayTeam,
            homeName: homeTeam.strTeam ?? game.strHomeTeam,
            awayScore: awayScore,
            homeScore: homeScore,
            isLive: isLive
        )
    }

    private struct InfoSnippet: Identifiable, Equatable {
        let id: String
        let icon: String?
        let text: String
    }

    private var infoSnippets: [InfoSnippet] {
        var snippets: [InfoSnippet] = []

        // Last play — biased on live games (duplicated so it lands twice per cycle)
        if let raw = game.lastPlay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let play = InfoSnippet(id: "lastPlay", icon: "quote.bubble.fill", text: raw)
            snippets.append(play)
            if isLive {
                snippets.append(InfoSnippet(id: "lastPlay.repeat", icon: play.icon, text: play.text))
            }
        }

        // Baseball finals: the pitchers of record lead.
        if game.hasDoneStatus, let pitchers = game.featuredPitchers, !pitchers.isEmpty {
            snippets.append(InfoSnippet(id: "pitchers", icon: "baseball.fill", text: Self.pitchersLine(pitchers)))
        }

        // Leaders paired by category (up to 3)
        for pair in leaderPairsByCategory().prefix(3) {
            let away = "\(abbreviatedName(pair.away.playerName)) \(pair.away.displayValue)"
            let home = "\(abbreviatedName(pair.home.playerName)) \(pair.home.displayValue)"
            let text = "\(pair.home.categoryDisplay): \(away) · \(home)"
            snippets.append(InfoSnippet(id: "leader.\(pair.category)", icon: "chart.bar.fill", text: text))
        }

        // Venue
        if let venue = game.venueName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !venue.isEmpty {
            snippets.append(InfoSnippet(id: "venue", icon: "mappin.and.ellipse", text: venue))
        }

        return snippets
    }

    /// "W: J. Berrios (6-4) · L: R. Ray (9-4) · S: Y. Rodriguez (3)"
    static func pitchersLine(_ pitchers: [FeaturedPitcher]) -> String {
        pitchers.map { pitcher in
            let role = pitcher.role == .save ? "S" : pitcher.role.rawValue
            return ["\(role): \(pitcher.name)", pitcher.line].compactMap { $0 }.joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    private func leaderPairsByCategory() -> [(category: String, home: GameLeader, away: GameLeader)] {
        guard let home = game.homeLeaders, let away = game.awayLeaders else { return [] }
        var result: [(String, GameLeader, GameLeader)] = []
        for h in home {
            if let a = away.first(where: { $0.category == h.category }) {
                result.append((h.category, h, a))
            }
        }
        return result
    }

    private func abbreviatedName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2, let last = parts.last else { return name }
        return "\(parts[0].prefix(1)). \(last)"
    }

    @ViewBuilder
    private var rotatingInfoLine: some View {
        let snippets = infoSnippets
        if let primary = snippets.first {
            if reduceMotion || snippets.count == 1 {
                // Reduce Motion: no 4s rotation — just hold the primary line.
                infoLine(primary)
            } else {
                TimelineView(.periodic(from: .now, by: 4.0)) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate / 4.0)
                    let snippet = snippets[((tick % snippets.count) + snippets.count) % snippets.count]
                    infoLine(snippet)
                        .animation(.easeInOut(duration: 0.35), value: snippet.id)
                }
            }
        }
    }

    private func infoLine(_ snippet: InfoSnippet) -> some View {
        HStack(spacing: 4) {
            if let icon = snippet.icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(snippet.text)
                .font(.caption2)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
    }

    // MARK: Sides

    private struct Side {
        let team: Team
        let side: GameSituation.Side
    }

    /// Away then home, or home then away for soccer.
    private var displayed: (first: Side, second: Side) {
        game.displayOrdered(home: Side(team: homeTeam, side: .home), away: Side(team: awayTeam, side: .away))
    }

    private func teamColumn(_ entry: Side, leading: Bool) -> some View {
        let isHome = entry.side == .home
        // ESPN's winner first, so the side that won a shootout is the one in bold.
        let winning = game.winningSide.map { $0 == entry.side } ?? false
        return IndividualTeamView(teamURL: entry.team.strTeamBadge, shortName: entry.team.strTeamShort, longName: entry.team.strTeam,
                                  score: isHome ? homeScore : awayScore, isWinning: winning, isAway: leading,
                                  record: isHome ? game.homeRecord : game.awayRecord, seed: isHome ? game.homeSeed : game.awaySeed,
                                  seedIsRank: game.isCollegeFootball, redCards: game.redCards(entry.side))
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    /// Each side's goalscorers, in display order. Nil without a goal.
    private var soccerScorers: (first: String?, second: String?)? {
        guard game.sportType == .soccer else { return nil }
        let first = game.scorerLine(displayed.first.side)
        let second = game.scorerLine(displayed.second.side)
        return first == nil && second == nil ? nil : (first, second)
    }

    private func soccerScorerLine(_ scorers: (first: String?, second: String?)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(scorers.first ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "soccerball")
                .opacity(0.6)
            Text(scorers.second ?? "")
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }

    var body: some View {
        @Bindable var bindableFavorites = favorites
        @Bindable var bindableViewModel = viewModel

        let content = VStack(spacing: 6) {
                HStack {
                    if viewModel.appStorage.debugMode, game.idEvent?.hasPrefix(DebugGameFactory.isFakeEventPrefix) == true {
                        Text("DEBUG")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                    teamColumn(displayed.first, leading: true)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            if isLive {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 6, height: 6)
                            }
                            if let statusText = game.displayStatus {
                                Text(statusText)
                                    .foregroundColor(isLive ? .red : .secondary)
                            }
                        }
                        if let number = game.doubleheaderGame {
                            Text("Game \(number)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let pens = game.shootoutLine {
                            Text("(\(pens))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let agg = game.aggregateLine ?? (game.displaysHomeFirst ? nil : game.aggregateScore) {
                            Text(agg)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if let leg = game.legDisplay {
                            Text(leg)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let competitionLabel {
                            Text(competitionLabel)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    teamColumn(displayed.second, leading: false)
                }

                if let scorers = soccerScorers {
                    soccerScorerLine(scorers)
                }

                if isLive, let situation = game.situation {
                    GameStateStrip(
                        situation: situation,
                        sport: game.sportType,
                        homeName: homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam,
                        awayName: awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam
                    )
                    .frame(maxWidth: .infinity)
                } else if !isLive, game.hasDoneStatus, let tier = game.excitementTier, tier.isWorthWatching {
                    ExcitementBadge(tier: tier)
                        .frame(maxWidth: .infinity)
                }

                // Rotating info: last play (weighted on live), leader categories, venue.
                // A finished soccer match's scorer line says more than its venue.
                if isLive || soccerScorers == nil {
                    rotatingInfoLine
                }

                if game.playoff != nil {
                    PlayoffPill(
                        game: game,
                        homeTeamShort: homeTeam.strTeamShort,
                        awayTeamShort: awayTeam.strTeamShort
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                if game.isPreseason {
                    PreseasonPill()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityLabel))
            .contextMenu {
#if canImport(ActivityKit) && os(iOS)
                if isLive {
                    LiveActivityFollowMenu(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                        .environment(viewModel)
                }
                if !isLive {
                    AutoFollowButton(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                        .environment(viewModel)
                }
#endif
                FavoriteMenu(game: game)
                    .environment(favorites)
                CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
            }

        if navigationDisabled {
            content
        } else {
            NavigationLink {
                AdaptiveGameDetail(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }
}
#Preview {
    @Previewable @State var favorites = Favorites()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())

    let nbaGame: Game = .init(strLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "6", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "552583", awayTeamColor: "CE1141")
    let mlbGame: Game = .init(strLeague: "\(Leagues.mlb.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "333366", awayTeamColor: "003831")
    let nflGame: Game = .init(strLeague: "\(Leagues.nfl.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "003594", awayTeamColor: "A71930")
    let soccerGame: Game = .init(strLeague: "\(Leagues.English_Premier_League.rawValue)", strHomeTeam: "4", strAwayTeam: "6", strStatus: "3P", strProgress: "4", strTimestamp: "2022-10-30T00:03:00", isoDate: nil, homeTeamColor: "DA291C", awayTeamColor: "6CABDD")

    List {
        GameScoreView(homeTeam:
                .init(strTeam: "Los Angeles Lakers", strTeamShort: "LAL", strAlternate: "LAL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Rockets", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 119, awayScore: 89, game: nbaGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
        .gameCard(game: nbaGame, isLive: true)
        .environment(favorites)
        .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Colorado Rockies", strTeamShort: "COL", strAlternate: "COL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Houston Astros", strTeamShort: "HOU", strAlternate: "HOU", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 3, awayScore: 4, game: mlbGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: false)
            .gameCard(game: mlbGame, isLive: false)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Dallas Cowboys", strTeamShort: "DAL", strAlternate: "DAL", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "San Francisco 49ers", strTeamShort: "SF", strAlternate: "SF", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 24, awayScore: 31, game: nflGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: true)
            .gameCard(game: nflGame, isLive: true)
            .environment(favorites)
            .environment(viewModel)
        GameScoreView(homeTeam: .init(strTeam: "Manchester United", strTeamShort: "MUN", strAlternate: "MUN", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/wvbk1d1550584627.png"), awayTeam: Team(strTeam: "Manchester City", strTeamShort: "MCI", strAlternate: "MCI", strTeamBadge: "https://www.thesportsdb.com/images/media/team/badge/miwigx1521893583.png"), homeScore: 2, awayScore: 1, game: soccerGame, shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), isLive: false)
            .gameCard(game: soccerGame, isLive: false)
            .environment(favorites)
            .environment(viewModel)
    }
}
