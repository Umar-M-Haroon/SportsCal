//
//  ScheduleGameView.swift
//  SportsCal
//
//  Created by Umar Haroon on 7/18/21.
//

import Foundation
import SwiftUI
import EventKit

struct ScheduleGameView: View {
    @State var game: Game?
    var dateFormatter: DateFormatter
    var relativeDateFormatter: RelativeDateTimeFormatter = RelativeDateTimeFormatter()
    @State var scheduleString: String?
    @State var currentDate: Date = Date()
    var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var timeRemaining: TimeInterval = 0
    @State var timeString: String = ""
    
    @State var accessibilityLabel: String = "days: hours"
    
    @Binding var shouldShowSportsCalProAlert: Bool
    
    @Binding var sheetType: SheetType?
    @State var hasFavoriteTeam: Bool = true
    @State var teamString: String?
    
    @Binding var shouldSetStartTime: Bool
    
    var favorites: Favorites
    
    init(gameArg: Game, shouldShowSportsCalProAlert: Binding<Bool>, sheetType: Binding<SheetType?>, teamStr: String?, favorites: Favorites, shouldSetStartTime: Binding<Bool>) {
        dateFormatter = DateFormatter()
        _game = State(initialValue: gameArg)
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        relativeDateFormatter.dateTimeStyle = RelativeDateTimeFormatter.DateTimeStyle.numeric
        _shouldShowSportsCalProAlert = shouldShowSportsCalProAlert
        _sheetType = sheetType
        _teamString = State(initialValue: teamStr)
        _shouldSetStartTime = shouldSetStartTime
        self.favorites = favorites
    }
    init() {
        relativeDateFormatter.dateTimeStyle = RelativeDateTimeFormatter.DateTimeStyle.numeric
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm"
        _sheetType = Binding<SheetType?>(get: {
            .onboarding
        }, set: { sheet in
            _ = sheet
        })
        _shouldShowSportsCalProAlert = Binding<Bool>(get: {
            false
        }, set: { should in
            _ = should
        })
        _teamString = State(initialValue: nil)
        
        _shouldSetStartTime = Binding<Bool>(get: {
            true
        }, set: { shouldSetStartTime in
            _ = shouldSetStartTime
        })
        self.favorites = Favorites()
        timeString = "6 days 18:29:31"
    }
    
    var body: some View {
        HStack {
            if game?.sport == .F1 {
                Image(systemName: "car.fill")
                    .font(.body)
                    .padding(-1)
                VStack(alignment: .leading) {
                    Text(game?.home ?? "New york knicxs")
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    TeamView(teamName: game?.home ?? "", visitingOrAway: .home, game: game!, score: game?.homeScore)
                    TeamView(teamName: game?.away ?? "", visitingOrAway: .away, game: game!, score: game?.awayScore)
                }
                
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let game_ = game, !game_.isInPast {
                    Text(format(game_.gameDate))
                        .fontWeight(.medium)
                        .accessibilityValue(accessibilityLabel)
                        .accessibilityLabel(accessibilityLabel)
                        .frame(maxWidth: .infinity,  alignment: .trailing)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .onReceive(timer) { cur in
                            timeString = formatCountdown()
                        }
                    if shouldSetStartTime {
                        Text(timeString)
                            .font(.system(.caption2, design: .rounded))
                            .fontWeight(.medium)
                            .accessibilityValue(accessibilityLabel)
                            .accessibilityLabel(accessibilityLabel)
                            .frame(maxWidth: .infinity,  alignment: .trailing)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .onReceive(timer) { cur in
                                timeString = formatCountdown()
                            }
                    }
                    if let competition = game_.competition?.name {
                        Text(competition)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity,  alignment: .trailing)
                    }
                }
                HStack {
                    FavoriteMenu(game: game)
                        .environmentObject(favorites)
                    if let game_ = game, !game_.isInPast {
                        Menu {
                            Button {
                                if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                                    shouldShowSportsCalProAlert = true
                                } else {
                                    EKEventStore().requestAccess(to: .event) { success, err in
                                        print("⚠️changing sheet type to a calendar with game \(game)")
                                        sheetType = .calendar(game: game)

                                    }
                                }
                            } label: {
                                Text("Add To Calendar")
                            }

                            Menu {
                                Button {
                                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                                        shouldShowSportsCalProAlert = true
                                    } else {
                                        NotificationManager.addLocalNotification(date: game!.gameDate, item: game!, duration: .thirtyMinutes)
                                    }
                                } label: {
                                    Text("\(NotificationDuration.thirtyMinutes.rawValue) before")
                                }
                                Button {
                                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                                        shouldShowSportsCalProAlert = true
                                    } else {
                                        NotificationManager.addLocalNotification(date: game!.gameDate, item: game!, duration: .oneHour)
                                    }
                                } label: {
                                    Text("\(NotificationDuration.oneHour.rawValue) before")
                                }
                                Button {

                                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                                        shouldShowSportsCalProAlert = true
                                    } else {
                                        NotificationManager.addLocalNotification(date: game!.gameDate, item: game!, duration: .twoHour)
                                    }
                                } label: {
                                    Text("\(NotificationDuration.twoHour.rawValue) before")
                                }
                            } label: {
                                Text("Notify me")
                            }
                        } label: {
                            Image(systemName: "clock")
                        }
                    }
                    Image((game?.sport.rawValue) ?? "NHL", bundle: nil)
                        .resizable()
                        .modifier(SportsTint(sport: SportTypes(rawValue: (game?.sport ?? .NHL).rawValue) ?? .NHL))
                        .frame(width: 20, height: 20, alignment: .center)
                        .padding(-1)
                }
                .frame(alignment: .trailing)
            }
            .frame(width: 120)
        }
        .padding(.vertical)
        .onAppear(perform: {
            timeString = formatCountdown()
        })
    }

    
    func format(_ date: Date?) -> String {
        guard let date = date else { return "sjdlfajksfjlasfdl" }
        dateFormatter.dateFormat = "hh:mm a"
        return dateFormatter.string(from: date)
    }
    
    func formatCountdown() -> String {
        guard let gameDate = game?.gameDate else { return "16 days: 12:12:20" }
//        let gameDate = DateComponents(calendar: Calendar.current, year: 2021, month: 7, day: 29, hour: 14, minute: 20, second: 0).date!
        timeRemaining = gameDate.timeIntervalSince(Date())
        if timeRemaining < 0 {
            return relativeDateFormatter.localizedString(for: gameDate, relativeTo: Date())
        }
        let days    = Int(timeRemaining) / 86400
        let hours   = Int(timeRemaining) / 3600 % 24
        let minutes = Int(timeRemaining) / 60 % 60
        let seconds = Int(timeRemaining) % 60
        var finalString = ""
        if days > 0 {
            finalString = String(format:"%2i days: %02i:%02i:%02i", days, hours, minutes, seconds)
            accessibilityLabel = String(format:"%2i days, %2i hours, %2i minutes, %2i seconds", days, hours, minutes, seconds)
        } else {
            
            finalString = String(format: "%2i:%02i:%02i", hours, minutes, seconds)
            accessibilityLabel = String(format:"%2i hours, %2i minutes, %2i seconds", days, hours, minutes, seconds)
        }
        return finalString
    }
}

struct ScheduleGameView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ScheduleGameView()
            ScheduleGameView()
        }
        
    }
}

struct SportsTint: ViewModifier {
    let sport: SportTypes
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            if sport == .NBA {
                content
                    .foregroundColor(.orange)
                    .background(.black, in: Circle())
            }
            if sport == .MLB {
                content
                    .foregroundColor(.white)
                    .background(.red, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 1, antialiased: true)
                    )
            }
            if sport == .NFL {
                content
                    .foregroundColor(.brown)
            }
            if sport == .NHL {
                content
            }
            if sport == .Soccer {
                content
            }
        } else {
            content
        }
    }
}
