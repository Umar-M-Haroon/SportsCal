//
//  SportsWidget.swift
//  SportsWidget
//
//  Created by Umar Haroon on 9/15/21.
//

import WidgetKit
import SwiftUI
import Combine
import SportsCalModel

// MARK: - Cross-Platform Image Helper

#if canImport(UIKit)
import UIKit
func widgetImage(from data: Data) -> Image? {
    guard let img = UIImage(data: data) else { return nil }
    return Image(uiImage: img)
}
#elseif canImport(AppKit)
import AppKit
func widgetImage(from data: Data) -> Image? {
    guard let img = NSImage(data: data) else { return nil }
    return Image(nsImage: img)
}
#endif

// MARK: - Cross-Platform Cell Background

var widgetCellBackground: Color {
    #if canImport(UIKit)
    Color(UIColor.secondarySystemBackground)
    #else
    Color(NSColor.controlBackgroundColor)
    #endif
}

// MARK: - Sport Color Line

struct SportsLine: View {
    let type: SportType
    var body: some View {
        VStack(spacing: 0) {
            switch type {
            case .hockey:
                Rectangle()
                    .foregroundColor(.black)
                Rectangle()
                    .foregroundColor(.white)
            case .nfl:
                Rectangle()
                    .foregroundColor(.brown)
            case .basketball:
                Rectangle()
                    .foregroundColor(.orange)
            case .mlb:
                Rectangle()
                    .foregroundColor(.white)
                Rectangle()
                    .foregroundColor(.red)
            case .soccer:
                Rectangle()
                    .foregroundColor(.white)
                Rectangle()
                    .foregroundColor(.black)
            case .golf:
                Rectangle()
                    .foregroundColor(.mint)
            case .tennis:
                Rectangle()
                    .foregroundColor(.yellow)
            case .racing:
                Rectangle()
                    .foregroundColor(.white)
                Rectangle()
                    .foregroundColor(.black)
            }
        }
        .frame(width: 4, height: 40)
        .border(.quaternary, width: 1)
        .cornerRadius(2)
    }
}

// MARK: - SportsView (Small widget row)

struct SportsView: View {
    let home: String
    let away: String
    let type: SportType
    let color: Color
    let gameDate: String
    var homeImageData: Data? = nil
    var awayImageData: Data? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type.widgetSystemImage)
                .font(.system(size: 14))
                .foregroundColor(type.widgetColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                if let date = DateFormatters.isoFormatter.date(from: gameDate) {
                    Text(date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 3) {
                    if let data = homeImageData, let image = widgetImage(from: data) {
                        image.resizable().aspectRatio(contentMode: .fit).frame(width: 12, height: 12)
                    }
                    Text(home)
                        .lineLimit(1)
                        .font(.caption2)
                }
                HStack(spacing: 3) {
                    if let data = awayImageData, let image = widgetImage(from: data) {
                        image.resizable().aspectRatio(contentMode: .fit).frame(width: 12, height: 12)
                    }
                    Text(away)
                        .lineLimit(1)
                        .font(.caption2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Entry View Router

struct SportsWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Group {
            switch family {
            case .systemSmall: SportsWidgetSmallView(entry: entry)
            case .systemMedium: SportsWidgetMediumView(entry: entry)
            case .systemLarge: SportsWidgetLargeView(entry: entry)
            #if os(iOS)
            case .accessoryCircular: SportsWidgetCircularView(entry: entry)
            case .accessoryRectangular: SportsWidgetRectangularView(entry: entry)
            case .accessoryInline: SportsWidgetInlineView(entry: entry)
            #endif
            default: SportsWidgetSmallView(entry: entry)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Bundle

@main
struct SportsWidgetBundle: WidgetBundle {
    var body: some Widget {
        SportsWidget()
        #if os(iOS)
        LiveSportActivityWidget()
        SportsCalControlWidget()
        #endif
    }
}

// MARK: - Main Widget

struct SportsWidget: Widget {
    let kind: String = "SportsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SportsWidgetIntent.self, provider: Provider()) { entry in
            SportsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sports Widget")
        .description("Show upcoming games for a sport")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #endif
        .contentMarginsDisabled()
    }
}

// MARK: - Team Badge Views

struct WidgetTeamView: View {
    var shortName: String?
    var longName: String?
    var isAway: Bool
    var data: Data? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if shortName == nil && !isAway {
                    Spacer()
                }
                if let data, let image = widgetImage(from: data) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                }
                if shortName == nil && isAway {
                    Spacer()
                }
            }
            if let shortName {
                Text(shortName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let longName {
                Text(longName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            }
        }
    }
}

struct TinyWidgetTeamView: View {
    var shortName: String?
    var longName: String?
    var isAway: Bool
    var data: Data? = nil
    var showText: Bool = true
    var body: some View {
        VStack(spacing: 0) {
            if let data, let image = widgetImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
            if showText {
                if let shortName {
                    Text(shortName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else if let longName {
                    Text(longName.uppercased())
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Previews

struct SportsWidget_Previews: PreviewProvider {
    static var sampleGames: [Game] = [
        Game(idLiveScore: nil, idEvent: "1001", strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: "1002", strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: "1003", strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: "1004", strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: "1005", strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil),
        Game(idLiveScore: nil, idEvent: "1006", strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00", isoDate: nil)
    ]

    static var teams: [Team] = [
        Team.init(idTeam: "134875", strTeam: "Dallas Mavericks", strTeamShort: "DAL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134880", strTeam: "Utah Jazz", strTeamShort: "UTA", strAlternate: nil, strTeamBadge: nil),
    ]
    static var previews: some View {
        Group {
            SportsWidgetEntryView(entry: SimpleEntry(date: .now,
                                                     configuration: SportsWidgetIntent(),
                                                     game: sampleGames,
                                                     images: nil,
                                                     teams: teams))
            .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
