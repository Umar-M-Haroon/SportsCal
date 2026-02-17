//
//  WidgetInteractiveIntents.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 2/15/26.
//

import AppIntents
import SwiftUI
import WidgetKit
import SportsCalModel

// MARK: - Sport Icon Helper for Widget

extension SportType {
    var widgetSystemImage: String {
        switch self {
        case .soccer: return "soccerball"
        case .basketball: return "basketball.fill"
        case .hockey: return "hockey.puck.fill"
        case .mlb: return "baseball.fill"
        case .nfl: return "football.fill"
        case .golf: return "figure.golf"
        case .tennis: return "tennis.racket"
        case .racing: return "flag.checkered.2.crossed"
        }
    }

    var widgetColor: Color {
        switch self {
        case .basketball: return .orange
        case .soccer: return .green
        case .hockey: return .blue
        case .mlb: return .red
        case .nfl: return .brown
        case .golf: return .mint
        case .tennis: return .yellow
        case .racing: return .red
        }
    }
}

// MARK: - Follow Game Intent (Start Live Activity)

#if os(iOS)
struct FollowGameIntent: AppIntent {
    static var title: LocalizedStringResource = "Follow Game"
    static var description: IntentDescription = "Follow a game with Live Activity"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Game ID")
    var gameID: String

    @Parameter(title: "Home Team")
    var homeTeam: String

    @Parameter(title: "Away Team")
    var awayTeam: String

    init() {}

    init(gameID: String, homeTeam: String, awayTeam: String) {
        self.gameID = gameID
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
    }

    func perform() async throws -> some IntentResult {
        // Write the follow request to shared app group storage
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        var ids = defaults?.stringArray(forKey: "autoFollowEventIDs") ?? []
        if !ids.contains(gameID) {
            ids.append(gameID)
            defaults?.set(ids, forKey: "autoFollowEventIDs")
        }
        return .result()
    }
}
#endif

// MARK: - Navigate Day Intent

struct NavigateDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Navigate Day"
    static var description: IntentDescription = "Change the widget's displayed day"

    @Parameter(title: "Day Offset")
    var dayOffset: Int

    init() {}

    init(dayOffset: Int) {
        self.dayOffset = dayOffset
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        defaults?.set(dayOffset, forKey: "widgetDayOffset")
        defaults?.set(Date(), forKey: "widgetDayOffsetDate")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
