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

    private var homeWinsSets: Int {
        guard let hLs = game.homeLinescores, let aLs = game.awayLinescores else { return 0 }
        return zip(hLs, aLs).filter { $0.0 > $0.1 }.count
    }

    private var awayWinsSets: Int {
        guard let hLs = game.homeLinescores, let aLs = game.awayLinescores else { return 0 }
        return zip(hLs, aLs).filter { $0.1 > $0.0 }.count
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                matchHeader
                gameInfo
                actionsRow
                setScoresSection
                headToHeadSection
            }
            .padding()
        }
        .navigationTitle(league?.leagueName ?? "Match Details")
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
                VStack(spacing: 4) {
                    Text(game.strHomeTeam)
                        .font(.title3)
                        .fontWeight(homeWinsSets >= awayWinsSets ? .bold : .regular)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    HStack(spacing: 12) {
                        Text("\(homeWinsSets)")
                            .font(.system(size: 32, weight: homeWinsSets > awayWinsSets ? .heavy : .regular))
                            .foregroundColor(homeWinsSets > awayWinsSets ? .primary : .secondary)
                        Text("-")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.secondary)
                        Text("\(awayWinsSets)")
                            .font(.system(size: 32, weight: awayWinsSets > homeWinsSets ? .heavy : .regular))
                            .foregroundColor(awayWinsSets > homeWinsSets ? .primary : .secondary)
                    }
                    if let status = game.strStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(spacing: 4) {
                    Text(game.strAwayTeam)
                        .font(.title3)
                        .fontWeight(awayWinsSets >= homeWinsSets ? .bold : .regular)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            if let progress = game.strProgress {
                Text(progress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
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
                Text(date.formatted(.dateTime.month().day().year().hour().minute()))
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
        if let homeLs = game.homeLinescores, let awayLs = game.awayLinescores,
           !homeLs.isEmpty, !awayLs.isEmpty {
            let setCount = max(homeLs.count, awayLs.count)
            let labels = (1...setCount).map { "S\($0)" }

            VStack(alignment: .leading, spacing: 12) {
                Text("Set Scores")
                    .font(.headline)

                VStack(spacing: 6) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("")
                            .frame(width: 100, alignment: .leading)
                        ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .frame(width: 36, alignment: .center)
                        }
                        Text("Sets")
                            .frame(width: 40, alignment: .center)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    Divider()

                    // Home player row
                    HStack(spacing: 0) {
                        Text(abbreviatedName(game.strHomeTeam))
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(1)
                        ForEach(0..<setCount, id: \.self) { i in
                            let score = i < homeLs.count ? homeLs[i] : nil
                            let opScore = i < awayLs.count ? awayLs[i] : nil
                            let wonSet = score != nil && opScore != nil && score! > opScore!
                            Text(score.map { formatScore($0) } ?? "-")
                                .fontWeight(wonSet ? .bold : .regular)
                                .foregroundColor(wonSet ? .primary : .secondary)
                                .frame(width: 36, alignment: .center)
                        }
                        Text("\(homeWinsSets)")
                            .fontWeight(homeWinsSets > awayWinsSets ? .bold : .regular)
                            .frame(width: 40, alignment: .center)
                    }
                    .font(.caption)

                    // Away player row
                    HStack(spacing: 0) {
                        Text(abbreviatedName(game.strAwayTeam))
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(1)
                        ForEach(0..<setCount, id: \.self) { i in
                            let score = i < awayLs.count ? awayLs[i] : nil
                            let opScore = i < homeLs.count ? homeLs[i] : nil
                            let wonSet = score != nil && opScore != nil && score! > opScore!
                            Text(score.map { formatScore($0) } ?? "-")
                                .fontWeight(wonSet ? .bold : .regular)
                                .foregroundColor(wonSet ? .primary : .secondary)
                                .frame(width: 36, alignment: .center)
                        }
                        Text("\(awayWinsSets)")
                            .fontWeight(awayWinsSets > homeWinsSets ? .bold : .regular)
                            .frame(width: 40, alignment: .center)
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 4)
            }
            .padding()
            .background(Color.secondaryGroupedBackground)
            .cornerRadius(12)
        }
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

                ForEach(matchups.prefix(10), id: \.id) { m in
                    HStack {
                        if let date = m.standardDate {
                            Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                        }
                        Spacer()
                        Text(abbreviatedName(m.strHomeTeam))
                            .font(.caption)
                            .lineLimit(1)
                        Text("\(m.intHomeScore ?? "-")")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 24)
                        Text("-")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(m.intAwayScore ?? "-")")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 24)
                        Text(abbreviatedName(m.strAwayTeam))
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

    // MARK: - Helpers

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

    private struct Record { let homeWins: Int; let awayWins: Int }

    private func computeRecord(matchups: [Game]) -> Record {
        var homeWins = 0, awayWins = 0
        let home = game.strHomeTeam
        for m in matchups {
            guard let hs = Int(m.intHomeScore ?? ""), let as_ = Int(m.intAwayScore ?? "") else { continue }
            if (m.strHomeTeam == home && hs > as_) || (m.strAwayTeam == home && as_ > hs) {
                homeWins += 1
            } else if hs != as_ {
                awayWins += 1
            }
        }
        return Record(homeWins: homeWins, awayWins: awayWins)
    }

    private func abbreviatedName(_ fullName: String) -> String {
        let parts = fullName.components(separatedBy: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return fullName }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }

    private func formatScore(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = "\(game.strHomeTeam) vs \(game.strAwayTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 3)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}
