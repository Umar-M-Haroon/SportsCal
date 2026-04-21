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
                .foregroundColor(.red)
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

    init?(hex: String?) {
        guard let hex = hex else { return nil }
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

// MARK: - Game Card Styling

struct GameCardModifier: ViewModifier {
    let game: Game
    let isLive: Bool

    private var sportColor: Color {
        guard let id = game.idLeague, let intID = Int(id),
              let league = Leagues(rawValue: intID) else { return .gray }
        return SportType(league: league).color
    }

    func body(content: Content) -> some View {
        content
            .listRowBackground(sportColor.opacity(0.15))
            .listRowSeparator(.hidden)
    }
}

extension View {
    func gameCard(game: Game, isLive: Bool) -> some View {
        modifier(GameCardModifier(game: game, isLive: isLive))
    }
}
