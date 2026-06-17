//
//  SportType.swift
//  SportsCal
//
//  Created by Umar Haroon on 10/23/22.
//

import Foundation
public enum SportType: String, CaseIterable {
    case basketball
    case soccer
    case hockey
    case mlb
    case nfl
    case golf
    case tennis
    case racing

    public init(league: Leagues) {
        switch league {
        case .nfl:
            self = .nfl
        case .nba, .ncaaMBBTournament, .wnba:
            self = .basketball
        case .nhl:
            self = .hockey
        case .mlb:
            self = .mlb
        case .pga:
            self = .golf
        case .atp, .wta:
            self = .tennis
        case .formula1:
            self = .racing
        default:
            self = .soccer
        }
    }
    /// Whether a score change in this sport is worth a haptic / alerting
    /// notification. Limited to low-frequency, high-value scoring events so we
    /// don't spam the user — a basket every 30s in basketball, or the continuous
    /// scoring in individual sports (golf/tennis/F1), would be noise.
    /// Shared by the iOS foreground haptic and the server's alerting Live
    /// Activity push so the two never disagree.
    public var alertsOnScoreChange: Bool {
        switch self {
        case .soccer, .hockey, .nfl:
            return true
        case .basketball, .mlb, .golf, .tennis, .racing:
            return false
        }
    }
    public var capitalized: String {
        switch self {
        case .basketball:
            return "NBA"
        case .soccer:
            return "Soccer"
        case .hockey:
            return "NHL"
        case .mlb:
            return "MLB"
        case .nfl:
            return "NFL"
        case .golf:
            return "PGA"
        case .tennis:
            return "Tennis"
        case .racing:
            return "F1"
        }
    }
}

