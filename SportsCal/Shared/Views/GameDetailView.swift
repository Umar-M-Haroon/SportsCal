//
//  GameDetailView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2/7/26.
//

import SwiftUI
import SportsCalModel
import NukeUI
#if os(iOS)
import EventKit
import EventKitUI
#endif

// MARK: - Sections loader model
//
// Shared async-loaded state for `GameDetailSections` (standings + plays).
// Lives in a reference-type model so `.refreshable` can await concrete loads
// instead of round-tripping through a trigger-binding.

@Observable
@MainActor
final class GameDetailSectionsModel {
    var standing: Standing?
    var standingsLoading = true
    var standingsErrorMessage: String?

    var plays: [Play] = []
    var playsLoading = false
    var playsAvailable = true
    var selectedPeriod: Int?
    /// Ride along with the plays on the same fetch.
    var winProbability: WinProbabilitySeries?
    var teamStats: TeamStatComparison?
    var players: PlayerBoxScore?
    var scoringSummary: ScoringSummary?
    /// Football drive headers and baseball's current series, from the same payload.
    var drives: [DriveSummary]?
    var series: SeriesContext?

    var soccerMatch: SoccerMatchDetail?
    var soccerMatchLoading = false

    func loadStandings(leagueID: String?, isIndividualSport: Bool) async {
        guard !isIndividualSport else {
            standingsLoading = false
            return
        }
        guard let leagueID else {
            standingsLoading = false
            standingsErrorMessage = "League information missing for this game"
            return
        }
        do {
            standing = try await NetworkHandler.getStandings(for: leagueID)
            standingsLoading = false
            standingsErrorMessage = nil
        } catch let urlError as URLError {
            standingsLoading = false
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                standingsErrorMessage = "No internet connection"
            case .timedOut:
                standingsErrorMessage = "Request timed out"
            default:
                standingsErrorMessage = "Unable to load standings"
            }
        } catch {
            standingsLoading = false
            standingsErrorMessage = "Unable to load standings"
        }
    }

    func loadPlays(eventID: String, sport: String?, league: String?) async {
        playsLoading = true
        defer { playsLoading = false }
        do {
            let cached = try await NetworkHandler.fetchPlayByPlay(
                eventID: eventID, sport: sport, league: league, includePlayers: true
            )
            plays = cached.plays
            playsAvailable = true
            // Keep what we have when a refresh comes back without them: a 404'd
            // box score mid-game shouldn't blank the panel.
            winProbability = cached.winProbability ?? winProbability
            teamStats = cached.teamStats ?? teamStats
            players = cached.players ?? players
            scoringSummary = cached.scoringSummary ?? scoringSummary
            drives = cached.drives ?? drives
            series = cached.series ?? series
        } catch is NetworkHandler.PlayByPlayNotAvailable {
            plays = []
            playsAvailable = false
        } catch {
            // Silent failure — keep any plays we already have.
            playsAvailable = plays.isEmpty == false
        }
    }

    func loadSoccerMatch(game: Game, leagueSlug: String?) async {
        soccerMatchLoading = true
        defer { soccerMatchLoading = false }
        do {
            soccerMatch = try await NetworkHandler.getSoccerMatch(for: game, leagueSlug: leagueSlug)
        } catch is NetworkHandler.SoccerMatchNotAvailable {
            // Keep what we have: a 404 mid-match shouldn't blank the match centre.
        } catch {
            // Silent failure — keep any match detail we already have.
        }
    }
}

// MARK: - GameDetailView (classic hero)

struct GameDetailView: View {
    let game: Game
    let homeTeam: Team
    let awayTeam: Team

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(EngagementTracker.self) private var engagementTracker
    #if os(iOS)
    @Environment(NativeAdManager.self) private var adManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    #endif
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    @State private var sectionsModel = GameDetailSectionsModel()

    private var league: Leagues? {
        guard let id = game.idLeague, let intID = Int(id) else { return nil }
        return Leagues(rawValue: intID)
    }

    private var sportType: SportType? {
        guard let league else { return nil }
        return SportType(league: league)
    }

    // MARK: - Body
    var body: some View {
        classicBody
    }

    private var classicBody: some View {
        ScrollView {
            VStack(spacing: 24) {
                gameHeader
                gameInfo
                actionsRow
                GameDetailSections(
                    game: game,
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    league: league,
                    sportType: sportType,
                    model: sectionsModel
                )
            }
            .padding()
        }
        .navigationTitle(league?.leagueName ?? "Game Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let id = game.idEvent, let url = DeepLink.url(for: .game(idEvent: id)) {
                ShareLink(
                    item: url,
                    subject: Text("\(game.strAwayTeam) @ \(game.strHomeTeam)"),
                    message: Text("Follow \(game.strAwayTeam) @ \(game.strHomeTeam) live on Scoreline")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .refreshable { await refreshSections() }
        .task { await initialLoad() }
        .sheet(item: $sheetType) { sheet in
            switch sheet {
            case .calendar(let eventGame):
                #if os(iOS)
                if let game = eventGame {
                    makeCalendarEvent(game: game)
                }
                #else
                EmptyView()
                #endif
            default:
                EmptyView()
            }
        }
    }

    private func refreshSections() async {
        if let eventID = game.idEvent, supportsPlayByPlay {
            await sectionsModel.loadPlays(
                eventID: eventID,
                sport: pbpSportPath,
                league: pbpLeagueSlug
            )
        }
        await sectionsModel.loadStandings(
            leagueID: game.idLeague,
            isIndividualSport: game.isIndividualSport
        )
    }

    private func initialLoad() async {
        await sectionsModel.loadStandings(
            leagueID: game.idLeague,
            isIndividualSport: game.isIndividualSport
        )
        if !game.isIndividualSport,
           !favorites.contains(game),
           let sportType {
            engagementTracker.recordView(team: game.strHomeTeam, sport: sportType)
            engagementTracker.recordView(team: game.strAwayTeam, sport: sportType)
        }
    }

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
        case .nfl:        return league?.espnSlug ?? "nfl"
        case .hockey:     return "nhl"
        case .mlb:        return "mlb"
        case .soccer:     return league?.espnSlug
        default:          return nil
        }
    }

    // MARK: - Classic hero
    private var gameHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                teamLink(awayTeam) {
                    teamBadge(url: awayTeam.strTeamBadge, name: awayTeam.strTeamShort ?? awayTeam.strTeam, size: 60)
                }
                Spacer()
                VStack(spacing: 4) {
                    scoreOrTime
                    HeroShotsOnGoalLine(sport: sportType, stats: sectionsModel.teamStats, awayName: awayTeam.strTeamShort ?? game.strAwayTeam, homeName: homeTeam.strTeamShort ?? game.strHomeTeam)
                }
                Spacer()
                teamLink(homeTeam) {
                    teamBadge(url: homeTeam.strTeamBadge, name: homeTeam.strTeamShort ?? homeTeam.strTeam, size: 60)
                }
            }

            HStack(alignment: .top) {
                teamLink(awayTeam) {
                    heroTeamName(awayTeam.strTeam ?? "Away", seed: game.awaySeed, record: game.awayRecord, side: .away)
                }
                Spacer()
                teamLink(homeTeam) {
                    heroTeamName(homeTeam.strTeam ?? "Home", seed: game.homeSeed, record: game.homeRecord, side: .home)
                }
            }

            // `scoreOrTime` already shows the status under the score (or in place of a
            // missing date); show it here only beside a kickoff time.
            if heroScores == nil, game.standardDate != nil, let statusText = game.displayStatus {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !game.isIndividualSport, let lastPlay = game.lastPlay {
                HStack(spacing: 6) {
                    if game.strStatus == "in" {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                    }
                    Text(lastPlay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    /// A hero team name with its rank or seed, record, and the ball when it has it.
    private func heroTeamName(_ name: String, seed: Int?, record: String?, side: GameSituation.Side) -> some View {
        let hasBall = game.strStatus == "in" && game.situation?.possession == side
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                if hasBall {
                    Image(systemName: "football.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                SeededName.text(name, seed: seed, isRank: game.isCollegeFootball)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            if let record, !game.isIndividualSport {
                Text(record)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            SeededName.spoken(name, seed: seed, isRank: game.isCollegeFootball),
            record,
            hasBall ? "has the ball" : nil
        ].compactMap { $0 }.joined(separator: ", "))
    }

    /// The hero's numeric score, when the game has one.
    private var heroScores: (home: Int, away: Int)? {
        guard let home = game.intHomeScore.flatMap({ Int($0) }),
              let away = game.intAwayScore.flatMap({ Int($0) }) else { return nil }
        return (home, away)
    }

    @ViewBuilder
    private var scoreOrTime: some View {
        if let scores = heroScores {
            let home = scores.home, away = scores.away
            VStack(spacing: 4) {
                HStack(spacing: 16) {
                    Text("\(away)")
                        .font(.system(size: 36, weight: away > home ? .heavy : .regular))
                        .foregroundColor(away > home ? .primary : .secondary)
                    Text("-")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.secondary)
                    Text("\(home)")
                        .font(.system(size: 36, weight: home > away ? .heavy : .regular))
                        .foregroundColor(home > away ? .primary : .secondary)
                }
                if let statusText = game.displayStatus {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if let date = game.standardDate {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                GameTimeLabel(date: date)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        } else {
            Text(game.displayStatus ?? "TBD")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    /// Wraps a hero element in a link to the team's page for real team sports.
    /// See `TeamDetailLink` for why the link is view-based.
    private func teamLink<Content: View>(_ team: Team, @ViewBuilder content: @escaping () -> Content) -> some View {
        TeamDetailLink(team: team, isEnabled: !game.isIndividualSport, label: content)
    }

    private func teamBadge(url: String?, name: String?, size: CGFloat) -> some View {
        VStack(spacing: 6) {
            if let url, let imageURL = resolvedBadgeURL(url) {
                LazyImage(request: ImageRequest(url: imageURL, processors: [.resize(size: CGSize(width: size, height: size))])) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size, height: size)
                    } else {
                        badgePlaceholder(name: name, size: size)
                    }
                }
            } else {
                badgePlaceholder(name: name, size: size)
            }
        }
    }

    private func badgePlaceholder(name: String?, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
            if let name {
                Text(Team.shortCode(strTeamShort: nil, name: name))
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func resolvedBadgeURL(_ urlString: String) -> URL? {
        if urlString.contains("thesportsdb.com") {
            return URL(string: urlString + "/preview")
        }
        return URL(string: urlString)
    }

    private var gameInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let sport = sportType {
                    Image(systemName: sport.systemImage)
                        .foregroundColor(sport.color)
                }
                if let leagueName = league?.leagueName {
                    Text(leagueName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let date = game.standardDate {
                    GameTimeLabel(date: date, includeDate: true)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            let context = gameContextLine
            if !context.isEmpty {
                Text(context.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            // Where to watch, until it's over.
            if !game.hasDoneStatus, let networks = game.broadcasts, !networks.isEmpty {
                Label(networks.prefix(3).joined(separator: ", "), systemImage: "tv")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("On \(networks.prefix(3).joined(separator: ", "))")
            }
        }
        .padding(.horizontal, 4)
    }

    /// "Week 8", "Game 2 of a doubleheader", "Game 2 of 3 · PHI leads series 1-0".
    private var gameContextLine: [String] {
        var parts: [String] = []
        if let week = game.footballWeek { parts.append("Week \(week)") }
        if let number = game.doubleheaderGame { parts.append("Game \(number) of a doubleheader") }
        if game.playoff == nil, let series = sectionsModel.series { parts.append(series.displayText) }
        return parts
    }

    private var actionsRow: some View {
        HStack(spacing: 16) {
            Menu {
                FavoriteMenu(game: game)
                    .environment(favorites)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: favorites.contains(game) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundColor(favorites.contains(game) ? .yellow : .secondary)
                    Text("Favorite")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            #if canImport(ActivityKit) && os(iOS)
            autoFollowAction
            #endif

            #if os(iOS)
            Button {
                EKEventStore().requestAccess(to: .event) { _, _ in
                    sheetType = .calendar(game: game)
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            #endif

            Menu {
                NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Notify")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    #if canImport(ActivityKit) && os(iOS)
    @ViewBuilder
    private var autoFollowAction: some View {
        if game.idEvent != nil, !isGameCompleted(game), game.strStatus != "in" {
            let isFollowing = viewModel.appStorage.isAutoFollowing(game.idEvent!)
            Button {
                if isFollowing {
                    viewModel.appStorage.removeAutoFollow(game.idEvent!)
                } else {
                    viewModel.appStorage.addAutoFollow(game.idEvent!)
                    viewModel.preCacheBadges(homeTeam: homeTeam, awayTeam: awayTeam)
                }
                #if os(iOS)
                viewModel.sendAutoFollowRegistration()
                #endif
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isFollowing ? "clock.badge.fill" : "clock.badge")
                        .font(.title3)
                        .foregroundColor(isFollowing ? .accentColor : .secondary)
                    Text(isFollowing ? "Following" : "Auto-Follow")
                        .font(.caption2)
                        .foregroundColor(isFollowing ? .accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        let separator = (game.playoff?.isNeutralSite == true) ? " vs " : " @ "
        event.title = "\(game.strAwayTeam)\(separator)\(game.strHomeTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 2)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}

// MARK: - GameDetailSections
//
// The box-score / momentum / key-players / play-by-play / injuries /
// head-to-head / standings stack. Shared across detail surfaces (classic and
// ambient) so each is feature-complete. Loading state lives on
// `GameDetailSectionsModel`, owned by the enclosing view.

struct GameDetailSections: View {
    let game: Game
    let homeTeam: Team
    let awayTeam: Team
    let league: Leagues?
    let sportType: SportType?
    let model: GameDetailSectionsModel

    @Environment(GameViewModel.self) private var viewModel
    #if os(iOS)
    @Environment(NativeAdManager.self) private var adManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    #endif

    // Box-score columns grow with Dynamic Type (the grid scrolls sideways when it outgrows the card).
    @ScaledMetric(relativeTo: .caption) private var boxTeamWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .caption) private var boxPeriodWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var boxTotalWidth: CGFloat = 40

    var body: some View {
        VStack(spacing: 24) {
            liveSituationSection
            playoffSeriesSection
            boxScoreSection
            PlayerBoxScoreSection(box: model.players, sport: sportType, homeName: homeShortName, awayName: awayShortName, homeColor: homeColor, awayColor: awayColor)
            pitchersSection
            soccerMatchSection
            winProbabilitySection
            momentumChartSection
            teamStatsSection
            keyPlayersSection
            ScoringSummarySection(summary: model.scoringSummary, game: game, homeName: homeShortName, awayName: awayShortName, homeColor: homeColor, awayColor: awayColor)
            playByPlaySection
            injuriesSection
            headToHeadSection
            #if os(iOS)
            if !subscriptionManager.isPro && AdConfiguration.isEnabled,
               let ad = adManager.adForSlot(0) {
                NativeAdCardView(nativeAd: ad)
            }
            #endif
            standingsSection
        }
        // Drive play-by-play loading from the always-present body rather than the
        // section itself, so data still loads even when the section is hidden.
        .task(id: game.idEvent) {
            await reloadPlays()
            await reloadSoccerMatch()
        }
        .onChange(of: game.lastPlay) { _, _ in
            Task { await reloadPlays() }
            Task { await reloadSoccerMatch() }
        }
        .onChange(of: model.plays) { _, newPlays in
            let newAvailable = Set(newPlays.compactMap { $0.period?.number })
            if let current = model.selectedPeriod, newAvailable.contains(current) {
                return
            }
            model.selectedPeriod = newAvailable.max()
        }
    }

    // MARK: Playoff series

    @ViewBuilder
    private var playoffSeriesSection: some View {
        if let playoff = game.playoff {
            playoffRichSection(playoff: playoff)
        } else if let fallbackTitle = game.fallbackPostseasonTitle {
            playoffMinimalSection(title: fallbackTitle)
        }
    }

    @ViewBuilder
    private func playoffRichSection(playoff: PlayoffContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(playoff.seriesTitle ?? "Postseason")
                    .font(.headline)
                Spacer()
                if let best = playoff.bestOf {
                    Text("Best of \(best)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let home = playoff.homeWins, let away = playoff.awayWins,
               let best = playoff.bestOf {
                seriesDots(homeWins: home, awayWins: away, bestOf: best)

                Text(seriesStatusText(
                    homeWins: home, awayWins: away,
                    seriesCompleted: playoff.seriesCompleted ?? false
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if let gameNumber = playoff.gameNumber, gameNumber > 0 {
                Text("Game \(gameNumber)" + (playoff.bestOf.map { " of \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if playoff.isNeutralSite == true, let venue = game.venueName {
                Label("Neutral site · \(venue)", systemImage: "mappin.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if playoff.isNeutralSite == true {
                Label("Neutral site", systemImage: "mappin.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func playoffMinimalSection(title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
            Text(title)
                .font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func seriesDots(homeWins: Int, awayWins: Int, bestOf: Int) -> some View {
        let played = homeWins + awayWins
        HStack(spacing: 6) {
            ForEach(0..<bestOf, id: \.self) { index in
                Circle()
                    .fill(fillForSeriesDot(index: index, homeWins: homeWins, awayWins: awayWins, played: played))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func fillForSeriesDot(index: Int, homeWins: Int, awayWins: Int, played: Int) -> Color {
        if index < awayWins {
            return Color(hex: game.awayTeamColor ?? "") ?? .accentColor
        }
        if index < played {
            return Color(hex: game.homeTeamColor ?? "") ?? .accentColor
        }
        return Color.secondary.opacity(0.25)
    }

    private func seriesStatusText(homeWins: Int, awayWins: Int, seriesCompleted: Bool) -> String {
        let homeShort = Team.shortCode(strTeamShort: homeTeam.strTeamShort, name: game.strHomeTeam)
        let awayShort = Team.shortCode(strTeamShort: awayTeam.strTeamShort, name: game.strAwayTeam)
        if seriesCompleted {
            if homeWins > awayWins { return "\(homeShort) win series \(homeWins)-\(awayWins)" }
            if awayWins > homeWins { return "\(awayShort) win series \(awayWins)-\(homeWins)" }
            return "Series tied \(homeWins)-\(awayWins)"
        }
        if homeWins == awayWins { return "Series tied \(homeWins)-\(awayWins)" }
        if homeWins > awayWins { return "\(homeShort) lead \(homeWins)-\(awayWins)" }
        return "\(awayShort) lead \(awayWins)-\(homeWins)"
    }

    // MARK: Box score

    @ViewBuilder
    private var boxScoreSection: some View {
        if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
           !homeLs.isEmpty, !awayLs.isEmpty {
            let periodCount = max(homeLs.count, awayLs.count)
            let labels = game.periodLabels(count: periodCount)
            let homeTotal = homeLs.reduce(0, +)
            let awayTotal = awayLs.reduce(0, +)

            VStack(alignment: .leading, spacing: 12) {
                Text("Box Score")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            Text("")
                                .frame(width: boxTeamWidth, alignment: .leading)
                            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                                Text(label)
                                    .frame(width: boxPeriodWidth, alignment: .center)
                            }
                            Text(showsHitsAndErrors ? "R" : "T")
                                .frame(width: boxTotalWidth, alignment: .center)
                            if showsHitsAndErrors {
                                Text("H").frame(width: boxTotalWidth, alignment: .center)
                                Text("E").frame(width: boxTotalWidth, alignment: .center)
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        Divider()

                        boxScoreRow(
                            name: Team.shortCode(strTeamShort: awayTeam.strTeamShort, name: game.strAwayTeam),
                            scores: awayLs, padTo: periodCount, total: awayTotal, isLeading: awayTotal > homeTotal,
                            hitsAndErrors: showsHitsAndErrors ? (game.awayHits, game.awayErrors) : nil
                        )
                        boxScoreRow(
                            name: Team.shortCode(strTeamShort: homeTeam.strTeamShort, name: game.strHomeTeam),
                            scores: homeLs, padTo: periodCount, total: homeTotal, isLeading: homeTotal > awayTotal,
                            hitsAndErrors: showsHitsAndErrors ? (game.homeHits, game.homeErrors) : nil
                        )
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
                }
                // One summary instead of a grid of bare numbers.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(boxScoreAccessibilityLabel(labels: labels, home: homeLs, away: awayLs,
                                                               homeTotal: homeTotal, awayTotal: awayTotal))
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    /// Baseball's line score ends R / H / E, once ESPN has sent the hits.
    private var showsHitsAndErrors: Bool {
        sportType == .mlb && (game.homeHits != nil || game.awayHits != nil)
    }

    private func boxScoreRow(name: String, scores: [Double], padTo count: Int, total: Double, isLeading: Bool,
                             hitsAndErrors: (hits: Int?, errors: Int?)? = nil) -> some View {
        HStack(spacing: 0) {
            Text(name)
                .frame(width: boxTeamWidth, alignment: .leading)
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                Text(formatLinescoreValue(score))
                    .frame(width: boxPeriodWidth, alignment: .center)
            }
            ForEach(0..<max(0, count - scores.count), id: \.self) { _ in
                Text("-")
                    .frame(width: boxPeriodWidth, alignment: .center)
            }
            Text(formatLinescoreValue(total))
                .fontWeight(isLeading ? .bold : .regular)
                .frame(width: boxTotalWidth, alignment: .center)
            if let hitsAndErrors {
                Text(hitsAndErrors.hits.map(String.init) ?? "-")
                    .frame(width: boxTotalWidth, alignment: .center)
                Text(hitsAndErrors.errors.map(String.init) ?? "-")
                    .frame(width: boxTotalWidth, alignment: .center)
            }
        }
        .font(.caption)
        .monospacedDigit()
    }

    /// "Box score. Celtics: Q1 28, Q2 31, …, total 112. Lakers: …"
    private func boxScoreAccessibilityLabel(labels: [String], home: [Double], away: [Double],
                                            homeTotal: Double, awayTotal: Double) -> String {
        func line(_ name: String, _ scores: [Double], _ total: Double, hits: Int?, errors: Int?) -> String {
            let periods = zip(labels, scores).map { "\($0) \(formatLinescoreValue($1))" }
            var totals = [showsHitsAndErrors ? "\(formatLinescoreValue(total)) runs" : "total \(formatLinescoreValue(total))"]
            if showsHitsAndErrors {
                if let hits { totals.append("\(hits) hits") }
                if let errors { totals.append("\(errors) errors") }
            }
            return "\(name): " + (periods + totals).joined(separator: ", ")
        }
        let awayName = awayTeam.strTeam ?? game.strAwayTeam
        let homeName = homeTeam.strTeam ?? game.strHomeTeam
        return "Box score. " + line(awayName, away, awayTotal, hits: game.awayHits, errors: game.awayErrors)
            + ". " + line(homeName, home, homeTotal, hits: game.homeHits, errors: game.homeErrors)
    }

    private func formatLinescoreValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }

    // MARK: Pitchers

    /// Baseball: the probable starters before first pitch, the pitchers of record after.
    @ViewBuilder
    private var pitchersSection: some View {
        if sportType == .mlb {
            if game.hasDoneStatus, let pitchers = game.featuredPitchers, !pitchers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pitchers of Record").font(.headline)
                    ForEach(Array(pitchers.enumerated()), id: \.offset) { _, pitcher in
                        HStack(spacing: 8) {
                            Text(pitcher.role == .save ? "S" : pitcher.role.rawValue)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 16, alignment: .leading)
                            Text(pitcher.name).font(.subheadline)
                            if let line = pitcher.line {
                                Text(line).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer(minLength: 0)
                            if let side = pitcher.side {
                                Text(side == .home ? homeShortName : awayShortName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondaryGroupedBackground)
                .cornerRadius(12)
            } else if game.strStatus != "in", !game.hasDoneStatus,
                      game.homeProbable != nil || game.awayProbable != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Probable Pitchers").font(.headline)
                    probableRow(team: awayShortName, pitcher: game.awayProbable)
                    probableRow(team: homeShortName, pitcher: game.homeProbable)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondaryGroupedBackground)
                .cornerRadius(12)
            }
        }
    }

    private func probableRow(team: String, pitcher: ProbablePitcher?) -> some View {
        HStack(spacing: 8) {
            Text(team)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .leading)
            Text(pitcher?.name ?? "TBA").font(.subheadline)
            Spacer(minLength: 0)
            if let record = pitcher?.record {
                Text(record).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Momentum chart

    @ViewBuilder
    private var momentumChartSection: some View {
        // Soccer's match centre draws real attack momentum instead of the score line.
        if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
           !homeLs.isEmpty, !awayLs.isEmpty,
           game.intHomeScore != nil,
           model.soccerMatch?.momentum.isEmpty ?? true {
            MomentumChartView(
                game: game,
                homeTeamName: homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam,
                awayTeamName: awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam,
                plays: model.plays
            )
        }
    }

    // MARK: Live situation, win probability, team stats

    private var homeShortName: String { homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam }
    private var awayShortName: String { awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam }
    private var homeColor: Color { game.homeTeamColor.map { Color(hex: $0) } ?? .blue }
    private var awayColor: Color { game.awayTeamColor.map { Color(hex: $0) } ?? .red }

    @ViewBuilder
    private var liveSituationSection: some View {
        if game.strStatus == "in", let situation = game.situation,
           situation.hasBaseballState || situation.hasFootballState || situation.homeWinProbability != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Live").font(.headline)
                LiveSituationPanel(
                    situation: situation, sport: sportType,
                    homeName: homeShortName, awayName: awayShortName,
                    homeColor: homeColor, awayColor: awayColor
                )
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var winProbabilitySection: some View {
        if let series = model.winProbability {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Win Probability").font(.headline)
                    Spacer()
                    if let tier = game.excitementTier, game.hasDoneStatus {
                        ExcitementBadge(tier: tier)
                    }
                }
                WinProbabilityChart(
                    series: series,
                    homeName: homeShortName, awayName: awayShortName,
                    homeColor: homeColor, awayColor: awayColor,
                    league: league
                )
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var teamStatsSection: some View {
        // Soccer matches with a match centre show their own, richer team stats above.
        if model.soccerMatch?.teamStats.isEmpty ?? true, let stats = model.teamStats {
            VStack(alignment: .leading, spacing: 12) {
                Text("Team Stats").font(.headline)
                TeamStatComparisonView(
                    stats: stats,
                    homeName: homeShortName, awayName: awayShortName,
                    homeColor: homeColor, awayColor: awayColor
                )
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    // MARK: Key players

    @ViewBuilder
    private var keyPlayersSection: some View {
        if let homeLeaders = game.homeLeaders, let awayLeaders = game.awayLeaders,
           !homeLeaders.isEmpty, !awayLeaders.isEmpty {
            let categories = matchedLeaderCategories(away: awayLeaders, home: homeLeaders)

            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Key Players")
                        .font(.headline)

                    ForEach(Array(categories.enumerated()), id: \.offset) { _, pair in
                        VStack(spacing: 8) {
                            Text(pair.categoryDisplay)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pair.awayLeader.playerName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(pair.awayLeader.displayValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(pair.homeLeader.playerName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(pair.homeLeader.displayValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }

                        if pair.category != categories.last?.category {
                            Divider()
                        }
                    }
                }
                .padding()
                .background(Color.secondaryGroupedBackground)
                .cornerRadius(12)
            }
        }
    }

    private struct LeaderPair {
        let category: String
        let categoryDisplay: String
        let awayLeader: GameLeader
        let homeLeader: GameLeader
    }

    private func matchedLeaderCategories(away: [GameLeader], home: [GameLeader]) -> [LeaderPair] {
        away.compactMap { awayLeader in
            guard let homeLeader = home.first(where: { $0.category == awayLeader.category }) else { return nil }
            return LeaderPair(category: awayLeader.category, categoryDisplay: awayLeader.categoryDisplay,
                              awayLeader: awayLeader, homeLeader: homeLeader)
        }
    }

    // MARK: Injuries

    @ViewBuilder
    private var injuriesSection: some View {
        let home = game.homeInjuries ?? []
        let away = game.awayInjuries ?? []
        if !game.isIndividualSport, !(home.isEmpty && away.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Injury Report")
                    .font(.headline)

                HStack(alignment: .top, spacing: 12) {
                    injuryColumn(
                        teamName: awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam,
                        reports: away
                    )
                    Divider()
                    injuryColumn(
                        teamName: homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam,
                        reports: home
                    )
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func injuryColumn(teamName: String, reports: [InjuryReport]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(teamName)
                .font(.subheadline)
                .fontWeight(.semibold)
            if reports.isEmpty {
                Text("No reported injuries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(reports.prefix(6).enumerated()), id: \.offset) { _, report in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(report.playerName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if let position = report.position {
                                Text(position)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(report.status)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(injuryStatusColor(report.status).opacity(0.2))
                                .foregroundColor(injuryStatusColor(report.status))
                                .cornerRadius(4)
                            if let detail = report.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                if reports.count > 6 {
                    Text("+\(reports.count - 6) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func injuryStatusColor(_ status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("out") || lower.contains("ir") || lower.contains("season") {
            return .red
        }
        if lower.contains("question") || lower.contains("doubt") {
            return .orange
        }
        if lower.contains("day") || lower.contains("probable") {
            return .yellow
        }
        return .secondary
    }

    // MARK: Head-to-head

    @ViewBuilder
    private var headToHeadSection: some View {
        let seasons = headToHeadSeasons
        // Hide the section entirely when there are no prior meetings (e.g. World Cup
        // group-stage games) rather than showing an empty placeholder card, and when
        // the soccer match centre already shows ESPN's fuller meeting history.
        if !seasons.isEmpty, model.soccerMatch?.headToHead == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Head-to-Head")
                    .font(.headline)

                recordRow(computeRecord(matchups: seasons.flatMap(\.games)))
                    .font(.subheadline)
                    .padding(.horizontal, 4)

                ForEach(seasons, id: \.label) { season in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(season.label)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            recordRow(computeRecord(matchups: season.games), compact: true)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(season.games, id: \.id) { matchupRow($0) }
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    /// "NYK 3  ·  Draws: 1  ·  2 BOS" — away on the left, home on the right, matching
    /// the score rows below.
    private func recordRow(_ record: Record, compact: Bool = false) -> some View {
        let away = awayTeam.strTeamShort ?? awayTeam.strTeam ?? "Away"
        let home = homeTeam.strTeamShort ?? homeTeam.strTeam ?? "Home"
        return HStack(spacing: 6) {
            Text(away).fontWeight(.semibold)
            Text("\(record.awayWins)")
                .foregroundColor(record.awayWins > record.homeWins ? .primary : .secondary)
            if compact {
                Text(record.draws > 0 ? "–  \(record.draws)D  –" : "–")
            } else {
                Spacer()
                if record.draws > 0 {
                    Text("Draws: \(record.draws)")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            Text("\(record.homeWins)")
                .foregroundColor(record.homeWins > record.awayWins ? .primary : .secondary)
            Text(home).fontWeight(.semibold)
        }
    }

    private func matchupRow(_ m: Game) -> some View {
        HStack {
            if let date = m.standardDate {
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 56, alignment: .leading)
            }
            Spacer()
            Text(m.strAwayTeam)
                .font(.caption)
                .lineLimit(1)
            Text("\(m.intAwayScore ?? "-")")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 24)
            Text("-")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(m.intHomeScore ?? "-")")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 24)
            Text(m.strHomeTeam)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
    }

    private struct H2HSeason { let label: String; let games: [Game] }

    /// Finished meetings between these two teams, newest season first, newest game
    /// first within a season.
    private var headToHeadSeasons: [H2HSeason] {
        let matchups = previousMatchups
        let grouped = Dictionary(grouping: matchups) { $0.resolvedSeason ?? "Earlier" }
        return grouped
            .map { H2HSeason(label: $0.key == "Earlier" ? $0.key : Game.seasonDisplayName($0.key), games: $0.value) }
            .sorted {
                ($0.games.first?.standardDate ?? .distantPast) > ($1.games.first?.standardDate ?? .distantPast)
            }
    }

    private var previousMatchups: [Game] {
        guard let allGames = viewModel.totalGames else { return [] }
        let liveIDs = Set(viewModel.liveEvents.map(\.id))
        return allGames.filter { g in
            g.id != game.id &&
            g.intHomeScore != nil && g.intAwayScore != nil &&
            !liveIDs.contains(g.id) && g.isFinalStatus &&
            isSameFixture(g)
        }
        .sorted { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }
    }

    /// Whether `g` is between the same two teams (either way round). Either signal is
    /// enough: names differ between sources ("Man Utd" / "Manchester United"), and IDs
    /// can too — the server keeps raw ESPN ids when it has no TheSportsDB mapping.
    private func isSameFixture(_ g: Game) -> Bool {
        sameSides(g) != nil
    }

    /// For a meeting between these two teams: true when this game's home team was also
    /// home in `g`, false when it was away, nil when `g` isn't between these teams.
    /// Names are checked before ids, and matching and win attribution share this one
    /// rule so they can't disagree.
    private func sameSides(_ g: Game) -> Bool? {
        let home = game.strHomeTeam, away = game.strAwayTeam
        if g.strHomeTeam == home && g.strAwayTeam == away { return true }
        if g.strHomeTeam == away && g.strAwayTeam == home { return false }
        func id(_ s: String?) -> String? { (s?.isEmpty == false) ? s : nil }
        if let h = id(game.idHomeTeam), let a = id(game.idAwayTeam),
           let gh = id(g.idHomeTeam), let ga = id(g.idAwayTeam) {
            if gh == h && ga == a { return true }
            if gh == a && ga == h { return false }
        }
        return nil
    }

    private struct Record { let homeWins: Int; let awayWins: Int; let draws: Int }

    /// Wins are credited to this game's home/away team, whichever side they played on.
    private func computeRecord(matchups: [Game]) -> Record {
        var homeWins = 0, awayWins = 0, draws = 0
        for m in matchups {
            guard let hs = Int(m.intHomeScore ?? ""), let as_ = Int(m.intAwayScore ?? "") else { continue }
            if hs == as_ {
                draws += 1
            } else if (sameSides(m) ?? true) == (hs > as_) {
                homeWins += 1
            } else {
                awayWins += 1
            }
        }
        return Record(homeWins: homeWins, awayWins: awayWins, draws: draws)
    }

    // MARK: Standings

    @ViewBuilder
    private var standingsSection: some View {
        if !game.isIndividualSport {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Standings")
                        .font(.headline)
                    Spacer()
                    if sportType == .soccer, let league {
                        // The competition hub: full table with form, matches, top scorers.
                        NavigationLink("Full table") {
                            SoccerCompetitionHubView(league: league)
                        }
                        .font(.subheadline)
                    }
                }

                if model.standingsLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else if let groups = model.standing?.groups, !groups.isEmpty {
                    // Just the group(s) the two teams are in — every NCAA conference
                    // is far too much under one game.
                    let own = groups.filter { $0.entries.contains(where: isTeamInGame(entry:)) }
                    ForEach(Array((own.isEmpty ? groups : own).enumerated()), id: \.offset) { _, group in
                        standingsGroup(name: group.name, entries: group.entries)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text(model.standingsErrorMessage ?? "Standings not available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button {
                            model.standingsLoading = true
                            model.standingsErrorMessage = nil
                            Task {
                                await model.loadStandings(
                                    leagueID: game.idLeague,
                                    isIndividualSport: game.isIndividualSport
                                )
                            }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func standingsGroup(name: String?, entries: [Entry]) -> some View {
        LeagueStandingsTable(name: name, entries: entries, league: league,
                             isHighlighted: isTeamInGame(entry:))
    }

    private func isTeamInGame(entry: Entry) -> Bool {
        guard let teamName = entry.team?.displayName else { return false }
        return teamName == game.strHomeTeam || teamName == game.strAwayTeam ||
               entry.team?.shortDisplayName == (homeTeam.strTeamShort ?? homeTeam.strTeam) ||
               entry.team?.shortDisplayName == (awayTeam.strTeamShort ?? awayTeam.strTeam)
    }

    // MARK: Play-by-play

    private var supportsPlayByPlay: Bool {
        switch sportType {
        case .basketball, .nfl, .hockey, .mlb, .soccer: return true
        default: return false
        }
    }

    private var availablePeriods: [Int] {
        let set = Set(model.plays.compactMap { $0.period?.number })
        return set.sorted()
    }

    private var playsInSelectedPeriod: [Play] {
        guard let selected = model.selectedPeriod else { return model.plays }
        return model.plays.filter { $0.period?.number == selected }
    }

    // Whether the play-by-play card should be shown. Only rendered once there are
    // actual plays for this game — no empty placeholder or loading state, since many
    // games (e.g. World Cup) never get a play-by-play feed. Loading itself is driven
    // from the parent body (see reloadPlays) so it runs regardless of visibility.
    private var showsPlayByPlay: Bool {
        guard supportsPlayByPlay, game.idEvent != nil else { return false }
        return !model.plays.isEmpty
    }

    @ViewBuilder
    private var playByPlaySection: some View {
        if showsPlayByPlay {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Play-by-Play")
                        .font(.headline)
                    Spacer()
                    if model.playsLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        // Baseball counts what's listed, not ESPN's ~600 pitch rows.
                        Text("\(model.plays.displayedPlayCount(isBaseball: sportType == .mlb)) plays")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                periodPicker

                let visible = playsInSelectedPeriod
                if visible.isEmpty {
                    Text("No plays recorded for this period")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else if sportType == .mlb {
                    baseballPlays(visible)
                } else if sportType == .nfl {
                    footballPlays()
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, play in
                            playRow(play)
                        }
                    }
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    /// While a game is on, the latest play leads; afterwards it reads in order.
    private var newestFirst: Bool { game.strStatus == "in" }

    /// Baseball: results only, under "Top 3rd" / "Bottom 3rd" headers, each with its
    /// pitches folded underneath.
    @ViewBuilder
    private func baseballPlays(_ plays: [Play]) -> some View {
        let halves = plays.baseballHalfInnings()
        let ordered = newestFirst ? Array(halves.reversed()) : halves
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(ordered) { half in
                Text("\(half.isTop ? "Top" : "Bottom") \(Leagues.mlb.periodName(half.inning))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                let atBats = newestFirst ? Array(half.atBats.reversed()) : half.atBats
                ForEach(atBats) { atBat in
                    BaseballAtBatRow(atBat: atBat)
                }
            }
        }
    }

    /// Football: plays under a header per drive ("KC · Touchdown · 8 plays, 75 yards,
    /// 4:12"), limited to the selected quarter.
    @ViewBuilder
    private func footballPlays() -> some View {
        let groups = model.plays.groupedIntoDrives(model.drives).compactMap { group -> PlayDriveGroup? in
            var group = group
            if let selected = model.selectedPeriod {
                group.plays = group.plays.filter { $0.period?.number == selected }
            }
            if newestFirst { group.plays.reverse() }
            return group.plays.isEmpty ? nil : group
        }
        let ordered = newestFirst ? Array(groups.reversed()) : groups
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(ordered) { group in
                if let drive = group.drive {
                    driveHeader(drive)
                }
                ForEach(Array(group.plays.enumerated()), id: \.offset) { _, play in
                    playRow(play)
                }
            }
        }
    }

    private func driveHeader(_ drive: DriveSummary) -> some View {
        HStack(spacing: 6) {
            if let team = drive.team {
                Text(team).font(.caption.weight(.bold))
            }
            Text(drive.result ?? "Drive in progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(drive.isScore == true ? Color.accentColor : .primary)
            if let summary = drive.summary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func reloadPlays() async {
        guard supportsPlayByPlay, let eventID = game.idEvent else { return }
        await model.loadPlays(
            eventID: eventID,
            sport: pbpSportPath,
            league: pbpLeagueSlug
        )
    }

    // MARK: Soccer match centre

    private var isSoccer: Bool { sportType == .soccer }

    private func reloadSoccerMatch() async {
        guard isSoccer, game.idEvent != nil else { return }
        await model.loadSoccerMatch(game: game, leagueSlug: league?.espnSlug)
    }

    @ViewBuilder
    private var soccerMatchSection: some View {
        if isSoccer, let match = model.soccerMatch, !match.isEmpty {
            SoccerMatchCentreView(match: match, game: game)
        }
    }

    @ViewBuilder
    private var periodPicker: some View {
        let periods = availablePeriods
        if periods.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(periods, id: \.self) { p in
                        let isSelected = model.selectedPeriod == p
                        Button {
                            model.selectedPeriod = p
                        } label: {
                            Text(periodAbbreviation(p))
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundColor(isSelected ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func playRow(_ play: Play) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let clockText = play.clock?.displayValue, !clockText.isEmpty {
                Text(clockText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let text = play.text {
                    Text(text)
                        .font(.caption)
                        .foregroundColor(play.scoringPlay == true ? .primary : .secondary)
                        .fontWeight(play.scoringPlay == true ? .semibold : .regular)
                }
                if play.scoringPlay == true,
                   let away = play.awayScore, let home = play.homeScore {
                    Text("\(away) – \(home)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    /// Shared with the box score, so OT reads "OT"/"2OT" and NCAA halves "H1"/"H2".
    private func periodAbbreviation(_ period: Int) -> String {
        game.periodLabel(period)
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
        case .nfl:        return league?.espnSlug ?? "nfl"
        case .hockey:     return "nhl"
        case .mlb:        return "mlb"
        case .soccer:     return league?.espnSlug
        default:          return nil
        }
    }
}


// MARK: - Baseball play-by-play row

/// One plate appearance: the result, with its pitches a tap away.
private struct BaseballAtBatRow: View {
    let atBat: BaseballAtBat
    @State private var showsPitches = false

    var body: some View {
        let play = atBat.result
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(play.text ?? "")
                        .font(.caption)
                        .foregroundColor(play.scoringPlay == true ? .primary : .secondary)
                        .fontWeight(play.scoringPlay == true ? .semibold : .regular)
                    if play.scoringPlay == true, let away = play.awayScore, let home = play.homeScore {
                        Text("\(away) – \(home)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !atBat.pitches.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsPitches.toggle() }
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(atBat.pitches.count)")
                                .monospacedDigit()
                            Image(systemName: showsPitches ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsPitches ? "Hide \(atBat.pitches.count) pitches" : "Show \(atBat.pitches.count) pitches")
                }
            }
            if showsPitches {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(atBat.pitches) { pitch in
                        Text(pitch.text ?? pitch.type?.text ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 10)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Standings table

/// One standings group (a conference, division or league table), ranked and with the
/// columns its sport reads by (see `StandingsStyle`). Shared by the game detail, the
/// team page and the league hub; `isHighlighted` bolds the rows being looked at.
struct LeagueStandingsTable: View {
    let name: String?
    let entries: [Entry]
    let style: StandingsStyle
    var isHighlighted: (Entry) -> Bool = { _ in false }

    @ScaledMetric(relativeTo: .caption) private var rankWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var statWidth: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var wideStatWidth: CGFloat = 40

    init(name: String?, entries: [Entry], league: Leagues?, isHighlighted: @escaping (Entry) -> Bool = { _ in false }) {
        self.name = name
        self.entries = entries
        self.style = league.map(StandingsStyle.init(league:)) ?? .basketball
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        let rows = style.ranked(entries)
        let columns = style.columns(for: entries)
        VStack(alignment: .leading, spacing: 6) {
            if let name {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            // The streak column only when the table still fits with it.
            if let extra = style.optionalColumn, entries.contains(where: { $0.streak != nil }) {
                ViewThatFits(in: .horizontal) {
                    table(rows: rows, columns: columns + [extra])
                    table(rows: rows, columns: columns)
                }
            } else {
                table(rows: rows, columns: columns)
            }
        }
        .padding(.vertical, 4)
    }

    private func table(rows: [RankedStandingsEntry], columns: [StandingsColumn]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: rankWidth, alignment: .leading)
                Text("Team")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns, id: \.self) { column in
                    Text(column.title)
                        .frame(width: width(column), alignment: .center)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityHidden(true)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                standingsRow(row, columns: columns)
            }
        }
    }

    private func standingsRow(_ row: RankedStandingsEntry, columns: [StandingsColumn]) -> some View {
        let entry = row.entry
        let highlighted = isHighlighted(entry)
        let teamName = entry.team?.shortDisplayName ?? entry.team?.displayName ?? "-"
        return HStack(spacing: 0) {
            Text("\(row.rank)")
                .frame(width: rankWidth, alignment: .leading)
            HStack(spacing: 2) {
                Text(teamName)
                    .lineLimit(1)
                if let marker = entry.clinchMarker {
                    Text(marker)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { column in
                Text(column.value(for: entry))
                    .frame(width: width(column), alignment: .center)
                    .fontWeight(column == .points ? .semibold : nil)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .fontWeight(highlighted ? .bold : .regular)
        .foregroundColor(highlighted ? .primary : .secondary)
        .overlay(alignment: .leading) {
            // Soccer qualification / relegation zone, from ESPN's note colour.
            if style.isSoccer, let color = Color(hex: entry.note?.color) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3)
                    .offset(x: -6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(row, teamName: teamName, columns: columns))
    }

    private func width(_ column: StandingsColumn) -> CGFloat {
        column.isWide ? wideStatWidth : statWidth
    }

    private func accessibilityLabel(_ row: RankedStandingsEntry, teamName: String, columns: [StandingsColumn]) -> String {
        var parts = ["\(row.rank). \(teamName)"]
        for column in columns {
            let value = column.value(for: row.entry)
            if value != "-" { parts.append("\(value) \(column.spokenName)") }
        }
        if let zone = row.entry.note?.description, style.isSoccer { parts.append(zone) }
        return parts.joined(separator: ", ")
    }
}
