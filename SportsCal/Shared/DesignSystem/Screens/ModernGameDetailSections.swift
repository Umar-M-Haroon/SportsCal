//
//  ModernGameDetailSections.swift
//  SportsCal — Design System v1.0
//
//  Modern-themed counterpart to `GameDetailSections`. Same data layout (playoff
//  series, box score, momentum, key players, play-by-play, injuries,
//  head-to-head, standings) but rendered with Modern design tokens — `appCard`
//  surfaces, `appEyebrow` section labels, monospaced numerics, sport-tinted
//  accents — so it sits cleanly inside `ModernGameDetailView` without bringing
//  classic-theme chrome along.
//

import SwiftUI
import SportsCalModel

struct ModernGameDetailSections: View {
    let game: Game
    let homeTeam: Team
    let awayTeam: Team
    let league: Leagues?
    let sportType: SportType?
    let model: GameDetailSectionsModel

    @Environment(GameViewModel.self) private var viewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager
    #if os(iOS)
    @Environment(NativeAdManager.self) private var adManager
    #endif

    /// Sport accent — falls back to basketball when the game's sport is
    /// unknown so accent strokes never collapse to a system gray.
    private var accent: Color { Color.app(sportType ?? .basketball) }

    var body: some View {
        VStack(spacing: .appSpace5) {
            playoffSeriesSection
            boxScoreSection
            momentumChartSection
            keyPlayersSection
            playByPlaySection
            injuriesSection
            headToHeadSection
            #if os(iOS)
            if !subscriptionManager.isPro && AdConfiguration.isEnabled,
               let ad = adManager.adForSlot(0) {
                NativeAdCardView(nativeAd: ad)
                    .padding(.horizontal, .appSpace4)
            }
            #endif
            standingsSection
        }
    }

    // MARK: - Playoff series

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
        VStack(alignment: .leading, spacing: .appSpace2) {
            HStack(alignment: .firstTextBaseline) {
                Text((playoff.seriesTitle ?? "Postseason").uppercased())
                    .appEyebrow()
                    .foregroundStyle(accent)
                Spacer()
                if let best = playoff.bestOf {
                    Text("BEST OF \(best)")
                        .appEyebrow()
                        .foregroundStyle(Color.appInkFaint)
                }
            }

            if let home = playoff.homeWins, let away = playoff.awayWins,
               let best = playoff.bestOf {
                seriesDots(homeWins: home, awayWins: away, bestOf: best)
                Text(seriesStatusText(homeWins: home, awayWins: away,
                                      seriesCompleted: playoff.seriesCompleted ?? false))
                    .font(.appHeadline)
                    .foregroundStyle(Color.appInk)
            }

            if let gameNumber = playoff.gameNumber, gameNumber > 0 {
                Text("Game \(gameNumber)" + (playoff.bestOf.map { " of \($0)" } ?? ""))
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkSoft)
            }

            if playoff.isNeutralSite == true {
                let label = game.venueName.map { "Neutral site · \($0)" } ?? "Neutral site"
                Label(label, systemImage: "mappin.circle")
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(fill: Color.appAlt)
    }

    @ViewBuilder
    private func playoffMinimalSection(title: String) -> some View {
        HStack(spacing: .appSpace2) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(Color.appStar)
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(Color.appInk)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(fill: Color.appAlt)
    }

    @ViewBuilder
    private func seriesDots(homeWins: Int, awayWins: Int, bestOf: Int) -> some View {
        let played = homeWins + awayWins
        HStack(spacing: 6) {
            ForEach(0..<bestOf, id: \.self) { index in
                Circle()
                    .fill(fillForSeriesDot(index: index, awayWins: awayWins, played: played))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func fillForSeriesDot(index: Int, awayWins: Int, played: Int) -> Color {
        if index < awayWins {
            return Color(hex: game.awayTeamColor ?? "") ?? accent
        }
        if index < played {
            return Color(hex: game.homeTeamColor ?? "") ?? accent
        }
        return Color.appDivider
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

    // MARK: - Box score

    @ViewBuilder
    private var boxScoreSection: some View {
        if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
           !homeLs.isEmpty, !awayLs.isEmpty {
            let periodCount = max(homeLs.count, awayLs.count)
            let labels = game.periodLabels(count: periodCount)
            let homeTotal = homeLs.reduce(0, +)
            let awayTotal = awayLs.reduce(0, +)

            VStack(alignment: .leading, spacing: .appSpace3) {
                Text("BOX SCORE").appEyebrow().foregroundStyle(accent)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: .appSpace1) {
                        boxScoreHeader(labels: labels)
                        Rectangle()
                            .fill(Color.appDivider)
                            .frame(height: 1)
                        boxScoreRow(
                            teamShort: Team.shortCode(strTeamShort: awayTeam.strTeamShort, name: game.strAwayTeam),
                            line: awayLs,
                            otherCount: homeLs.count,
                            total: awayTotal,
                            isLeader: awayTotal > homeTotal
                        )
                        boxScoreRow(
                            teamShort: Team.shortCode(strTeamShort: homeTeam.strTeamShort, name: game.strHomeTeam),
                            line: homeLs,
                            otherCount: awayLs.count,
                            total: homeTotal,
                            isLeader: homeTotal > awayTotal
                        )
                    }
                    .padding(.horizontal, .appSpace1)
                }
            }
            .appCard(fill: Color.appAlt)
        }
    }

    private func boxScoreHeader(labels: [String]) -> some View {
        HStack(spacing: 0) {
            Text("").frame(width: 60, alignment: .leading)
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .frame(width: 36, alignment: .center)
            }
            Text("T").frame(width: 40, alignment: .center)
        }
        .font(.appFootnote)
        .foregroundStyle(Color.appInkFaint)
    }

    private func boxScoreRow(teamShort: String, line: [Double], otherCount: Int, total: Double, isLeader: Bool) -> some View {
        HStack(spacing: 0) {
            Text(teamShort)
                .frame(width: 60, alignment: .leading)
                .lineLimit(1)
                .foregroundStyle(isLeader ? accent : Color.appInk)
                .font(.appCaption)
            ForEach(Array(line.enumerated()), id: \.offset) { _, score in
                Text(formatLinescoreValue(score))
                    .frame(width: 36, alignment: .center)
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkSoft)
            }
            ForEach(0..<max(0, otherCount - line.count), id: \.self) { _ in
                Text("-")
                    .frame(width: 36, alignment: .center)
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkFaint)
            }
            Text(formatLinescoreValue(total))
                .frame(width: 40, alignment: .center)
                .font(.appCaption)
                .fontWeight(isLeader ? .bold : .regular)
                .foregroundStyle(isLeader ? accent : Color.appInk)
        }
    }

    private func formatLinescoreValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }

    // MARK: - Momentum

    @ViewBuilder
    private var momentumChartSection: some View {
        if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
           !homeLs.isEmpty, !awayLs.isEmpty,
           game.intHomeScore != nil {
            VStack(alignment: .leading, spacing: .appSpace2) {
                Text("MOMENTUM").appEyebrow().foregroundStyle(accent)
                MomentumChartView(
                    game: game,
                    homeTeamName: homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam,
                    awayTeamName: awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam,
                    plays: model.plays
                )
            }
            .appCard(fill: Color.appAlt)
        }
    }

    // MARK: - Key players

    @ViewBuilder
    private var keyPlayersSection: some View {
        if let homeLeaders = game.homeLeaders, let awayLeaders = game.awayLeaders,
           !homeLeaders.isEmpty, !awayLeaders.isEmpty {
            let categories = matchedLeaderCategories(away: awayLeaders, home: homeLeaders)

            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: .appSpace3) {
                    Text("KEY PLAYERS").appEyebrow().foregroundStyle(accent)

                    ForEach(Array(categories.enumerated()), id: \.offset) { idx, pair in
                        VStack(spacing: .appSpace2) {
                            Text(pair.categoryDisplay.uppercased())
                                .font(.appFootnote)
                                .foregroundStyle(Color.appInkFaint)
                                .frame(maxWidth: .infinity)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pair.awayLeader.playerName)
                                        .font(.appHeadline)
                                        .lineLimit(1)
                                    Text(pair.awayLeader.displayValue)
                                        .font(.appCaption)
                                        .foregroundStyle(accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(pair.homeLeader.playerName)
                                        .font(.appHeadline)
                                        .lineLimit(1)
                                    Text(pair.homeLeader.displayValue)
                                        .font(.appCaption)
                                        .foregroundStyle(accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }

                        if idx < categories.count - 1 {
                            Rectangle()
                                .fill(Color.appDivider)
                                .frame(height: 1)
                        }
                    }
                }
                .appCard(fill: Color.appAlt)
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
        // Dedup both sides by category first so a category that appears twice
        // in ESPN's payload yields one row, not two.
        let awayDeduped = away.dedupedByCategory()
        let homeDeduped = home.dedupedByCategory()
        return awayDeduped.compactMap { awayLeader in
            guard let homeLeader = homeDeduped.first(where: { $0.category == awayLeader.category }) else { return nil }
            return LeaderPair(category: awayLeader.category, categoryDisplay: awayLeader.categoryDisplay,
                              awayLeader: awayLeader, homeLeader: homeLeader)
        }
    }

    // MARK: - Play-by-play

    private var supportsPlayByPlay: Bool {
        switch sportType {
        case .basketball, .nfl, .hockey, .mlb, .soccer: return true
        default: return false
        }
    }

    private var availablePeriods: [Int] {
        Array(Set(model.plays.compactMap { $0.period?.number })).sorted()
    }

    private var playsInSelectedPeriod: [Play] {
        guard let selected = model.selectedPeriod else { return model.plays }
        return model.plays.filter { $0.period?.number == selected }
    }

    @ViewBuilder
    private var playByPlaySection: some View {
        if supportsPlayByPlay, game.idEvent != nil {
            VStack(alignment: .leading, spacing: .appSpace3) {
                HStack {
                    Text("PLAY-BY-PLAY").appEyebrow().foregroundStyle(accent)
                    Spacer()
                    if model.playsLoading {
                        ProgressView().controlSize(.small)
                    } else if !model.plays.isEmpty {
                        Text("\(model.plays.count) plays")
                            .font(.appCaption)
                            .foregroundStyle(Color.appInkFaint)
                    }
                }

                if !model.playsAvailable && model.plays.isEmpty {
                    placeholder("Play-by-play not available yet")
                } else if model.plays.isEmpty && !model.playsLoading {
                    placeholder("Loading plays…")
                } else {
                    periodPicker

                    let visible = playsInSelectedPeriod
                    if visible.isEmpty {
                        placeholder("No plays recorded for this period")
                    } else {
                        LazyVStack(alignment: .leading, spacing: .appSpace2) {
                            ForEach(Array(visible.enumerated()), id: \.offset) { _, play in
                                playRow(play)
                            }
                        }
                    }
                }
            }
            .appCard(fill: Color.appAlt)
            .onChange(of: model.plays) { _, newPlays in
                let newAvailable = Set(newPlays.compactMap { $0.period?.number })
                if let current = model.selectedPeriod, newAvailable.contains(current) { return }
                model.selectedPeriod = newAvailable.max()
            }
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
                                .font(.appFootnote)
                                .foregroundStyle(isSelected ? Color.appBackground : Color.appInk)
                                .padding(.horizontal, .appSpace3)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected ? accent : Color.appDivider,
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
        HStack(alignment: .top, spacing: .appSpace3) {
            if let clockText = play.clock?.displayValue, !clockText.isEmpty {
                Text(clockText)
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkFaint)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let text = play.text {
                    Text(text)
                        .font(.appCaption)
                        .foregroundStyle(play.scoringPlay == true ? Color.appInk : Color.appInkSoft)
                        .fontWeight(play.scoringPlay == true ? .semibold : .regular)
                }
                if play.scoringPlay == true,
                   let away = play.awayScore, let home = play.homeScore {
                    Text("\(away) – \(home)")
                        .font(.appFootnote)
                        .foregroundStyle(accent)
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

    // MARK: - Injuries

    @ViewBuilder
    private var injuriesSection: some View {
        let home = game.homeInjuries ?? []
        let away = game.awayInjuries ?? []
        if !game.isIndividualSport, !(home.isEmpty && away.isEmpty) {
            VStack(alignment: .leading, spacing: .appSpace3) {
                Text("INJURY REPORT").appEyebrow().foregroundStyle(accent)

                HStack(alignment: .top, spacing: .appSpace3) {
                    injuryColumn(
                        teamName: awayTeam.strTeamShort ?? awayTeam.strTeam ?? game.strAwayTeam,
                        reports: away
                    )
                    Rectangle()
                        .fill(Color.appDivider)
                        .frame(width: 1)
                    injuryColumn(
                        teamName: homeTeam.strTeamShort ?? homeTeam.strTeam ?? game.strHomeTeam,
                        reports: home
                    )
                }
            }
            .appCard(fill: Color.appAlt)
        }
    }

    @ViewBuilder
    private func injuryColumn(teamName: String, reports: [InjuryReport]) -> some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text(teamName.uppercased())
                .font(.appFootnote)
                .foregroundStyle(Color.appInkFaint)
            if reports.isEmpty {
                Text("No reported injuries")
                    .font(.appCaption)
                    .foregroundStyle(Color.appInkSoft)
            } else {
                ForEach(Array(reports.prefix(6).enumerated()), id: \.offset) { _, report in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(report.playerName)
                                .font(.appCaption)
                                .foregroundStyle(Color.appInk)
                                .lineLimit(1)
                            if let position = report.position {
                                Text(position)
                                    .font(.appFootnote)
                                    .foregroundStyle(Color.appInkFaint)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(report.status.uppercased())
                                .font(.appFootnote)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(injuryStatusColor(report.status).opacity(0.18))
                                .foregroundStyle(injuryStatusColor(report.status))
                                .clipShape(RoundedRectangle.appShape(.appRadiusXS))
                            if let detail = report.detail {
                                Text(detail)
                                    .font(.appFootnote)
                                    .foregroundStyle(Color.appInkSoft)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                if reports.count > 6 {
                    Text("+\(reports.count - 6) more")
                        .font(.appFootnote)
                        .foregroundStyle(Color.appInkFaint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func injuryStatusColor(_ status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("out") || lower.contains("ir") || lower.contains("season") {
            return Color.appNegative
        }
        if lower.contains("question") || lower.contains("doubt") {
            return Color.orange
        }
        if lower.contains("day") || lower.contains("probable") {
            return Color.appStar
        }
        return Color.appInkSoft
    }

    // MARK: - Head-to-head

    private var headToHeadSection: some View {
        VStack(alignment: .leading, spacing: .appSpace3) {
            Text("HEAD-TO-HEAD").appEyebrow().foregroundStyle(accent)

            let matchups = previousMatchups
            if matchups.isEmpty {
                placeholder("No previous matchups found")
            } else {
                let record = computeRecord(matchups: matchups)
                HStack {
                    Text(awayTeam.strTeamShort ?? awayTeam.strTeam ?? "Away")
                        .font(.appHeadline)
                    Text("\(record.awayWins)")
                        .font(.appHeadline)
                        .foregroundStyle(record.awayWins > record.homeWins ? accent : Color.appInkSoft)
                    Spacer()
                    if record.draws > 0 {
                        Text("Draws: \(record.draws)")
                            .font(.appCaption)
                            .foregroundStyle(Color.appInkSoft)
                        Spacer()
                    }
                    Text("\(record.homeWins)")
                        .font(.appHeadline)
                        .foregroundStyle(record.homeWins > record.awayWins ? accent : Color.appInkSoft)
                    Text(homeTeam.strTeamShort ?? homeTeam.strTeam ?? "Home")
                        .font(.appHeadline)
                }

                ForEach(matchups.prefix(10), id: \.id) { m in
                    matchupRow(m)
                }
            }
        }
        .appCard(fill: Color.appAlt)
    }

    private func matchupRow(_ m: Game) -> some View {
        HStack(spacing: 4) {
            if let date = m.standardDate {
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.appFootnote)
                    .foregroundStyle(Color.appInkFaint)
                    .frame(width: 96, alignment: .leading)
            }
            Spacer(minLength: 0)
            Text(m.strAwayTeam)
                .font(.appCaption)
                .foregroundStyle(Color.appInkSoft)
                .lineLimit(1)
            Text(m.intAwayScore ?? "-")
                .font(.appCaption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appInk)
                .frame(width: 24)
            Text("-")
                .font(.appCaption)
                .foregroundStyle(Color.appInkFaint)
            Text(m.intHomeScore ?? "-")
                .font(.appCaption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appInk)
                .frame(width: 24)
            Text(m.strHomeTeam)
                .font(.appCaption)
                .foregroundStyle(Color.appInkSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
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

    // MARK: - Standings

    @ViewBuilder
    private var standingsSection: some View {
        if !game.isIndividualSport {
            VStack(alignment: .leading, spacing: .appSpace3) {
                Text("STANDINGS").appEyebrow().foregroundStyle(accent)

                if model.standingsLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, .appSpace2)
                } else if let children = model.standing?.standings.children, !children.isEmpty {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        if let entries = child.standings?.entries, !entries.isEmpty {
                            standingsGroup(name: child.name, entries: entries)
                        }
                    }
                } else {
                    VStack(spacing: .appSpace2) {
                        Text(model.standingsErrorMessage ?? "Standings not available")
                            .font(.appCaption)
                            .foregroundStyle(Color.appInkSoft)
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
                                .font(.appCaption)
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, .appSpace2)
                }
            }
            .appCard(fill: Color.appAlt)
        }
    }

    private func standingsGroup(name: String?, entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name {
                Text(name.uppercased())
                    .font(.appFootnote)
                    .foregroundStyle(Color.appInkFaint)
            }

            HStack(spacing: 0) {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("W").frame(width: 32, alignment: .center)
                Text("L").frame(width: 32, alignment: .center)
                if league?.isSoccer == true {
                    Text("D").frame(width: 32, alignment: .center)
                    Text("Pts").frame(width: 36, alignment: .center)
                }
            }
            .font(.appFootnote)
            .foregroundStyle(Color.appInkFaint)

            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let isGameTeam = isTeamInGame(entry: entry)
                HStack(spacing: 0) {
                    Text("\(index + 1)").frame(width: 24, alignment: .leading)
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
                .font(.appCaption)
                .fontWeight(isGameTeam ? .bold : .regular)
                .foregroundStyle(isGameTeam ? accent : Color.appInkSoft)
            }
        }
        .padding(.vertical, .appSpace1)
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

    // MARK: - Shared placeholder

    private func placeholder(_ message: String) -> some View {
        Text(message)
            .font(.appCaption)
            .foregroundStyle(Color.appInkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, .appSpace2)
    }
}
