//
//  SportsWidgetSmallView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import WidgetKit
import SportsCalModel

struct SportsWidgetSmallView: View {
    var entry: Provider.Entry

    private var dayOffset: Int {
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.integer(forKey: "widgetDayOffset") ?? 0
    }

    private var displayDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private var hasMultipleGames: Bool {
        (entry.game?.count ?? 0) >= 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasMultipleGames {
                Spacer()
            }
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Button(intent: NavigateDayIntent(dayOffset: dayOffset - 1)) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(displayDate.formatted(.dateTime.weekday(.abbreviated)))
                        .bold()
                        .foregroundColor(.red)

                    Button(intent: NavigateDayIntent(dayOffset: dayOffset + 1)) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, 8)
                HStack {
                    Text(displayDate.formatted(.dateTime.month(.abbreviated).day(.twoDigits)))
                        .bold()
                    Spacer()
                    Text("Up Next")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(alignment: .leading)
                }
            }
            .padding(.bottom, 4)
            if let games = entry.game, games.count >= 2 {
                ForEach(Array(games.prefix(2))) { game in
                    smallGameRow(game: game)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let games = entry.game, let game = games.first {
                smallGameRow(game: game)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 24, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(WidgetTokens.inkSoft)
                    Text("No upcoming games")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WidgetTokens.inkSoft)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
            if hasMultipleGames {
                Spacer()
            }
            WidgetUpdatedLabel(date: entry.date)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding([.leading, .trailing, .bottom], 8)
        .widgetURL(smallWidgetURL)
    }

    private var smallWidgetURL: URL? {
        guard let game = entry.game?.first, let id = game.idEvent else { return nil }
        return URL(string: "sportscal://game/\(id)")
    }

    @ViewBuilder
    private func smallGameRow(game: Game) -> some View {
        let sportType = game.sportType ?? .basketball
        if game.isIndividualSport {
            HStack(spacing: 6) {
                Image(systemName: sportType.widgetSystemImage)
                    .font(.system(size: 14))
                    .foregroundColor(sportType.widgetColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.strHomeTeam)
                        .lineLimit(1)
                        .font(.caption2)
                        .fontWeight(.medium)
                    if let leader = game.resolvedLeaderboard.first {
                        Text("\(leader.name) \(leader.score)")
                            .lineLimit(1)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(game.strAwayTeam)
                            .lineLimit(1)
                            .font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            SportsView(
                home: game.strHomeTeam,
                away: game.strAwayTeam,
                type: sportType,
                color: .orange,
                gameDate: game.strTimestamp ?? "",
                homeImageData: entry.images?[game.idHomeTeam ?? ""],
                awayImageData: entry.images?[game.idAwayTeam ?? ""]
            )
        }
    }
}
