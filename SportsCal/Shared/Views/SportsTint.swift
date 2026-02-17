//
//  SportsTint.swift
//  SportsCal
//
//  Created by Umar Haroon on 1/21/23.
//

import SwiftUI
import SportsCalModel

struct SportsTint: ViewModifier {
    let sport: SportType
    func body(content: Content) -> some View {
        switch sport {
        case .basketball:
            content
                .foregroundColor(.orange)
        case .mlb:
            content
                .foregroundColor(.white)
                .background(.red, in: Circle())
        case .nfl:
            content
                .foregroundColor(.brown)
        case .hockey:
            content
                .foregroundColor(.blue)
        case .soccer:
            content
                .foregroundColor(.green)
        case .golf:
            content
                .foregroundColor(.mint)
        case .tennis:
            content
                .foregroundColor(.yellow)
        case .racing:
            content
                .foregroundColor(.red)
        }
    }
}

extension SportType {
    var systemImage: String {
        switch self {
        case .soccer:
            return "soccerball"
        case .basketball:
            return "basketball.fill"
        case .hockey:
            return "hockey.puck.fill"
        case .mlb:
            return "baseball.fill"
        case .nfl:
            return "football.fill"
        case .golf:
            return "figure.golf"
        case .tennis:
            return "tennis.racket"
        case .racing:
            return "flag.checkered.2.crossed"
        }
    }

    var color: Color {
        switch self {
        case .soccer:
            return .green
        case .basketball:
            return .orange
        case .hockey:
            return .blue
        case .mlb:
            return .red
        case .nfl:
            return .brown
        case .golf:
            return .mint
        case .tennis:
            return .yellow
        case .racing:
            return .red
        }
    }

    var displayName: String {
        switch self {
        case .soccer:
            return "Soccer"
        case .basketball:
            return "Basketball"
        case .hockey:
            return "Hockey"
        case .mlb:
            return "Baseball"
        case .nfl:
            return "Football"
        case .golf:
            return "Golf"
        case .tennis:
            return "Tennis"
        case .racing:
            return "Formula 1"
        }
    }
}

extension Color {
    static var secondaryGroupedBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
