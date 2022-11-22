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

class Provider: IntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        return SimpleEntry(date: Date(), configuration: ConfigurationIntent(), game: [Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: nil, strLeague: nil, idHomeTeam: nil, idAwayTeam: nil, strHomeTeam: "Denver Nuggets", strAwayTeam: "Milwaukee Bucks", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: nil, intAwayScore: nil, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: nil, strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: DateFormatters.isoFormatter.string(from: .now))], images: nil, teams: [])
    }

    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        Task {
            let (games, teams) = await handleNetworking(favoriteOnly: configuration.favoritesOnly?.boolValue ?? false, type: configurationToString(configuration: configuration))
            if games.isEmpty {
                let entry = SimpleEntry(date: Date(), configuration: configuration, game: nil, images: nil, teams: teams)
                completion(entry)
                return
            }
            if games.count < 2 {
                var entry = SimpleEntry(date: Date(), configuration: configuration, game: [games[0]], images: nil, teams: teams)
                guard let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idHomeTeam),
                      let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idAwayTeam) else {
                    completion(entry)
                    return
                }
                if let images = try? await getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam) {
                    entry.images = images
                }
                completion(entry)
                return
            }

            var allImages: [String: Data] = [:]
            for game in games {
                if let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idAwayTeam) {
                    async let images = getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam)
                    try await allImages.merge(images, uniquingKeysWith: {$1})
                }
            }
            let entry = SimpleEntry(date: Date(), configuration: configuration, game: Array(games.prefix(through: 1)), images: allImages, teams: teams)
            completion(entry)
        }
    }

    func getImagesFor(homeTeam: Team, awayTeam: Team) async throws -> [String: Data] {
        guard let homeImageURL = homeTeam.strTeamBadge,
              let homeID = homeTeam.idTeam,
              let awayImageURL = awayTeam.strTeamBadge,
              let awayID = awayTeam.idTeam else {
            return [:]
        }
        let homeImage = try await NetworkHandler.getImageFor(url: homeImageURL, size: .tiny)
        let awayImage = try await NetworkHandler.getImageFor(url: awayImageURL, size: .tiny)
        return [homeID: homeImage, awayID: awayImage]
    }
    
    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            await completion(timelineHandler(configuration: configuration))
        }
    }
    
    func timelineHandler(configuration: ConfigurationIntent) async -> Timeline<Entry> {
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        let (games, teams) = await handleNetworking(favoriteOnly: configuration.favoritesOnly?.boolValue ?? false, type: configurationToString(configuration: configuration))
        let entryDate = Calendar.current.date(byAdding: .minute, value: 3, to: currentDate)
        if games.isEmpty {
            let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: nil, images: nil, teams: teams)
            //                let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: [Game(idLeague: "4387", strHomeTeam: "uhoh", strAwayTeam: "Test")])
            entries.append(entry)
        } else if games.count < 2 {
            var entry = SimpleEntry(date: entryDate!, configuration: configuration, game: [games[0]], images: nil, teams: teams)
            guard let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idHomeTeam),
                  let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: games[0].idAwayTeam) else {
                entries.append(entry)
                return Timeline(entries: entries, policy: .atEnd)
            }
            if let images = try? await getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam) {
                entry.images = images
            }
            entries.append(entry)
        } else {
            let first2Games = games.prefix(through: 1)
            var allImages: [String: Data] = [:]
            for game in first2Games {
                if let homeTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idHomeTeam), let awayTeam = Team.getTeamInfoFrom(teams: teams, teamID: game.idAwayTeam) {
                    async let images = getImagesFor(homeTeam: homeTeam, awayTeam: awayTeam)
                    try? await allImages.merge(images, uniquingKeysWith: {$1})
                }
            }
            let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: Array(first2Games), images: allImages, teams: teams)
            entries.append(entry)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
    
    func configurationToString(configuration: ConfigurationIntent) -> SportType {
        switch configuration.GameType {
        case .mLB:
            return .mlb
        case .nBA:
            return .basketball
        case .nHL:
            return .hockey
        case .nFL:
            return .nfl
        case .soccer:
            return .soccer
        case .unknown:
            return .hockey
        }
    }
    
    
    func handleNetworking(favoriteOnly: Bool, type: SportType) async -> ([Game], [Team])  {
        do {
            var games = try await NetworkHandler.getScheduleFor(sport: type).events
            games = games
                .filter({ game -> Bool in
                    guard let date = game.getDate() else { return false }
                        return date.timeIntervalSinceNow > 0
                })
            async let teams = NetworkHandler.getTeams()

            let favorites = Favorites()
            if favoriteOnly {
                games.removeAll { game in
                    !favorites.contains(game)
                }
            }
            return await (games, try teams)
        } catch let e {
            return ([Game(idLeague: "4387", strHomeTeam: "g", strAwayTeam: e.localizedDescription)], [])
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent
    let game: [Game]?
    var images: [String: Data]?
    let teams: [Team]
}
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
                    Text(Date.isoStringToDateString(dateString: gameDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
//                    Text(Date.formatToTime(gameDate))
//                        .font(.caption)
//                        .foregroundColor(.secondary)
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

struct SportsWidgetSmallView: View {
    var entry: Provider.Entry
    var body: some View {
        VStack(spacing: 4) {
            VStack {
                Text(Date.currentDateToDayString())
                    .bold()
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                
                HStack {
                    Text(Date.currentDateToNumberString())
                        .bold()
                    Spacer()
                    Text("Up Next")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(alignment: .leading)
                }
            }
            .padding(.bottom, 4)
            if let games = entry.game, !games.isEmpty {
                ForEach(Array(games.prefix(through: 1))) { game in
                    SportsView(home: game.strHomeTeam, away: game.strAwayTeam, type: SportType.basketball, color: .orange, gameDate: game.strTimestamp ?? "")
                }
            } else {
                Spacer()
                Text("No upcoming games")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding([.leading, .trailing, .bottom], 8)
    }
}

struct SportsWidgetMediumView: View {
    var entry: Provider.Entry
    var body: some View {
        VStack {
            VStack {
                Text(Date.currentDateToDayString())
                    .bold()
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                
                HStack {
                    Text(Date.currentDateToNumberString())
                        .bold()
                    Spacer()
                    Text("Up Next")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(alignment: .leading)
                        .padding([.leading], 8)
                }
            }
            VStack(spacing: 4) {
                if let games = entry.game {
                    if games.isEmpty {
                        Text("No upcoming games")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(games) { game in
                            if let homeTeamID = game.idHomeTeam, let homeTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: homeTeamID), let awayTeamID = game.idAwayTeam, let awayTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: awayTeamID) {
                                HStack {
//                                    HStack {
                                    WidgetTeamView(shortName: awayTeam.strTeamShort, longName: awayTeam.strTeam, isAway: true, data: entry.images?[awayTeamID])
                                    Spacer()
                                    VStack(alignment: .center, spacing: 0) {
                                        if let isoDate = game.getDate() {
                                            
                                            Text(isoDate.formatToDate(dateFormat: "d MMM") ?? "")
                                                .font(.system(.subheadline, design: .monospaced))
                                                .fontWeight(.medium)
                                            //                                                    .accessibilityValue(accessibilityLabel)
                                            //                                                    .accessibilityLabel(accessibilityLabel)
                                                .foregroundColor(.secondary)
                                        }
                                        if let isoDate = game.getDate(),
                                           let isoString = isoDate.formatToTime() {
                                            Text(isoString)
                                                .font(.system(.subheadline, design: .monospaced))
                                                .fontWeight(.medium)
                                                .foregroundColor(Color(UIColor.secondaryLabel))
                                        }
                                        //
                                    }
                                    Spacer()
//                                        .frame(maxWidth: .infinity)
                                    WidgetTeamView(shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, isAway: false, data: entry.images?[homeTeamID])
                                            
//                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No upcoming games")
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
    }
}
struct SportsWidgetLargeView: View {
    var entry: Provider.Entry
    var body: some View {
        Text("Hello World!!")
    }
}
struct SportsWidgetCircularView: View {
    var entry: Provider.Entry
    var body: some View {
        Text("Hello World!")
    }
}
struct SportsWidgetRectangularView: View {
    var entry: Provider.Entry
    var body: some View {
        Text("Hello World!")
    }
}
struct SportsWidgetInlineView: View {
    var entry: Provider.Entry
    var body: some View {
        Text("Hello World!")
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SportsWidget_Previews: PreviewProvider {
    var sampleGames: [Game] = [
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
    ]
    
    var images: [String: Data] = ["134875": UIImage(systemName: "folder.circle")!.pngData()!, "134880": UIImage(systemName: "circle.fill")!.pngData()!]
    
    var teams: [Team] = [
        Team.init(idTeam: "134875", strTeam: "DAL", strTeamShort: "Dallas Mavericks", strAlternate: nil, strTeamBadge: nil),
        Team.init(idTeam: "134880", strTeam: "UTA", strTeamShort: "Utah Jazz", strAlternate: nil, strTeamBadge: nil),
    ]
    static var previews: some View {
        Group {
            SportsWidgetEntryView(entry: SimpleEntry(date: .now,
                                                     configuration: .init(),
                                                     game: [
                                                        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134875", idAwayTeam: "134880", strHomeTeam: "Dallas Mavericks", strAwayTeam: "Utah Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),
                                                        Game(idLiveScore: nil, idEvent: nil, strSport: nil, idLeague: "4387", strLeague: "NBA", idHomeTeam: "134890", idAwayTeam: "134891", strHomeTeam: "Milwaukee Bucks", strAwayTeam: "Denver Nuggets Jazz", strHomeTeamBadge: nil, strAwayTeamBadge: nil, intHomeScore: "103", intAwayScore: "100", strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: "FT", strProgress: nil, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: "2022-11-03T00:30:00+00:00"),

                                                     ],
                                                     images: [
                                                        "134875": UIImage(systemName: "folder.circle")!.pngData()!,
                                                        "134880": UIImage(systemName: "circle.fill")!.pngData()!,
                                                        "134890": UIImage(systemName: "folder.circle")!.pngData()!,
                                                        "134891": UIImage(systemName: "circle.fill")!.pngData()!],
                                                     teams: [
                                                        Team.init(idTeam: "134875", strTeam: "Dallas Mavericks", strTeamShort: "DAL", strAlternate: nil, strTeamBadge: nil),
                                                        Team.init(idTeam: "134880", strTeam: "Utah Jazz", strTeamShort: "UTA", strAlternate: nil, strTeamBadge: nil),
                                                        Team.init(idTeam: "134890", strTeam: "Milwaukee Bucks", strTeamShort: nil, strAlternate: nil, strTeamBadge: nil),
                                                        Team.init(idTeam: "134891", strTeam: "Denver Nuggets", strTeamShort: nil, strAlternate: nil, strTeamBadge: nil)
                                                     ]))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}

struct SportsTint: ViewModifier {
    let sport: SportType
    func body(content: Content) -> some View {
        if sport == .basketball {
            content
                .foregroundColor(.orange)
                .background(.black, in: Circle())
        }
        if sport == .mlb {
            content
                .foregroundColor(.white)
                .background(.red, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1, antialiased: true)
                )
        }
        if sport == .nfl {
            content
                .foregroundColor(.brown)
        }
        if sport == .hockey {
            content
        }
        if sport == .soccer {
            content
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
