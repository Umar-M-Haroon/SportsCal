//
//  SportsWidget.swift
//  SportsWidget
//
//  Created by Umar Haroon on 9/15/21.
//

import WidgetKit
import SwiftUI
import Intents
import Combine
import SportsCalModel

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
            }
        }
        .frame(width: 4, height: 40)
        .border(.quaternary, width: 1)
        .cornerRadius(2)
    }
}
struct SportsView: View {
    let home: String
    let away: String
    let type: SportType
    let color: Color
    let gameDate: String
    let homeImage: Data? = nil
    let awayImage: Data? = nil
    var body: some View {
        HStack {
            SportsLine(type: type)
            VStack(alignment: .leading) {
                HStack {
                    if let date = DateFormatters.isoFormatter.date(from: gameDate) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).month(.defaultDigits).day().hour().minute()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading) {
                    Text(home)
                        .lineLimit(1)
                        .font(.caption2)
                    Text(away)
                        .lineLimit(1)
                        .font(.caption2)
                }
            }
        }
    }
    
}

struct SportsWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .systemSmall: SportsWidgetSmallView(entry: entry)
        case .systemMedium: SportsWidgetMediumView(entry: entry)
        case .systemLarge: SportsWidgetLargeView(entry: entry)
        case .accessoryCircular: SportsWidgetCircularView(entry: entry)
        case .accessoryRectangular: SportsWidgetRectangularView(entry: entry)
        case .accessoryInline: SportsWidgetInlineView(entry: entry)
        default: SportsWidgetSmallView(entry: entry)
        }
        
    }
}

@main
struct SportsWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        SportsWidget()
        if #available(iOS 16.1, *) {
#if canImport(ActivityKit)
            LiveSportActivityWidget()
#endif
        }
    }
}
struct SportsWidget: Widget {
    let kind: String = "SportsWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider()) { entry in
            SportsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sports Widget")
        .description("Show upcoming games for a sport")
        .versionSpecificFamilies()
    }
}
extension WidgetConfiguration {
    func versionSpecificFamilies() -> some WidgetConfiguration {
        if #available(iOS 16.0, *) {
            return self.supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
        }
        return self.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@available(iOSApplicationExtension 16.0, *)
struct SportsWidget_Previews: PreviewProvider {
    static var sampleGames: [Game] = [
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00")
    ]
    
   static var images: [String: Data] = ["134875": UIImage(systemName: "folder.circle")!.pngData()!, "134880": UIImage(systemName: "circle.fill")!.pngData()!]
    
   static var teams: [Team] = [
        Team.init(idTeam: "134875", strTeam: "Dallas Mavericks", strTeamShort: "DAL", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134880", strTeam: "Utah Jazz", strTeamShort: "UTA", strAlternate: nil, strTeamBadge: nil),
    ]
    static var previews: some View {
        Group {
            SportsWidgetEntryView(entry: SimpleEntry(date: .now,
                                                     configuration: .init(),
                                                     game: sampleGames,
                                                     images: images,
                                                     teams: teams))
            .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}

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
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
//                        .frame(maxWidth: .infinity, alignment: (shortName == nil && isAway) ? .leading : .trailing)
                }
                if shortName == nil && isAway {
                    Spacer()
                }
            }
//            .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            if let shortName {
                Text(shortName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
//                    .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            } else if let longName {
                Text(longName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: isAway ? .leading : .trailing)
            }
        }
//        .background(Color.red)
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
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
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


