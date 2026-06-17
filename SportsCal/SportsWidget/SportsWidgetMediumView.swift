//
//  SportsWidgetMediumView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import WidgetKit
import SportsCalModel

struct SportsWidgetMediumView: View {
    var entry: Provider.Entry

    private var dayOffset: Int {
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.integer(forKey: "widgetDayOffset") ?? 0
    }

    private var displayDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 4) {
            // Header with day navigation
            HStack(spacing: 6) {
                Button(intent: NavigateDayIntent(dayOffset: dayOffset - 1)) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text(displayDate.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(WidgetTokens.live)
                    Text(displayDate.formatted(.dateTime.month(.abbreviated).day(.twoDigits)))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(WidgetTokens.ink)
                }

                Button(intent: NavigateDayIntent(dayOffset: dayOffset + 1)) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                if dayOffset != 0 {
                    Button(intent: NavigateDayIntent(dayOffset: 0)) {
                        Text("TODAY")
                            .font(.system(size: 9, design: .monospaced).weight(.bold))
                            .tracking(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WidgetTokens.live)
                }

                Text("SCOREBOARD")
                    .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(WidgetTokens.inkFaint)
            }
            .padding(.horizontal, 4)

            // Interactive sport filter tabs (iOS only, allSports mode)
            #if os(iOS)
            if entry.configuration.sport == .allSports {
                WidgetSportTabBar(compact: true)
            }
            #endif

            // Compact multi-game grid (2x2 = 4 games)
            if let games = entry.game, !games.isEmpty {
                let displayGames = Array(games.prefix(4))
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)
                ], spacing: 4) {
                    ForEach(displayGames) { game in
                        gameCellView(game: game)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 22, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(WidgetTokens.inkSoft)
                    Text("No upcoming games")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WidgetTokens.inkSoft)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
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
        if let id = game.idEvent, let url = URL(string: "sportscal://game/\(id)") {
            Link(destination: url) { cellContent(game: game) }
        } else {
            cellContent(game: game)
        }
    }

    @ViewBuilder
    private func cellContent(game: Game) -> some View {
        if game.isRace {
            WidgetRaceCell(game: game, compact: true)
        } else if game.isIndividualSport {
            WidgetTournamentCell(game: game, compact: true)
        } else {
            CompactGameCell(game: game, teams: entry.teams, images: entry.images)
        }
    }
}

// Compact cell for showing a single game in the grid
struct CompactGameCell: View {
    let game: Game
    let teams: [Team]
    let images: [String: Data]?

    private var sportType: SportType { game.sportType ?? .basketball }

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" && status != "not started" && status != "ns"
            && game.intHomeScore != nil && game.intAwayScore != nil
    }

    var body: some View {
        let accent = WidgetTokens.sport(sportType)
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: sportType.widgetSystemImage)
                .font(.system(size: 10))
                .foregroundStyle(accent)
                .frame(width: 12)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                // Teams row
                HStack(spacing: 4) {
                    compactTeamView(teamID: game.idAwayTeam, teamName: game.strAwayTeam, score: game.intAwayScore, seed: game.awaySeed)
                    Text("@")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(WidgetTokens.inkFaint)
                    compactTeamView(teamID: game.idHomeTeam, teamName: game.strHomeTeam, score: game.intHomeScore, seed: game.homeSeed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Time or status
                HStack(spacing: 4) {
                    if let statusText = game.displayStatus {
                        HStack(spacing: 3) {
                            if isLive {
                                Circle().fill(WidgetTokens.live).frame(width: 4, height: 4)
                            }
                            Text(statusText)
                                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                                .foregroundStyle(isLive ? WidgetTokens.live : WidgetTokens.inkSoft)
                        }
                    } else if let gameDate = game.standardDate {
                        Text(gameDate.formatToTime() ?? "")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(WidgetTokens.inkSoft)
                    }
                }

                if let agg = game.aggregateScore {
                    Text(agg)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(WidgetTokens.inkFaint)
                }
            }
        }
        .padding(4)
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
    private func compactTeamView(teamID: String?, teamName: String, score: String?, seed: Int? = nil) -> some View {
        HStack(spacing: 2) {
            if let id = teamID, let data = images?[id], let image = widgetImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
            }

            if let seed {
                Text("(\(seed))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(WidgetTokens.inkFaint)
            }

            Text(getTeamAbbrev(teamID: teamID, teamName: teamName))
                .font(.system(size: 10, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(WidgetTokens.ink)

            if let scoreStr = score, let scoreInt = Int(scoreStr) {
                Text("\(scoreInt)")
                    .font(.system(size: 10, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTokens.ink)
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
}
