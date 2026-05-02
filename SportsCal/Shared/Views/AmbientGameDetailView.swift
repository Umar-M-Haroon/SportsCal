//
//  AmbientGameDetailView.swift
//  SportsCal (iOS)
//
//  Big-type ambient hero above the shared `GameDetailSections` stack, so
//  every data-driven section (playoffs, box score, momentum chart, key
//  players, injuries, H2H, play-by-play, standings) is carried over verbatim.
//
//  `AdaptiveGameDetail` is the single navigation destination used by every
//  list row — it dispatches between Classic / Ambient based on `appTheme`
//  and preserves the existing Tournament / Race detail paths for
//  individual sports and F1.
//

import SwiftUI
import SportsCalModel

// MARK: - Adaptive entry point

/// One destination for every NavigationLink that currently pushes a team-sport
/// detail view, so origins don't need per-site theme branching. Individual-
/// sport / race detail views stay on their dedicated chromed pages regardless
/// of theme — those call sites already route to `RaceDetailView` /
/// `TournamentDetailView` / `TennisMatchDetailView` directly.
struct AdaptiveGameDetail: View {
    let game: Game
    let homeTeam: Team
    let awayTeam: Team

    @Environment(UserDefaultStorage.self) private var storage

    init(game: Game, homeTeam: Team, awayTeam: Team) {
        self.game = game
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
    }

    init(gwt: GameWithTeams) {
        self.game = gwt.game
        self.homeTeam = gwt.homeTeam ?? Team(strTeam: gwt.game.strHomeTeam)
        self.awayTeam = gwt.awayTeam ?? Team(strTeam: gwt.game.strAwayTeam)
    }

    var body: some View {
        switch storage.appTheme {
        case .ambient:
            AmbientGameDetailView(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
        case .efRemix:
            EFRemixGameDetailView(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
        case .classic:
            GameDetailView(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
        }
    }
}

// MARK: - Ambient detail hero

struct AmbientGameDetailView: View {
    let game: Game
    let homeTeam: Team
    let awayTeam: Team

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var sectionsModel = GameDetailSectionsModel()

    private var league: Leagues? {
        guard let id = game.idLeague, let intID = Int(id) else { return nil }
        return Leagues(rawValue: intID)
    }

    private var sportType: SportType? {
        guard let league else { return nil }
        return SportType(league: league)
    }

    private var isLive: Bool {
        // Matches GameViewModel's live-event detection: game has a progress/score
        // but is not marked done.
        !game.hasDoneStatus &&
            (game.intHomeScore != nil || game.intAwayScore != nil ||
             (game.strProgress?.isEmpty == false))
    }

    private var isFinal: Bool { game.hasDoneStatus }

    private var awayScore: Int? { Int(game.intAwayScore ?? "") }
    private var homeScore: Int? { Int(game.intHomeScore ?? "") }

    private var leader: Side? {
        guard let a = awayScore, let h = homeScore else { return nil }
        if a > h { return .away }
        if h > a { return .home }
        return nil
    }

    private enum Side { case away, home }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 18)

                periodBars
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                tileGrid
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                // Re-use the entire classic sections stack below the ambient hero.
                GameDetailSections(
                    game: game,
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    league: league,
                    sportType: sportType,
                    model: sectionsModel
                )
                .environment(viewModel)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AmbientPalette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle(league?.leagueName ?? "Game")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(AmbientPalette.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable { await refresh() }
        .task { await initialLoad() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(metaLine)
                    .font(.ambientMono(10))
                    .tracking(2)
                    .foregroundStyle(AmbientPalette.muted)
                Spacer()
                stateBadge
            }

            HStack(alignment: .lastTextBaseline, spacing: 14) {
                sideColumn(
                    label: AmbientFormat.abbreviation(team: awayTeam, fallback: game.strAwayTeam),
                    score: awayScore,
                    isLeader: leader == .away,
                    isFavorite: favorites.contains(game) && favorites.teams.contains(game.strAwayTeam)
                )
                Text("—")
                    .font(.ambientDisplay(40, weight: .light))
                    .foregroundStyle(AmbientPalette.ink.opacity(0.3))
                sideColumn(
                    label: AmbientFormat.abbreviation(team: homeTeam, fallback: game.strHomeTeam),
                    score: homeScore,
                    isLeader: leader == .home,
                    isFavorite: favorites.contains(game) && favorites.teams.contains(game.strHomeTeam)
                )
            }

            if let caption = subCaption {
                Text(caption)
                    .font(.ambientDisplay(14))
                    .foregroundStyle(AmbientPalette.muted)
            }
        }
    }

    private func sideColumn(label: String, score: Int?, isLeader: Bool, isFavorite: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.ambientDisplay(14, weight: .semibold))
                    .foregroundStyle(isLeader ? AmbientPalette.highlight : AmbientPalette.muted)
                if isFavorite {
                    Text("★")
                        .font(.ambientDisplay(12, weight: .bold))
                        .foregroundStyle(AmbientPalette.highlight)
                }
            }
            if let score {
                Text("\(score)")
                    .font(.ambientDisplay(isLeader ? 84 : 72, weight: .bold))
                    .foregroundStyle(isLeader ? AmbientPalette.highlight : AmbientPalette.ink)
                    .monospacedDigit()
            } else {
                Text("–")
                    .font(.ambientDisplay(72, weight: .bold))
                    .foregroundStyle(AmbientPalette.ink.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let league { parts.append(league.leagueName.uppercased()) }
        if let progress = game.strProgress, !progress.isEmpty {
            parts.append(progress.uppercased())
        }
        if isLive, let status = game.strStatus, !status.isEmpty,
           status.uppercased() != (game.strProgress?.uppercased() ?? "") {
            parts.append(status.uppercased())
        }
        if parts.isEmpty, let date = game.standardDate {
            let f = DateFormatter(); f.dateFormat = "EEE MMM d · HH:mm"
            parts.append(f.string(from: date).uppercased())
        }
        return parts.joined(separator: " · ")
    }

    private var subCaption: String? {
        guard let a = awayScore, let h = homeScore, a != h else { return nil }
        let awayAbbr = AmbientFormat.abbreviation(team: awayTeam, fallback: game.strAwayTeam)
        let homeAbbr = AmbientFormat.abbreviation(team: homeTeam, fallback: game.strHomeTeam)
        let diff = abs(a - h)
        let leaderAbbr = a > h ? awayAbbr : homeAbbr
        if isFinal {
            return "\(leaderAbbr) win by \(diff)"
        }
        let suffix: String
        if let progress = game.strProgress, !progress.isEmpty {
            suffix = " · \(progress)"
        } else {
            suffix = ""
        }
        return "\(leaderAbbr) leads by \(diff)\(suffix)"
    }

    @ViewBuilder
    private var stateBadge: some View {
        if isLive {
            HStack(spacing: 4) {
                Circle().fill(AmbientPalette.live).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.ambientMono(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(AmbientPalette.live)
            }
        } else if isFinal {
            Text("FINAL")
                .font(.ambientMono(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(AmbientPalette.muted)
        } else {
            Text("UPCOMING")
                .font(.ambientMono(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(AmbientPalette.highlight)
        }
    }

    // MARK: - Period bars

    private var periodBars: some View {
        let away = game.awayLinescores ?? []
        let home = game.homeLinescores ?? []
        let periods = max(away.count, home.count)

        if periods == 0 {
            return AnyView(EmptyView())
        }

        let periodTotals: [Double] = (0..<periods).map { i in
            let a = i < away.count ? away[i] : 0
            let h = i < home.count ? home[i] : 0
            return a + h
        }
        let maxVal = max(periodTotals.max() ?? 1, 1)

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                AmbientSectionLabel(text: "PERIOD BREAKDOWN", size: 9)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<periods, id: \.self) { i in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AmbientPalette.ink)
                                .frame(height: max(CGFloat(periodTotals[i] / maxVal) * 40, 4))
                            Text(periodLabel(for: i))
                                .font(.ambientMono(8))
                                .foregroundStyle(AmbientPalette.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Totals column
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AmbientPalette.highlight)
                            .frame(height: 40)
                        Text("TOT")
                            .font(.ambientMono(8, weight: .bold))
                            .foregroundStyle(AmbientPalette.highlight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        )
    }

    private func periodLabel(for index: Int) -> String {
        switch sportType {
        case .basketball, .nfl:
            return "Q\(index + 1)"
        case .hockey:
            return "P\(index + 1)"
        case .soccer:
            return index == 0 ? "1H" : "2H"
        case .mlb:
            return "\(index + 1)"
        default:
            return "\(index + 1)"
        }
    }

    // MARK: - Tiles

    private var tileGrid: some View {
        let tiles = tileData
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(tiles.indices, id: \.self) { i in
                let t = tiles[i]
                AmbientTile(label: t.label, value: t.value, sub: t.sub)
            }
        }
    }

    private struct TileModel {
        let label: String
        let value: String
        let sub: String?
    }

    private var tileData: [TileModel] {
        var tiles: [TileModel] = []

        // Top scorer — prefer "points" or first leader from either team.
        if let leader = firstLeader(preferring: ["points", "PTS", "passingYards", "goals"]) {
            tiles.append(TileModel(
                label: "TOP \(leader.categoryDisplay.uppercased())",
                value: leader.playerName,
                sub: leader.displayValue
            ))
        }

        // Lead changes from linescore trace (best-effort — nil-safe).
        if let changes = leadChanges() {
            tiles.append(TileModel(
                label: "LEAD CHANGES",
                value: "\(changes)",
                sub: nil
            ))
        }

        // Next game in the series / season — nearest upcoming involving either team.
        if let next = nextGame() {
            let f = DateFormatter(); f.dateFormat = "EEE"
            tiles.append(TileModel(
                label: "NEXT GAME",
                value: "\(AmbientFormat.abbreviation(team: nil, fallback: next.strAwayTeam)) @ \(AmbientFormat.abbreviation(team: nil, fallback: next.strHomeTeam))",
                sub: next.standardDate.map { f.string(from: $0).lowercased() }
            ))
        }

        // Playoff series standing (only if playoff data present).
        if let playoff = game.playoff, let home = playoff.homeWins, let away = playoff.awayWins {
            let homeAbbr = AmbientFormat.abbreviation(team: homeTeam, fallback: game.strHomeTeam)
            let awayAbbr = AmbientFormat.abbreviation(team: awayTeam, fallback: game.strAwayTeam)
            let leaderStr: String
            if home > away { leaderStr = "\(homeAbbr) \(home)–\(away)" }
            else if away > home { leaderStr = "\(awayAbbr) \(away)–\(home)" }
            else { leaderStr = "\(home)–\(away)" }
            tiles.append(TileModel(
                label: "SERIES",
                value: leaderStr,
                sub: home == away ? "tied" : "leads"
            ))
        }

        return Array(tiles.prefix(4))
    }

    private func firstLeader(preferring categories: [String]) -> GameLeader? {
        let all = (game.awayLeaders ?? []) + (game.homeLeaders ?? [])
        for wanted in categories {
            if let match = all.first(where: { $0.category.caseInsensitiveCompare(wanted) == .orderedSame }) {
                return match
            }
        }
        return all.first
    }

    private func leadChanges() -> Int? {
        let away = game.awayLinescores ?? []
        let home = game.homeLinescores ?? []
        guard !away.isEmpty || !home.isEmpty else { return nil }
        let n = max(away.count, home.count)
        var cumAway = 0.0, cumHome = 0.0
        var lastLeader: Int = 0 // -1 away, +1 home, 0 tied
        var changes = 0
        for i in 0..<n {
            cumAway += i < away.count ? away[i] : 0
            cumHome += i < home.count ? home[i] : 0
            let leader = cumHome > cumAway ? 1 : (cumAway > cumHome ? -1 : 0)
            if leader != 0 && leader != lastLeader && lastLeader != 0 { changes += 1 }
            if leader != 0 { lastLeader = leader }
        }
        return changes
    }

    private func nextGame() -> Game? {
        let homeName = game.strHomeTeam
        let awayName = game.strAwayTeam
        let after = game.standardDate ?? Date()
        return (viewModel.totalGames ?? [])
            .filter { g in
                guard g.idEvent != game.idEvent else { return false }
                guard let d = g.standardDate, d > after else { return false }
                return g.strHomeTeam == homeName || g.strAwayTeam == homeName ||
                       g.strHomeTeam == awayName || g.strAwayTeam == awayName
            }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .first
    }

    // MARK: - Load

    private var supportsPlayByPlay: Bool {
        switch sportType {
        case .basketball, .nfl, .hockey, .mlb, .soccer: return true
        default: return false
        }
    }

    private var pbpSportPath: String? {
        switch sportType {
        case .basketball: return "basketball"
        case .nfl:        return "football"
        case .hockey:     return "hockey"
        case .mlb:        return "baseball"
        case .soccer:     return "soccer"
        default:          return nil
        }
    }

    private var pbpLeagueSlug: String? {
        switch sportType {
        case .basketball: return "nba"
        case .nfl:        return "nfl"
        case .hockey:     return "nhl"
        case .mlb:        return "mlb"
        case .soccer:     return league?.espnSlug
        default:          return nil
        }
    }

    private func initialLoad() async {
        await sectionsModel.loadStandings(
            leagueID: game.idLeague,
            isIndividualSport: game.isIndividualSport
        )
        if let eventID = game.idEvent, supportsPlayByPlay {
            await sectionsModel.loadPlays(
                eventID: eventID,
                sport: pbpSportPath,
                league: pbpLeagueSlug
            )
        }
    }

    private func refresh() async {
        await initialLoad()
    }
}
