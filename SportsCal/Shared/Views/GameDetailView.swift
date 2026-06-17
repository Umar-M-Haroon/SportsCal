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

    var worldCupBoxScore: WorldCupBoxScore?
    var boxScoreLoading = false

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
                eventID: eventID, sport: sport, league: league
            )
            plays = cached.plays
            playsAvailable = true
        } catch is NetworkHandler.PlayByPlayNotAvailable {
            plays = []
            playsAvailable = false
        } catch {
            // Silent failure — keep any plays we already have.
            playsAvailable = plays.isEmpty == false
        }
    }

    func loadWorldCupBoxScore(eventID: String) async {
        boxScoreLoading = true
        defer { boxScoreLoading = false }
        do {
            worldCupBoxScore = try await NetworkHandler.getWorldCupBoxScore(eventID: eventID)
        } catch is NetworkHandler.BoxScoreNotAvailable {
            worldCupBoxScore = nil
        } catch {
            // Silent failure — keep any box score we already have.
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
        case .nfl:        return "nfl"
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
                teamBadge(url: awayTeam.strTeamBadge, name: awayTeam.strTeamShort ?? awayTeam.strTeam, size: 60)
                Spacer()
                scoreOrTime
                Spacer()
                teamBadge(url: homeTeam.strTeamBadge, name: homeTeam.strTeamShort ?? homeTeam.strTeam, size: 60)
            }

            HStack {
                Text(awayTeam.strTeam ?? "Away")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                Spacer()
                Text(homeTeam.strTeam ?? "Home")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }

            if let statusText = game.displayStatus {
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

    @ViewBuilder
    private var scoreOrTime: some View {
        if let homeScore = game.intHomeScore, let awayScore = game.intAwayScore,
           let home = Int(homeScore), let away = Int(awayScore) {
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
        .padding(.horizontal, 4)
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

    var body: some View {
        VStack(spacing: 24) {
            playoffSeriesSection
            boxScoreSection
            worldCupBoxScoreSection
            momentumChartSection
            keyPlayersSection
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
            await reloadBoxScore()
        }
        .onChange(of: game.lastPlay) { _, _ in
            Task { await reloadPlays() }
            Task { await reloadBoxScore() }
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
                                .frame(width: 60, alignment: .leading)
                            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                                Text(label)
                                    .frame(width: 36, alignment: .center)
                            }
                            Text("T")
                                .frame(width: 40, alignment: .center)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        Divider()

                        HStack(spacing: 0) {
                            Text(Team.shortCode(strTeamShort: awayTeam.strTeamShort, name: game.strAwayTeam))
                                .frame(width: 60, alignment: .leading)
                                .lineLimit(1)
                            ForEach(Array(awayLs.enumerated()), id: \.offset) { _, score in
                                Text(formatLinescoreValue(score))
                                    .frame(width: 36, alignment: .center)
                            }
                            ForEach(0..<max(0, homeLs.count - awayLs.count), id: \.self) { _ in
                                Text("-")
                                    .frame(width: 36, alignment: .center)
                            }
                            Text(formatLinescoreValue(awayTotal))
                                .fontWeight(awayTotal > homeTotal ? .bold : .regular)
                                .frame(width: 40, alignment: .center)
                        }
                        .font(.caption)

                        HStack(spacing: 0) {
                            Text(Team.shortCode(strTeamShort: homeTeam.strTeamShort, name: game.strHomeTeam))
                                .frame(width: 60, alignment: .leading)
                                .lineLimit(1)
                            ForEach(Array(homeLs.enumerated()), id: \.offset) { _, score in
                                Text(formatLinescoreValue(score))
                                    .frame(width: 36, alignment: .center)
                            }
                            ForEach(0..<max(0, awayLs.count - homeLs.count), id: \.self) { _ in
                                Text("-")
                                    .frame(width: 36, alignment: .center)
                            }
                            Text(formatLinescoreValue(homeTotal))
                                .fontWeight(homeTotal > awayTotal ? .bold : .regular)
                                .frame(width: 40, alignment: .center)
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func formatLinescoreValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }

    // MARK: Momentum chart

    @ViewBuilder
    private var momentumChartSection: some View {
        if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
           !homeLs.isEmpty, !awayLs.isEmpty,
           game.intHomeScore != nil {
            MomentumChartView(
                game: game,
                homeTeamName: homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam,
                awayTeamName: awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam,
                plays: model.plays
            )
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
        let matchups = previousMatchups
        // Hide the section entirely when there are no prior meetings (e.g. World Cup
        // group-stage games) rather than showing an empty placeholder card.
        if !matchups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Head-to-Head")
                    .font(.headline)

                let record = computeRecord(matchups: matchups)
                HStack {
                    Text(awayTeam.strTeamShort ?? awayTeam.strTeam ?? "Away")
                        .fontWeight(.semibold)
                    Text("\(record.awayWins)")
                        .foregroundColor(record.awayWins > record.homeWins ? .primary : .secondary)
                    Spacer()
                    if record.draws > 0 {
                        Text("Draws: \(record.draws)")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Text("\(record.homeWins)")
                        .foregroundColor(record.homeWins > record.awayWins ? .primary : .secondary)
                    Text(homeTeam.strTeamShort ?? homeTeam.strTeam ?? "Home")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 4)

                ForEach(matchups.prefix(10), id: \.id) { m in
                    HStack {
                        if let date = m.standardDate {
                            Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
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
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private var previousMatchups: [Game] {
        guard let allGames = viewModel.totalGames else { return [] }
        let home = game.strHomeTeam
        let away = game.strAwayTeam
        return allGames.filter { g in
            g.id != game.id &&
            g.intHomeScore != nil && g.intAwayScore != nil &&
            ((g.strHomeTeam == home && g.strAwayTeam == away) ||
             (g.strHomeTeam == away && g.strAwayTeam == home))
        }
        .sorted { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }
    }

    private struct Record { let homeWins: Int; let awayWins: Int; let draws: Int }

    private func computeRecord(matchups: [Game]) -> Record {
        var homeWins = 0, awayWins = 0, draws = 0
        let home = game.strHomeTeam
        for m in matchups {
            guard let hs = Int(m.intHomeScore ?? ""), let as_ = Int(m.intAwayScore ?? "") else { continue }
            if hs == as_ {
                draws += 1
            } else if (m.strHomeTeam == home && hs > as_) || (m.strAwayTeam == home && as_ > hs) {
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
                Text("Standings")
                    .font(.headline)

                if model.standingsLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else if let children = model.standing?.standings.children, !children.isEmpty {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        if let entries = child.standings?.entries, !entries.isEmpty {
                            standingsGroup(name: child.name, entries: entries)
                        }
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
        VStack(alignment: .leading, spacing: 6) {
            if let name {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 24, alignment: .leading)
                Text("Team")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("W")
                    .frame(width: 32, alignment: .center)
                Text("L")
                    .frame(width: 32, alignment: .center)
                if league?.isSoccer == true {
                    Text("D")
                        .frame(width: 32, alignment: .center)
                    Text("Pts")
                        .frame(width: 36, alignment: .center)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let isGameTeam = isTeamInGame(entry: entry)
                HStack(spacing: 0) {
                    Text("\(index + 1)")
                        .frame(width: 24, alignment: .leading)
                    Text(entry.team?.shortDisplayName ?? entry.team?.displayName ?? "-")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(statValue(entry: entry, name: "wins"))
                        .frame(width: 32, alignment: .center)
                    Text(statValue(entry: entry, name: "losses"))
                        .frame(width: 32, alignment: .center)
                    if league?.isSoccer == true {
                        Text(statValue(entry: entry, name: "ties"))
                            .frame(width: 32, alignment: .center)
                        Text(statValue(entry: entry, name: "points"))
                            .frame(width: 36, alignment: .center)
                    }
                }
                .font(.caption)
                .fontWeight(isGameTeam ? .bold : .regular)
                .foregroundColor(isGameTeam ? .primary : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statValue(entry: Entry, name: String) -> String {
        guard let stats = entry.stats,
              let stat = stats.first(where: { $0.name == name }) else { return "-" }
        return stat.displayValue ?? (stat.value.map { "\(Int($0))" } ?? "-")
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
                        Text("\(model.plays.count) plays")
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

    private func reloadPlays() async {
        guard supportsPlayByPlay, let eventID = game.idEvent else { return }
        await model.loadPlays(
            eventID: eventID,
            sport: pbpSportPath,
            league: pbpLeagueSlug
        )
    }

    // MARK: World Cup box score

    private var isWorldCup: Bool { league == .FIFA_World_Cup }

    private func reloadBoxScore() async {
        guard isWorldCup, let eventID = game.idEvent else { return }
        await model.loadWorldCupBoxScore(eventID: eventID)
    }

    @ViewBuilder
    private var worldCupBoxScoreSection: some View {
        if isWorldCup, let box = model.worldCupBoxScore, !box.isEmpty {
            WorldCupBoxScoreView(boxScore: box, game: game)
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

    private func periodAbbreviation(_ period: Int) -> String {
        switch sportType {
        case .basketball, .nfl: return "Q\(period)"
        case .hockey: return period > 3 ? (period == 4 ? "OT" : "SO") : "P\(period)"
        case .mlb: return "\(period)"
        case .soccer:
            switch period {
            case 1: return "1H"
            case 2: return "2H"
            case 3: return "ET1"
            case 4: return "ET2"
            case 5: return "PEN"
            default: return "\(period)"
            }
        default: return "\(period)"
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
}

