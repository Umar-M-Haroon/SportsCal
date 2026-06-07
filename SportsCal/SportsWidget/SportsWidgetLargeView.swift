//
//  SportsWidgetLargeView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import SportsCalModel

struct SportsWidgetLargeView: View {
    var entry: Provider.Entry

    private var dayOffset: Int {
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.integer(forKey: "widgetDayOffset") ?? 0
    }

    private var displayDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header with day navigation
            HStack(spacing: 6) {
                Button(intent: NavigateDayIntent(dayOffset: dayOffset - 1)) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text(displayDate.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(WidgetTokens.live)
                    Text(displayDate.formatted(.dateTime.month(.abbreviated).day(.twoDigits)))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(WidgetTokens.ink)
                }

                Button(intent: NavigateDayIntent(dayOffset: dayOffset + 1)) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                if dayOffset != 0 {
                    Button(intent: NavigateDayIntent(dayOffset: 0)) {
                        Text("TODAY")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .tracking(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WidgetTokens.live)
                }

                Text("SCOREBOARD")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(WidgetTokens.inkFaint)
            }
            .padding(.horizontal, 4)

            // Interactive sport filter tabs (iOS only, allSports mode)
            #if os(iOS)
            if entry.configuration.sport == .allSports {
                WidgetSportTabBar(compact: false)
            }
            #endif

            // Multi-game grid (2x3 = 6 games)
            if let games = entry.game, !games.isEmpty {
                let displayGames = Array(games.prefix(6))
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    ForEach(displayGames) { game in
                        gameCellView(game: game)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 30, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(WidgetTokens.inkSoft)
                    Text("No upcoming games")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WidgetTokens.inkSoft)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }

            Spacer(minLength: 0)
            WidgetUpdatedLabel(date: entry.date)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 4)
        }
        .padding(8)
        .widgetURL(widgetDeepLink)
    }

    private var widgetDeepLink: URL? {
        guard let game = entry.game?.first, let id = game.idEvent else { return nil }
        return URL(string: "sportscal://game/\(id)")
    }

    @ViewBuilder
    private func gameCellView(game: Game) -> some View {
        if game.isRace {
            WidgetRaceCell(game: game, compact: false)
        } else if game.isIndividualSport {
            WidgetTournamentCell(game: game, compact: false)
        } else {
            LargeCompactGameCell(game: game, teams: entry.teams, images: entry.images)
        }
    }
}

// Larger compact cell for the large widget
struct LargeCompactGameCell: View {
    let game: Game
    let teams: [Team]
    let images: [String: Data]?

    private var sportType: SportType { game.sportType ?? .basketball }

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" && status != "not started" && status != "ns"
            && game.intHomeScore != nil && game.intAwayScore != nil
    }

    private var isGameCompleted: Bool {
        if game.isCompleted == true { return true }
        guard let status = game.strStatus?.lowercased() else { return false }
        return status == "ft" || status == "aet"
    }

    var body: some View {
        let accent = WidgetTokens.sport(sportType)
        VStack(spacing: 4) {
            // Sport icon header
            HStack(spacing: 4) {
                Image(systemName: sportType.widgetSystemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
                Spacer()
                // Time or status
                if let statusText = game.displayStatus {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(WidgetTokens.live)
                            .frame(width: 5, height: 5)
                        Text(statusText)
                            .font(.system(size: 9, design: .monospaced).weight(.semibold))
                            .foregroundStyle(WidgetTokens.live)
                    }
                } else if let gameDate = game.standardDate {
                    Text(gameDate.formatToTime() ?? "")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(WidgetTokens.inkSoft)
                }
                #if os(iOS)
                if isLive, let gameID = game.idEvent {
                    Button(intent: FollowGameIntent(gameID: gameID, homeTeam: game.strHomeTeam, awayTeam: game.strAwayTeam)) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 11))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }

            // Teams row with scores
            HStack(spacing: 6) {
                teamColumn(teamID: game.idAwayTeam, teamName: game.strAwayTeam, score: game.intAwayScore, isWinning: isAwayWinning(), seed: game.awaySeed, record: game.awayRecord)

                Text("vs")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(WidgetTokens.inkFaint)

                teamColumn(teamID: game.idHomeTeam, teamName: game.strHomeTeam, score: game.intHomeScore, isWinning: isHomeWinning(), seed: game.homeSeed, record: game.homeRecord)
            }

            if let agg = game.aggregateScore {
                Text(agg)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(WidgetTokens.inkFaint)
            }

            // Line scores for completed games only (live scores would be stale)
            if isGameCompleted, let homeLine = game.homeLinescores, let awayLine = game.awayLinescores, !homeLine.isEmpty {
                HStack(spacing: 6) {
                    Text(awayLine.map { "\(Int($0))" }.joined(separator: "|"))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(WidgetTokens.inkFaint)
                    Spacer()
                    Text(homeLine.map { "\(Int($0))" }.joined(separator: "|"))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(WidgetTokens.inkFaint)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WidgetTokens.alt)
        .clipShape(RoundedRectangle(cornerRadius: WidgetTokens.radiusSM, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: WidgetTokens.radiusSM, style: .continuous))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func teamColumn(teamID: String?, teamName: String, score: String?, isWinning: Bool, seed: Int? = nil, record: String? = nil) -> some View {
        VStack(spacing: 2) {
            if let id = teamID, let data = images?[id], let image = widgetImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "sportscourt")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(WidgetTokens.inkFaint)
            }

            HStack(spacing: 1) {
                if let seed {
                    Text("(\(seed))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(WidgetTokens.inkFaint)
                }
                Text(getTeamAbbrev(teamID: teamID, teamName: teamName))
                    .font(.system(size: 11, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(WidgetTokens.ink)
            }

            if let record, !record.isEmpty {
                Text(record)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(WidgetTokens.inkFaint)
            }

            if let scoreStr = score, let scoreInt = Int(scoreStr) {
                Text("\(scoreInt)")
                    .font(.system(size: 14, design: .rounded).weight(isWinning ? .heavy : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isWinning ? WidgetTokens.ink : WidgetTokens.inkSoft)
            }
        }
    }

    private func getTeamAbbrev(teamID: String?, teamName: String) -> String {
        if let team = Team.getTeamInfoFrom(teams: teams, teamID: teamID, teamName: teamName),
           let shortName = team.strTeamShort {
            return shortName
        }
        let name = teamName.trimmingCharacters(in: .whitespaces)
        return Team.shortCode(strTeamShort: nil, name: name)
    }

    private func isHomeWinning() -> Bool {
        guard let homeScore = Int(game.intHomeScore ?? ""),
              let awayScore = Int(game.intAwayScore ?? "") else { return false }
        return homeScore > awayScore
    }

    private func isAwayWinning() -> Bool {
        guard let homeScore = Int(game.intHomeScore ?? ""),
              let awayScore = Int(game.intAwayScore ?? "") else { return false }
        return awayScore > homeScore
    }
}
