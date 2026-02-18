//
//  SportType+Watch.swift
//  SportsCalWatch
//
//  SportType UI extensions for Watch app views.
//  Mirrors WidgetInteractiveIntents.swift extensions for the Watch app target.
//

import SwiftUI
import SportsCalModel

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
