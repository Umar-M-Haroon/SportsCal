//
//  MenuBarContentView.swift
//  SportsCal
//

#if os(macOS)
import SwiftUI
import SportsCalModel

struct MenuBarContentView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    @State private var collapsedSports: Set<SportType> = []
    @State private var expandedSports: Set<SportType> = []
    @State private var previousScores: [String: String] = [:]
    @State private var flashingGameIDs: Set<String> = []
    private static let sportGroupLimit = 4
    private static let flashClearTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !viewModel.liveEventsWithTeams.isEmpty {
                        liveSection
                    }

                    if !viewModel.todayFavoriteGamesWithTeams.isEmpty {
                        favoritesSection
                    }

                    let sortedSports = viewModel.todayAllGamesBySport.keys.sorted { $0.displayName < $1.displayName }
                    if !sortedSports.isEmpty {
                        todaySection(sports: sortedSports)
                    }

                    // Up next favorite nudge (today has games but none are favorites)
                    // Debug mode: always show to allow visual testing
                    if !viewModel.todayGamesWithTeams.isEmpty
                        && (viewModel.todayFavoriteGamesWithTeams.isEmpty || storage.debugMode)
                        && !favorites.teams.isEmpty {
                        upNextFavoriteRow
                    }

                    if viewModel.liveEventsWithTeams.isEmpty
                        && viewModel.todayFavoriteGamesWithTeams.isEmpty
                        && viewModel.todayAllGamesBySport.isEmpty {
                        emptyState
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 340)

        }
        .frame(width: 300)
        .onChange(of: viewModel.liveEvents.map { "\($0.id):\($0.intHomeScore ?? ""):\($0.intAwayScore ?? "")" }) { _, _ in
            let liveIDs = Set(viewModel.liveEvents.map(\.id))
            for key in previousScores.keys where !liveIDs.contains(key) {
                previousScores.removeValue(forKey: key)
            }
            for game in viewModel.liveEvents {
                let scoreKey = "\(game.intHomeScore ?? ""):\(game.intAwayScore ?? "")"
                if let prev = previousScores[game.id], prev != scoreKey {
                    flashingGameIDs.insert(game.id)
                }
                previousScores[game.id] = scoreKey
            }
        }
        .onReceive(Self.flashClearTimer) { _ in
            if !flashingGameIDs.isEmpty {
                flashingGameIDs.removeAll()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Scoreline")
                .font(.appHeadline)
                .foregroundStyle(Color.appInk)
            Spacer()
            Button("Open App") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.link)
            .font(.appCallout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Live Section

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("LIVE", count: viewModel.liveEventsWithTeams.count, color: Color.appLive)

            ForEach(viewModel.liveEventsWithTeams) { gwt in
                gameRow(gwt, isLive: true)
            }
        }
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !viewModel.liveEventsWithTeams.isEmpty {
                Divider().padding(.horizontal, 12)
            }
            sectionHeader("FAVORITES", color: Color.appStar)

            ForEach(viewModel.todayFavoriteGamesWithTeams) { gwt in
                let isLive = viewModel.liveEvents.contains(where: { $0.id == gwt.game.id })
                gameRow(gwt, isLive: isLive)
            }
        }
    }

    // MARK: - Today Section

    private func todaySection(sports: [SportType]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !viewModel.liveEventsWithTeams.isEmpty || !viewModel.todayFavoriteGamesWithTeams.isEmpty {
                Divider().padding(.horizontal, 12)
            }
            sectionHeader("TODAY", color: .secondary)

            ForEach(sports, id: \.self) { sport in
                if let games = viewModel.todayAllGamesBySport[sport] {
                    sportGroupView(sport: sport, games: games)
                }
            }
        }
    }

    private func sportGroupView(sport: SportType, games: [GameWithTeams]) -> some View {
        let isCollapsed = collapsedSports.contains(sport)
        let isFullyExpanded = expandedSports.contains(sport)
        let limit = Self.sportGroupLimit
        let needsTruncation = games.count > limit
        let visibleGames = isCollapsed ? [] : (isFullyExpanded ? games : Array(games.prefix(limit)))
        let hiddenCount = games.count - limit

        return VStack(alignment: .leading, spacing: 2) {
            // Tappable header
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isCollapsed {
                        _ = collapsedSports.remove(sport)
                    } else {
                        _ = collapsedSports.insert(sport)
                        _ = expandedSports.remove(sport)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sport.systemImage)
                        .font(.caption2)
                        .foregroundStyle(sport.color)
                    Text("\(sport.displayName) (\(games.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 4)

            if !isCollapsed {
                ForEach(visibleGames) { gwt in
                    gameRow(gwt, isLive: false, isFavorite: favorites.contains(gwt.game))
                }

                if needsTruncation && !isFullyExpanded {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            _ = expandedSports.insert(sport)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7))
                            Text("Show \(hiddenCount) more")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                } else if isFullyExpanded && needsTruncation {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            _ = expandedSports.remove(sport)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 7))
                            Text("Show less")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Up Next Favorite

    @ViewBuilder
    private var upNextFavoriteRow: some View {
        if let nextFav = viewModel.nextFavoriteGame(after: Date(), favorites: favorites) {
            Divider().padding(.horizontal, 12)
            sectionHeader("UP NEXT", color: Color.appStar)

            let game = nextFav.game
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)

                if let sportType = game.sportType {
                    Image(systemName: sportType.systemImage)
                        .font(.caption)
                        .foregroundStyle(sportType.color)
                        .frame(width: 14)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(upNextMatchupText(game))
                        .font(.caption)
                        .fontWeight(.medium)
                    if let gameDate = game.standardDate {
                        Text(Self.upNextDateFormatter.string(from: gameDate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    private func upNextMatchupText(_ game: Game) -> String {
        let favTeam = favorites.containsHome(game.strHomeTeam) ? game.strHomeTeam : game.strAwayTeam
        if game.isIndividualSport {
            return favTeam
        }
        let opponent = (favTeam == game.strHomeTeam) ? game.strAwayTeam : game.strHomeTeam
        return "\(favTeam) vs \(opponent)"
    }

    private static let upNextDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE 'at' h:mm a"
        return f
    }()

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            if let nextFav = viewModel.nextFavoriteGame(after: Date(), favorites: favorites) {
                let game = nextFav.game
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                Text(upNextMatchupText(game))
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let gameDate = game.standardDate {
                    Text(Self.upNextDateFormatter.string(from: gameDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let nextDate = viewModel.nextDateWithGames(after: Date()) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Next games on \(Self.nextDateShortFormatter.string(from: nextDate))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let summary = viewModel.gameSummary(for: nextDate)
                if !summary.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(summary, id: \.sport) { entry in
                            HStack(spacing: 2) {
                                Image(systemName: entry.sport.systemImage)
                                    .font(.caption2)
                                    .foregroundStyle(entry.sport.color)
                                Text("\(entry.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Image(systemName: "sportscourt")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No upcoming games")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private static let nextDateShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    // MARK: - Components

    private func sectionHeader(_ title: String, count: Int? = nil, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.appFootnote)
                .tracking(2)
                .foregroundStyle(color)
            if let count {
                Text("\(count)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.appInkSoft)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func gameRow(_ gwt: GameWithTeams, isLive: Bool, isFavorite: Bool = false) -> some View {
        let game = gwt.game
        let isFlashing = flashingGameIDs.contains(game.id)
        return HStack(spacing: 6) {
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.yellow)
                    .frame(width: 8)
            } else {
                Color.clear.frame(width: 8)
            }

            if let sportType = game.sportType {
                Image(systemName: sportType.systemImage)
                    .font(.caption)
                    .foregroundStyle(sportType.color)
                    .frame(width: 14)
            }

            if game.isIndividualSport {
                individualRow(game: game, isLive: isLive)
            } else {
                teamRow(gwt: gwt, isLive: isLive)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow.opacity(isFlashing ? 0.25 : 0))
                .animation(.easeInOut(duration: 0.3), value: isFlashing)
        )
    }

    private func seedPrefix(_ seed: Int?) -> String {
        guard let seed else { return "" }
        return "(\(seed)) "
    }

    private func teamRow(gwt: GameWithTeams, isLive: Bool) -> some View {
        let game = gwt.game
        let away = seedPrefix(game.awaySeed) + Team.shortCode(strTeamShort: gwt.awayTeam?.strTeamShort, name: game.strAwayTeam)
        let home = seedPrefix(game.homeSeed) + Team.shortCode(strTeamShort: gwt.homeTeam?.strTeamShort, name: game.strHomeTeam)

        return HStack {
            if isLive, let awayScore = game.intAwayScore, let homeScore = game.intHomeScore {
                Text("\(away) \(awayScore) - \(home) \(homeScore)")
                    .font(.caption)
                    .fontWeight(.medium)
            } else {
                Text("\(away) @ \(home)")
                    .font(.caption)
            }
            if let agg = game.aggregateScore {
                Text(agg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let leg = game.legDisplay {
                Text(leg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusText(game: game, isLive: isLive)
        }
    }

    private func individualRow(game: Game, isLive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.strHomeTeam)
                    .font(.caption)
                    .lineLimit(1)
                if let leader = game.resolvedLeaderboard.first {
                    Text("\(leader.name)  \(leader.score)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusText(game: game, isLive: isLive)
        }
    }

    private func statusText(game: Game, isLive: Bool) -> some View {
        Group {
            if isLive, let progress = game.strProgress {
                HStack(spacing: 3) {
                    Circle().fill(Color.appLive).frame(width: 4, height: 4)
                    Text(progress)
                        .foregroundStyle(Color.appLive)
                }
            } else if let date = game.standardDate {
                Text(Self.timeFormatter.string(from: date))
                    .foregroundStyle(Color.appInkSoft)
            }
        }
        .font(.system(.caption2, design: .monospaced).weight(.medium))
    }
}

// MARK: - Preview

private struct MenuBarPreviewWrapper: View {
    @State private var storage = UserDefaultStorage()
    @State private var favorites = Favorites()
    @State private var viewModel: GameViewModel

    init() {
        let s = UserDefaultStorage()
        let f = Favorites()
        let vm = GameViewModel(appStorage: s, favorites: f, networkState: .loaded)

        // Build mock "today" games across multiple sports
        let now = Date()
        let cal = Calendar.current

        func game(id: String, home: String, away: String, league: String, minutesFromNow: Int) -> Game {
            let date = cal.date(byAdding: .minute, value: minutesFromNow, to: now)!
            return Game(idEvent: id, idLeague: league, idHomeTeam: id + "h", idAwayTeam: id + "a",
                        strHomeTeam: home, strAwayTeam: away, isoDate: date)
        }

        func gwt(_ g: Game) -> GameWithTeams {
            let ht = Team(idTeam: g.idHomeTeam, strTeam: g.strHomeTeam, strTeamShort: Team.shortCode(strTeamShort: nil, name: g.strHomeTeam), strAlternate: nil, strTeamBadge: nil)
            let at = Team(idTeam: g.idAwayTeam, strTeam: g.strAwayTeam, strTeamShort: Team.shortCode(strTeamShort: nil, name: g.strAwayTeam), strAlternate: nil, strTeamBadge: nil)
            return GameWithTeams(game: g, homeTeam: ht, awayTeam: at)
        }

        // NBA games (6)
        let nbaGames = (0..<6).map { i in
            let teams = [("Celtics","Lakers"),("Bucks","Heat"),("Warriors","Suns"),("Nuggets","Thunder"),("76ers","Knicks"),("Cavaliers","Pacers")]
            return game(id: "nba\(i)", home: teams[i].0, away: teams[i].1, league: "4387", minutesFromNow: 30 + i * 60)
        }

        // NHL games (5)
        let nhlGames = (0..<5).map { i in
            let teams = [("Bruins","Rangers"),("Maple Leafs","Canadiens"),("Avalanche","Stars"),("Panthers","Lightning"),("Oilers","Flames")]
            return game(id: "nhl\(i)", home: teams[i].0, away: teams[i].1, league: "4380", minutesFromNow: 60 + i * 60)
        }

        // Soccer (3)
        let soccerGames = (0..<3).map { i in
            let teams = [("Arsenal","Chelsea"),("Liverpool","Man City"),("Tottenham","Man Utd")]
            return game(id: "soc\(i)", home: teams[i].0, away: teams[i].1, league: "4328", minutesFromNow: 90 + i * 60)
        }

        // One live game
        let liveGame = Game(idEvent: "live1", idLeague: "4387", idHomeTeam: "live1h", idAwayTeam: "live1a",
                            strHomeTeam: "Mavericks", strAwayTeam: "Clippers",
                            intHomeScore: "87", intAwayScore: "82",
                            strStatus: "in", strProgress: "Q3 4:22", isoDate: now)

        // Mark some as favorites (including a live game team for label preview)
        f.add("Celtics")
        f.add("Arsenal")
        f.add("Mavericks")

        let allToday = nbaGames + nhlGames + soccerGames
        let allTodayGwt = allToday.map { gwt($0) }
        let liveGwt = gwt(liveGame)

        vm.liveEventsWithTeams = [liveGwt]
        vm.liveEvents = [liveGame]
        vm.todayGamesWithTeams = allTodayGwt + [liveGwt]
        vm.todayFavoriteGamesWithTeams = allTodayGwt.filter { f.contains($0.game) }
        vm.currentlyLiveSports = [.basketball]

        // Build todayAllGamesBySport (excluding live)
        let liveIDs: Set<String> = ["live1"]
        var grouped: [SportType: [GameWithTeams]] = [:]
        for g in allTodayGwt {
            guard !liveIDs.contains(g.id),
                  let ls = g.game.idLeague, let li = Int(ls), let league = Leagues(rawValue: li) else { continue }
            let sport = SportType(league: league)
            grouped[sport, default: []].append(g)
        }
        for (sport, games) in grouped {
            grouped[sport] = games.sorted { a, b in
                let aFav = f.contains(a.game)
                let bFav = f.contains(b.game)
                if aFav != bFav { return aFav }
                return (a.game.standardDate ?? .distantPast) < (b.game.standardDate ?? .distantPast)
            }
        }
        vm.todayAllGamesBySport = grouped
        vm.todayGames = allToday + [liveGame]

        _storage = State(initialValue: s)
        _favorites = State(initialValue: f)
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        MenuBarContentView()
            .environment(storage)
            .environment(favorites)
            .environment(viewModel)
    }
}

#Preview("Menu Bar - Busy Day") {
    MenuBarPreviewWrapper()
        .frame(width: 300, height: 400)
}
#endif
