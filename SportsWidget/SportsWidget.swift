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
    private var cancellable: AnyCancellable!
    private var isRunning: Bool = false
    func placeholder(in context: Context) -> SimpleEntry {
        return SimpleEntry(date: Date(), configuration: ConfigurationIntent(), game: nil)
    }

    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        handleNetworking(favoriteOnly: configuration.favoritesOnly?.boolValue ?? false, type: configurationToString(configuration: configuration)) { games in
            if games.isEmpty {
                let entry = SimpleEntry(date: Date(), configuration: configuration, game: nil)
                completion(entry)
                return
            }
            if games.count < 2 {
                let entry = SimpleEntry(date: Date(), configuration: configuration, game: [games[0]])
                completion(entry)
                return
            }
            let entry = SimpleEntry(date: Date(), configuration: configuration, game: Array(games.prefix(through: 1)))
            completion(entry)
        }
    }

    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        
        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        //        if !isRunning {
        isRunning = true
        timelineHandler(configuration: configuration) { entry in
            completion(entry)
        }
    }
    
    
    func timelineHandler(configuration: ConfigurationIntent, completion: @escaping(Timeline<Entry>) -> Void) {
        
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        handleNetworking(favoriteOnly: configuration.favoritesOnly?.boolValue ?? false, type: configurationToString(configuration: configuration), completion: { games in
            let entryDate = Calendar.current.date(byAdding: .minute, value: 3, to: currentDate)
            if games.isEmpty {
                let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: nil)
                entries.append(entry)
                
            } else if games.count < 2 {
                let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: [games[0]])
                entries.append(entry)
            } else {
                
                let entry = SimpleEntry(date: entryDate!, configuration: configuration, game: Array(games.prefix(through: 1)))
                entries.append(entry)
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        })
        
    }
    
    func configurationToString(configuration: ConfigurationIntent) -> SportType {
        switch configuration.SportType {
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
    
    
    func handleNetworking(favoriteOnly: Bool, type: SportType?, completion: @escaping([Game]) -> Void) {
        
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent
    let game: [Game]?
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
        .frame(width: 4, height: 25)
        .border(.quaternary, width: 1)
        .cornerRadius(2)
    }
}
struct SportsView: View {
    let home: String
    let away: String?
    let type: SportType
    let color: Color
    let gameDate: Date
    var body: some View {
        HStack {
            SportsLine(type: type)
                
            HStack {
                VStack(spacing: 0) {
                    Text(dateToString(date: gameDate))
                        .font(.caption2)
                        Image(type.rawValue)
                            .modifier(SportsTint(sport: type))
                }
                Spacer()
                VStack(alignment: .leading) {
                    
                    Text(home)
                        .lineLimit(1)
                        .font(.caption2)
                    if let away = away {
                        Text(away)
                            .lineLimit(1)
                        .font(.caption)
                    }
                }
            }
        }
    }
    func dateToString(date: Date) -> String {
        let cal = Calendar.current
        let df = DateFormatter()
        if cal.isDateInToday(date) {
            df.dateFormat = "h:mm a"
            return df.string(from: date)
        }
        df.dateFormat = "MM/dd"
        return df.string(from: date)
    }
}
struct SportsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SportsView(home: "Milwaukee Bucks", away: "Denver Nuggets", type: .basketball, color: .orange, gameDate: sampleDate(hoursInFuture: 2))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SportsView(home: "Milwaukee Bucks", away: "Denver Nuggets", type: .basketball, color: .orange, gameDate: sampleDate(daysInFuture: 1))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SportsView(home: "Milwaukee Bucks", away: "Denver Nuggets", type: .basketball, color: .orange, gameDate: sampleDate(daysInFuture: 2))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
    static func sampleDate(hoursInFuture hours: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .hour, value: hours, to: Date(), wrappingComponents: true)!
        
    }
    static func sampleDate(daysInFuture days: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: days, to: Date(), wrappingComponents: true)!
        
    }
}
struct SportsWidgetSmallView: View {
    var entry: Provider.Entry
    

    var body: some View {
        VStack {
            VStack {
                HStack {
                    Text(currentDateToDayString())
                        .bold()
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.top, 8)

                HStack {
                    Text(currentDateToNumberString())
                        .bold()
                    Spacer()
                    Text("Up Next")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(alignment: .leading)
                        .padding([.leading], 8)
                }
            }
            Spacer()
            VStack(alignment: .center) {
                if let games = entry.game {
                    if games.isEmpty {
                        Text("No upcoming games")
                    } else {
                        ForEach(games) { game in
//                            SportsView(home: game.strHomeTeam, away: game.strAwayTeam, type: SportType(league: Leagues(rawValue: Int(game.idLeague!)!)!), color: .orange, gameDate: Date.now)
                        }
                    }
                } else {
                        Text("No upcoming games")
                }
            }
            Spacer()
        }
        .padding([.leading, .trailing], 8)
    }

    func currentDateToDayString() -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df.string(from: Date())
    }
    func currentDateToNumberString() -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        return df.string(from: Date())
    }
    func dateToString(formatString: String = "MM/dd", date: Date) -> String {
        
        let df = DateFormatter()
        df.dateFormat = formatString
        return df.string(from: date)
    }


}

struct SportsWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
            SportsWidgetSmallView(entry: entry)
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
        .supportedFamilies([.systemSmall])
    }
}

struct SportsWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SportsWidgetEntryView(entry: SimpleEntry(date: Date(), configuration: ConfigurationIntent(), game: nil))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SportsWidgetEntryView(entry: SimpleEntry(date: Date(), configuration: ConfigurationIntent(), game: nil))
                .preferredColorScheme(.dark)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SportsWidgetEntryView(entry: SimpleEntry(date: Date(), configuration: ConfigurationIntent(), game: nil))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
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
