//
//  TennisMatchDetailView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel
#if os(iOS)
import EventKit
import EventKitUI
#endif

struct TennisMatchDetailView: View {
    let game: Game

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    @ScaledMetric(relativeTo: .caption) private var setColumnWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var nameColumnWidth: CGFloat = 110
    /// The players' meetings from the server's results archive (several seasons). Nil
    /// until it loads, or when it can't, and then the month of results the app holds
    /// stands in.
    @State private var archivedHeadToHead: TennisHeadToHead?

    private var league: Leagues? {
        guard let id = game.idLeague, let intID = Int(id) else { return nil }
        return Leagues(rawValue: intID)
    }

    private var sportType: SportType? {
        guard let league else { return nil }
        return SportType(league: league)
    }

    private var isLive: Bool {
        game.strStatus == "in"
    }

    /// Finished sets only — the set in play isn't anyone's yet.
    private var setsWon: (home: Int, away: Int) { game.tennisSetsWon }

    private var emphasizedSide: GameSituation.Side? {
        TennisMatchPresentation.emphasizedSide(game)
    }

    // MARK: - Body
    var body: some View {
        PinnedDetailLayout {
            matchHeader
            gameInfo
            actionsRow
        } details: {
            setScoresSection
            if let archivedHeadToHead {
                archivedHeadToHeadSection(archivedHeadToHead)
            } else {
                headToHeadSection
            }
        }
        .task(id: game.id) { await loadHeadToHead() }
        .navigationTitle(game.tournamentName ?? league?.leagueName ?? "Match Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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

    // MARK: - Match Header
    private var matchHeader: some View {
        VStack(spacing: 16) {
            HStack {
                if let sport = sportType {
                    Image(systemName: sport.systemImage)
                        .font(.title2)
                        .foregroundColor(sport.color)
                }
                if let round = game.round {
                    Text(round)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }

            // Player names and sets-won score
            HStack(alignment: .center) {
                playerHeader(side: .home, name: game.strHomeTeam, seed: game.tennisHomeSeed)

                VStack(spacing: 4) {
                    HStack(spacing: 12) {
                        Text("\(setsWon.home)")
                            .font(.largeTitle.weight(emphasizedSide == .home ? .heavy : .regular))
                            .foregroundColor(emphasizedSide == .away ? .secondary : .primary)
                        Text("-")
                            .font(.title.weight(.light))
                            .foregroundColor(.secondary)
                        Text("\(setsWon.away)")
                            .font(.largeTitle.weight(emphasizedSide == .away ? .heavy : .regular))
                            .foregroundColor(emphasizedSide == .home ? .secondary : .primary)
                    }
                    .monospacedDigit()
                    // The status once, under the score.
                    if let stoppage = game.tennisStoppageText {
                        TennisStoppageBadge(text: stoppage)
                    } else if let statusText = game.displayStatus {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TennisMatchPresentation.spokenScore(game).joined(separator: ", "))

                playerHeader(side: .away, name: game.strAwayTeam, seed: game.tennisAwaySeed)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func playerHeader(side: GameSituation.Side, name: String, seed: Int?) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if game.tennisServer == side {
                    TennisServeDot()
                }
                Text(name)
                    .font(.title3)
                    .fontWeight(emphasizedSide == side ? .bold : .regular)
                    .multilineTextAlignment(.center)
            }
            if let seed {
                Text("Seed \(seed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if game.tennisMatchWinner == side, let marker = game.tennisResultMarker {
                Text(marker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Game Info
    private var gameInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let sport = sportType {
                    Image(systemName: sport.systemImage)
                        .foregroundColor(sport.color)
                }
                if let tournament = game.tournamentName {
                    hubLink(tournament: tournament)
                } else if let leagueName = league?.leagueName {
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
            if let court = game.tennisCourt {
                Label(court, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    /// The tournament, linking to its hub (draw by day and round).
    private func hubLink(tournament: String) -> some View {
        NavigationLink {
            TournamentHubView(
                tournamentName: tournament,
                games: hubGames(tournament: tournament),
                shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                sheetType: $sheetType
            )
            .environment(viewModel)
            .environment(favorites)
        } label: {
            HStack(spacing: 4) {
                Text(tournament)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityHint("Opens the tournament")
    }

    private func hubGames(tournament: String) -> [Game] {
        (viewModel.gamesDict[.tennis] ?? viewModel.totalGames ?? [])
            .filter { $0.isTennisMatch && $0.tournamentName == tournament }
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

    // MARK: - Set Scores
    @ViewBuilder
    private var setScoresSection: some View {
        let sets = game.tennisSets
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set Scores")
                    .font(.headline)

                VStack(spacing: 6) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("")
                            .frame(width: nameColumnWidth, alignment: .leading)
                        ForEach(1...sets.count, id: \.self) { index in
                            Text("S\(index)")
                                .frame(width: setColumnWidth, alignment: .center)
                        }
                        Text("Sets")
                            .frame(width: setColumnWidth + 4, alignment: .center)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)

                    Divider()

                    setRow(side: .home, name: game.strHomeTeam, sets: sets, won: setsWon.home)
                    setRow(side: .away, name: game.strAwayTeam, sets: sets, won: setsWon.away)
                }
                .padding(.horizontal, 4)
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func setRow(side: GameSituation.Side, name: String, sets: [TennisSet], won: Int) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(abbreviatedName(name))
                    .lineLimit(1)
                if game.tennisServer == side {
                    TennisServeDot()
                }
            }
            .frame(width: nameColumnWidth, alignment: .leading)
            ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                let wonSet = set.winner == side
                Text(set.text(for: side))
                    .fontWeight(wonSet ? .bold : .regular)
                    .foregroundColor(wonSet || !set.isComplete ? .primary : .secondary)
                    .frame(width: setColumnWidth, alignment: .center)
            }
            Text("\(won)")
                .fontWeight(emphasizedSide == side ? .bold : .regular)
                .frame(width: setColumnWidth + 4, alignment: .center)
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(won) \(won == 1 ? "set" : "sets"), \(sets.map { $0.text(for: side) }.joined(separator: ", "))")
    }

    // MARK: - Head-to-Head

    /// Singles only: doubles pairs have no athlete id to look up.
    private var headToHeadIDs: (player: String, opponent: String)? {
        guard game.isTennisMatch, !game.isTennisDoubles,
              let home = game.idHomeTeam, let away = game.idAwayTeam, home != away,
              [home, away].allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && $0 != "0" }) else { return nil }
        return (home, away)
    }

    private func loadHeadToHead() async {
        guard let ids = headToHeadIDs else { return }
        archivedHeadToHead = try? await NetworkHandler.fetchTennisHeadToHead(player: ids.player, opponent: ids.opponent)
    }

    /// Every meeting since the archive's first season; this match itself is left out
    /// once it's finished, so the record is what they brought into it.
    private func archivedHeadToHeadSection(_ h2h: TennisHeadToHead) -> some View {
        let meetings = h2h.meetings.filter { $0.id != game.idEvent }
        let counted = meetings.filter { $0.marker != "w/o" }
        let homeWins = counted.filter { $0.winnerID == h2h.playerID }.count
        let awayWins = counted.filter { $0.winnerID == h2h.opponentID }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Head-to-Head")
                .font(.headline)

            if meetings.isEmpty {
                Text("First meeting on tour since \(String(h2h.since))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(abbreviatedName(game.strHomeTeam))
                        .fontWeight(.semibold)
                    Text("\(homeWins)")
                        .foregroundColor(homeWins > awayWins ? .primary : .secondary)
                    Spacer()
                    Text("\(awayWins)")
                        .foregroundColor(awayWins > homeWins ? .primary : .secondary)
                    Text(abbreviatedName(game.strAwayTeam))
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .monospacedDigit()
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Head to head: \(game.strHomeTeam) \(homeWins), \(game.strAwayTeam) \(awayWins)")

                ForEach(meetings.prefix(10)) { meeting in
                    archivedMeetingRow(meeting, playerID: h2h.playerID)
                }
                Text("Tour-level main draws since \(String(h2h.since)). Walkovers aren't counted.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    private func archivedMeetingRow(_ meeting: TennisMeeting, playerID: String) -> some View {
        let winnerName = meeting.winnerID == meeting.homeID ? meeting.homeName : (meeting.winnerID == meeting.awayID ? meeting.awayName : nil)
        let round = meeting.round.map(TennisDrawBracket.shortLabel(ofRound:))
        let date = meeting.day?.formatted(.dateTime.month(.abbreviated).year())
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text([meeting.tournament, round].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .lineLimit(1)
                if let date {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let winnerName {
                Text(abbreviatedName(winnerName))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(meeting.scoreText(from: meeting.winnerID ?? playerID))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([meeting.tournament, round, date, winnerName.map { "\($0) won" },
                             meeting.scoreText(from: meeting.winnerID ?? playerID)]
            .compactMap { $0 }.joined(separator: ", "))
    }

    /// Earlier meetings in the schedule the app holds (about a month of results). Hidden
    /// when there are none, rather than claiming they've never met.
    @ViewBuilder
    private var headToHeadSection: some View {
        let matchups = previousMatchups
        if !matchups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Meetings")
                    .font(.headline)

                let record = computeRecord(matchups: matchups)
                HStack {
                    Text(abbreviatedName(game.strHomeTeam))
                        .fontWeight(.semibold)
                    Text("\(record.homeWins)")
                        .foregroundColor(record.homeWins > record.awayWins ? .primary : .secondary)
                    Spacer()
                    Text("\(record.awayWins)")
                        .foregroundColor(record.awayWins > record.homeWins ? .primary : .secondary)
                    Text(abbreviatedName(game.strAwayTeam))
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(game.strHomeTeam) \(record.homeWins), \(game.strAwayTeam) \(record.awayWins)")

                ForEach(matchups.prefix(10), id: \.id) { m in
                    meetingRow(m)
                }
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
    }

    private func meetingRow(_ m: Game) -> some View {
        let sets = m.tennisSets
        let won = m.tennisSetsWon
        let winner = m.tennisMatchWinner
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                if let date = m.standardDate {
                    Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let tournament = m.tournamentName {
                    Text([tournament, m.shortRoundLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 120, alignment: .leading)
            Spacer()
            Text(abbreviatedName(m.strHomeTeam))
                .font(.caption)
                .fontWeight(winner == .home ? .semibold : .regular)
                .lineLimit(1)
            Text("\(won.home)-\(won.away)")
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
            Text(abbreviatedName(m.strAwayTeam))
                .font(.caption)
                .fontWeight(winner == .away ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meetingLabel(m, sets: sets))
    }

    private func meetingLabel(_ m: Game, sets: [TennisSet]) -> String {
        let winnerName = m.tennisMatchWinner.map { $0 == .home ? m.strHomeTeam : m.strAwayTeam }
        let date = m.standardDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        return [date, m.tournamentName, winnerName.map { "\($0) won" }, sets.map(\.spokenText).joined(separator: ", ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: - Helpers

    /// Finished meetings between the two, newest first. Tennis has no `intHomeScore`,
    /// so a result is read from its sets (or ESPN's winner, for a retirement).
    private var previousMatchups: [Game] {
        guard let allGames = viewModel.totalGames else { return [] }
        let home = game.strHomeTeam
        let away = game.strAwayTeam
        return allGames.filter { g in
            g.id != game.id && g.isTennisMatch && g.isTennisMatchOver && g.tennisMatchWinner != nil &&
            ((g.strHomeTeam == home && g.strAwayTeam == away) ||
             (g.strHomeTeam == away && g.strAwayTeam == home))
        }
        .sorted { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }
    }

    private struct Record { let homeWins: Int; let awayWins: Int }

    private func computeRecord(matchups: [Game]) -> Record {
        var homeWins = 0, awayWins = 0
        let home = game.strHomeTeam
        for m in matchups {
            guard let winner = m.tennisMatchWinner else { continue }
            let winnerName = winner == .home ? m.strHomeTeam : m.strAwayTeam
            if winnerName == home { homeWins += 1 } else { awayWins += 1 }
        }
        return Record(homeWins: homeWins, awayWins: awayWins)
    }

    private func abbreviatedName(_ fullName: String) -> String {
        // Doubles pairs ("A. Name / B. Name") are already short.
        guard !fullName.contains("/") else { return fullName }
        let parts = fullName.components(separatedBy: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return fullName }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        let matchup = "\(game.strHomeTeam) vs \(game.strAwayTeam)"
        // "Sinner vs Alcaraz · Wimbledon QF"
        let context = [game.tournamentName, game.shortRoundLabel].compactMap { $0 }.joined(separator: " ")
        event.title = context.isEmpty ? matchup : "\(matchup) · \(context)"
        event.location = game.tennisCourt
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 3)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}
