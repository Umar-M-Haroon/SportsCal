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

    @State private var standing: Standing?
    @State private var standingsLoading = true
    @State private var standingsErrorMessage: String?

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
        ScrollView {
            VStack(spacing: 24) {
                gameHeader
                gameInfo
                actionsRow
                playoffSeriesSection
                boxScoreSection
                momentumChartSection
                keyPlayersSection
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
            .padding()
        }
        .navigationTitle(league?.leagueName ?? "Game Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadStandings()
            if !game.isIndividualSport,
               !favorites.contains(game),
               let sportType {
                engagementTracker.recordView(team: game.strHomeTeam, sport: sportType)
                engagementTracker.recordView(team: game.strAwayTeam, sport: sportType)
            }
        }
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

    // MARK: - Game Header
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

            if let progress = game.strProgress {
                Text(progress)
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
                if let status = game.strStatus {
                    Text(status)
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
            Text(game.strStatus ?? "TBD")
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
                Text(String(name.prefix(3)))
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

    // MARK: - Game Info
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

    // MARK: - Actions Row
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

    // MARK: - Auto-Follow Action
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

    // MARK: - Playoff Series
    @ViewBuilder
    private var playoffSeriesSection: some View {
        if let playoff = game.playoff {
            playoffRichSection(playoff: playoff)
        } else if let fallbackTitle = fallbackPlayoffTitle {
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

    private var fallbackPlayoffTitle: String? { game.fallbackPostseasonTitle }

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
        // Wins so far are ordered as opaque dots: away wins first, then home wins.
        // Remaining dots (scheduled but unplayed) are shown dimmed.
        if index < awayWins {
            return Color(hex: game.awayTeamColor ?? "") ?? .accentColor
        }
        if index < played {
            return Color(hex: game.homeTeamColor ?? "") ?? .accentColor
        }
        return Color.secondary.opacity(0.25)
    }

    private func seriesStatusText(homeWins: Int, awayWins: Int, seriesCompleted: Bool) -> String {
        let homeShort = homeTeam.strTeamShort ?? String(game.strHomeTeam.prefix(3)).uppercased()
        let awayShort = awayTeam.strTeamShort ?? String(game.strAwayTeam.prefix(3)).uppercased()
        if seriesCompleted {
            if homeWins > awayWins { return "\(homeShort) win series \(homeWins)-\(awayWins)" }
            if awayWins > homeWins { return "\(awayShort) win series \(awayWins)-\(homeWins)" }
            return "Series tied \(homeWins)-\(awayWins)"
        }
        if homeWins == awayWins { return "Series tied \(homeWins)-\(awayWins)" }
        if homeWins > awayWins { return "\(homeShort) lead \(homeWins)-\(awayWins)" }
        return "\(awayShort) lead \(awayWins)-\(homeWins)"
    }

    // MARK: - Box Score
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
                        // Header row
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

                        // Away team row
                        HStack(spacing: 0) {
                            Text(awayTeam.strTeamShort ?? String(game.strAwayTeam.prefix(3)).uppercased())
                                .frame(width: 60, alignment: .leading)
                                .lineLimit(1)
                            ForEach(Array(awayLs.enumerated()), id: \.offset) { _, score in
                                Text(formatLinescoreValue(score))
                                    .frame(width: 36, alignment: .center)
                            }
                            // Pad if fewer periods than home
                            ForEach(0..<max(0, homeLs.count - awayLs.count), id: \.self) { _ in
                                Text("-")
                                    .frame(width: 36, alignment: .center)
                            }
                            Text(formatLinescoreValue(awayTotal))
                                .fontWeight(awayTotal > homeTotal ? .bold : .regular)
                                .frame(width: 40, alignment: .center)
                        }
                        .font(.caption)

                        // Home team row
                        HStack(spacing: 0) {
                            Text(homeTeam.strTeamShort ?? String(game.strHomeTeam.prefix(3)).uppercased())
                                .frame(width: 60, alignment: .leading)
                                .lineLimit(1)
                            ForEach(Array(homeLs.enumerated()), id: \.offset) { _, score in
                                Text(formatLinescoreValue(score))
                                    .frame(width: 36, alignment: .center)
                            }
                            // Pad if fewer periods than away
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

    // MARK: - Momentum Chart
    @ViewBuilder
    private var momentumChartSection: some View {
        if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
           !homeLs.isEmpty, !awayLs.isEmpty,
           game.intHomeScore != nil {
            MomentumChartView(
                game: game,
                homeTeamName: homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam,
                awayTeamName: awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam
            )
        }
    }

    // MARK: - Key Players
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
                                // Away leader
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

                                // Home leader
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

    // MARK: - Injuries
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

    // MARK: - Head-to-Head
    private var headToHeadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Head-to-Head")
                .font(.headline)

            let matchups = previousMatchups
            if matchups.isEmpty {
                Text("No previous matchups found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
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
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
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

    // MARK: - Standings
    @ViewBuilder
    private var standingsSection: some View {
        if !game.isIndividualSport {
            VStack(alignment: .leading, spacing: 12) {
                Text("Standings")
                    .font(.headline)

                if standingsLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else if let children = standing?.standings.children, !children.isEmpty {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        if let entries = child.standings?.entries, !entries.isEmpty {
                            standingsGroup(name: child.name, entries: entries)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Text(standingsErrorMessage ?? "Standings not available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button {
                            standingsLoading = true
                            standingsErrorMessage = nil
                            Task { await loadStandings() }
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

            // Header row
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

    private func loadStandings() async {
        guard !game.isIndividualSport else {
            standingsLoading = false
            return
        }
        guard let leagueID = game.idLeague else {
            standingsLoading = false
            standingsErrorMessage = "League information missing for this game"
            return
        }
        do {
            standing = try await NetworkHandler.getStandings(for: leagueID, debug: viewModel.appStorage.debugMode)
            standingsLoading = false
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
}
